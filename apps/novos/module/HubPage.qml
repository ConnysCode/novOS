import QtQuick 2.12
import WebOS.Global 1.0
import WebOSServices 1.0
import "."
import "HubModel.js" as HubModel
import "HubDemo.js" as HubDemo
import "ListScroll.js" as ListScroll

// Smart home hub after K3-Home-A ("stage and shelf", like the launcher). Above, the stage
// describes what the focus means: a room with its summary, or a device with its state.
// Below, one glass shelf: rooms as chips, the room's devices as tiles. OK switches a
// device that has a switch, a long OK opens its detail (a short one, if it has no
// switch); Back goes back. Data comes from LG's
// com.webos.service.homeconnect, which serves ThinQ, Matter and other brands alike;
// relayEvent keeps it current, and a get every 20 s lets it fetch ThinQ states.
FocusScope {
    id: hub

    property real unit: 1
    property string titleFamily: ""
    property string rowFamily: ""
    property string valueFamily: ""
    property string timeText: ""
    property string dateText: ""
    property url backgroundSource
    property string backgroundCredit: ""
    signal backRequested()

    readonly property var standardCurve: GlassStyle.curve
    readonly property string service_: "luna://com.webos.service.homeconnect"
    readonly property int tilePitch: 236

    property var realRooms: []
    property var realDevices: []
    // The made-up home of the debug menu, kept while the hub is open.
    property bool demoOn: false
    property var demoDevices: []
    readonly property var rooms: [{ id: "", name: tr("room.all") }].concat(realRooms,
                                 demoOn ? HubDemo.rooms(tr) : [])
    readonly property var devices: demoOn ? realDevices.concat(demoDevices) : realDevices
    readonly property bool ready: loaded || (demoOn && devices.length > 0)
    property string homeName: ""
    property bool loaded: false
    property bool failed: false
    property bool subscribed: false
    property int roomIndex: 0
    property int deviceIndex: 0
    property int row: 0                 // 0 rooms, 1 devices
    property real tileScroll: 0
    property string detailId: ""
    property bool okDown: false
    property bool okHeld: false
    property var pendingSend: null

    readonly property var room: rooms[Math.min(roomIndex, rooms.length - 1)]
    readonly property var roomDevices: HubModel.inRoom(devices, room ? room.id : "")
    readonly property var focusedDevice: row === 1 && roomDevices.length > 0 ?
                                         roomDevices[Math.min(deviceIndex, roomDevices.length - 1)] : null

    function tr(key, params) { return I18n.t("hub", key, params); }

    // The debug menu's switch lives in the debug file; the hub reads it each time it opens.
    function readDemo() {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", "file:///tmp/novos-debug.ini", false);
            request.send();
            return /demoDevices=true/.test(request.responseText);
        } catch (error) {
            return false;
        }
    }

    function open() {
        demoOn = readDemo();
        if (demoOn && demoDevices.length === 0) demoDevices = HubDemo.devices(tr);
        detail.close();
        okDown = false;
        row = 0;
        roomIndex = 0;
        deviceIndex = 0;
        tileScroll = 0;
        if (ready && roomDevices.length > 0) row = 1;
        request();
        pollTimer.restart();
        loadTimeout.restart();
        forceActiveFocus();
    }

    function stop() {
        pollTimer.stop();
        loadTimeout.stop();
        detail.close();
        sendNow();
    }

    function request() {
        service.call(service_, "/get", JSON.stringify({ type: "homeList" }));
        service.call(service_, "/get", JSON.stringify({ type: "iotList" }));
        if (!subscribed) {
            subscribed = true;
            service.call(service_, "/relayEvent", JSON.stringify({ subscribe: true }));
        }
    }

    function applyHomes(response) {
        var homes = response.homeList || [];
        var current = null;
        for (var i = 0; i < homes.length; ++i) {
            if (homes[i].homeId === response.currentHome) current = homes[i];
        }
        current = current || homes[0];
        homeName = current ? current.homeName || "" : "";
        var list = [];
        ((current && current.rooms) || []).forEach(function (entry) {
            list.push({ id: entry.roomId, name: entry.roomName });
        });
        realRooms = list;
        if (roomIndex >= rooms.length) roomIndex = 0;
    }

    function applyDevices(list) {
        var first = !ready;
        realDevices = list || [];
        loaded = true;
        failed = false;
        loadTimeout.stop();
        // The focus starts on the devices, the design's "last used device".
        if (first && roomDevices.length > 0) row = 1;
        if (deviceIndex >= roomDevices.length) deviceIndex = Math.max(0, roomDevices.length - 1);
    }

    function handle(method, response) {
        if (method === "/relayEvent") {
            var event = response;
            if (event.type === "initial") {
                var data = event.response || {};
                if (data.homeList) applyHomes(data);
                if (data.iotList) applyDevices(data.iotList);
            } else if (event.type) {
                refreshTimer.restart();
            }
            return;
        }
        var body = response.response || {};
        if (body.homeList) applyHomes(body);
        if (body.iotList) applyDevices(body.iotList);
    }

    function withValue(list, deviceId, resourceId, value) {
        var copy = JSON.parse(JSON.stringify(list));
        copy.forEach(function (entry) {
            if (entry.deviceId === deviceId && entry.resources && entry.resources[resourceId])
                entry.resources[resourceId].value = value;
        });
        return copy;
    }

    // Sets one resource. A demo device only changes here; a real one gets set operate
    // from LG's service, values from the left and right keys once they rest for 0.5 s.
    function setResource(device, resourceId, value, soon) {
        if (HubDemo.isDemo(device)) {
            demoDevices = withValue(demoDevices, device.deviceId, resourceId, value);
            return;
        }
        var option = { deviceId: device.deviceId, control: [{ resourceId: resourceId, value: value }] };
        if (device.endpointId) option.endpointId = device.endpointId;
        if (pendingSend && (pendingSend.deviceId !== option.deviceId ||
                            pendingSend.control[0].resourceId !== resourceId)) sendNow();
        pendingSend = option;
        if (soon) sendTimer.restart();
        else sendNow();
        // Shown at once; the next event brings the device's own word.
        realDevices = withValue(realDevices, device.deviceId, resourceId, value);
    }

    function sendNow() {
        sendTimer.stop();
        if (!pendingSend) return;
        service.call(service_, "/set", JSON.stringify({ type: "operate", option: pendingSend }));
        pendingSend = null;
    }

    readonly property var detailDevice: {
        for (var i = 0; i < devices.length; ++i) {
            if (devices[i].deviceId === detailId) return devices[i];
        }
        return null;
    }

    function openDetail(device) {
        if (!device || !HubModel.hasDetail(device)) return;
        detailId = device.deviceId;
        detail.open();
    }

    // OK on a room goes down to its devices, OK on a device with a switch switches it,
    // on any other device it opens the detail.
    function activate() {
        if (row === 0) {
            if (roomDevices.length > 0) row = 1;
            return;
        }
        var device = focusedDevice;
        if (!device) return;
        var resourceId = HubModel.powerResource(device);
        if (resourceId === "" || !HubModel.reachable(device)) {
            openDetail(device);
            return;
        }
        setResource(device, resourceId, HubModel.toggleValue(device), false);
    }

    function move(step) {
        if (row === 0) {
            var next = Math.max(0, Math.min(rooms.length - 1, roomIndex + step));
            if (next !== roomIndex) {
                roomIndex = next;
                deviceIndex = 0;
                tileScroll = 0;
            }
        } else {
            deviceIndex = Math.max(0, Math.min(roomDevices.length - 1, deviceIndex + step));
            var visible = (1808 - 56) * unit;
            var content = (roomDevices.length * tilePitch - (tilePitch - 224)) * unit;
            tileScroll = ListScroll.centred(deviceIndex * tilePitch * unit, 224 * unit, visible, content);
        }
    }

    function isBack(key) {
        return Remote.isBack(key);
    }

    function isOk(key) {
        return Remote.isOk(key);
    }

    // OK acts on its release, so that holding it can open the detail instead.
    Keys.onPressed: {
        if (event.key === Qt.Key_Left) move(-1);
        else if (event.key === Qt.Key_Right) move(1);
        else if (event.key === Qt.Key_Up) row = 0;
        else if (event.key === Qt.Key_Down) { if (roomDevices.length > 0) row = 1; }
        else if (isOk(event.key)) {
            if (!event.isAutoRepeat) {
                okDown = true;
                okHeld = false;
                if (row === 1) holdTimer.restart();
            }
        }
        else if (!isBack(event.key)) return;
        event.accepted = true;
    }

    Keys.onReleased: {
        if (isBack(event.key)) {
            event.accepted = true;
            hub.backRequested();
        } else if (isOk(event.key) && !event.isAutoRepeat) {
            event.accepted = true;
            holdTimer.stop();
            if (okDown && !okHeld) activate();
            okDown = false;
        }
    }

    Timer {
        id: holdTimer
        interval: 550
        onTriggered: {
            if (!hub.okDown) return;
            hub.okHeld = true;
            hub.openDetail(hub.focusedDevice);
        }
    }

    Timer {
        id: sendTimer
        interval: 500
        onTriggered: hub.sendNow()
    }

    Service {
        id: service
        appId: "com.webos.app.store-streamer"
        onResponse: {
            try {
                hub.handle(method, JSON.parse(payload));
            } catch (error) {
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 20000
        repeat: true
        onTriggered: service.call(hub.service_, "/get", JSON.stringify({ type: "iotList" }))
    }

    Timer {
        id: refreshTimer
        interval: 300
        onTriggered: service.call(hub.service_, "/get", JSON.stringify({ type: "iotList" }))
    }

    // LG's service starts on the first call and may take a while.
    Timer {
        id: loadTimeout
        interval: 20000
        onTriggered: if (!hub.loaded) hub.failed = true
    }

    Rectangle {
        anchors.fill: parent
        color: "#02040a"
    }

    // What the glass blurs: the picture with its scrims, as the eye sees it.
    Item {
        id: backdrop
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#02040a"
        }

        Image {
            id: picture
            anchors.fill: parent
            source: hub.backgroundSource
            sourceSize: Qt.size(1920, 1080)
            fillMode: Image.PreserveAspectCrop
        }

        BackdropScrim {
            anchors.fill: parent
            unit: hub.unit
        }
    }

    // The glass hides the backdrop it blurs, so the picture is drawn again here, as it is.
    ShaderEffect {
        anchors.fill: parent
        property variant source: picture
    }

    ImageGlass {
        id: shelfGlass
        sourceItem: backdrop
        unit: hub.unit
        area: Qt.rect(shelf.x, shelf.y, shelf.width, shelf.height)
        visible: false
    }

    BackdropScrim {
        anchors.fill: parent
        unit: hub.unit
    }

    Column {
        anchors.right: parent.right
        anchors.rightMargin: 96 * hub.unit
        y: 64 * hub.unit
        spacing: 2 * hub.unit

        Text {
            anchors.right: parent.right
            text: hub.timeText
            color: "#ffffff"
            font.family: hub.titleFamily
            font.pixelSize: 32 * hub.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            anchors.right: parent.right
            text: hub.dateText
            color: GlassStyle.textGlance
            font.family: hub.valueFamily
            font.pixelSize: 18 * hub.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    // The stage.
    Item {
        x: 96 * hub.unit
        width: 1300 * hub.unit
        height: shelf.y

        Column {
            id: stage
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 10 * hub.unit

            readonly property var device: hub.focusedDevice
            readonly property bool roomStage: hub.row === 0 || !device

            Text {
                text: {
                    if (!hub.ready) return hub.tr("title.smart_home");
                    if (stage.roomStage) return hub.roomIndex === 0 ? hub.tr("eyebrow.home") : hub.tr("eyebrow.room");
                    var roomOf = hub.rooms.filter(function (entry) { return entry.id && entry.id === stage.device.roomId; });
                    return roomOf.length > 0 ? roomOf[0].name : hub.tr("type." + HubModel.kind(stage.device));
                }
                color: GlassStyle.textSecondary
                font.family: hub.titleFamily
                font.pixelSize: 18 * hub.unit
                font.letterSpacing: 1.08 * hub.unit
                font.capitalization: Font.AllUppercase
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (hub.failed && !hub.ready) return hub.tr("unreachable.title");
                    if (!hub.ready) return hub.tr("loading");
                    if (hub.devices.length === 0) return hub.tr("empty.title");
                    if (stage.roomStage) return hub.roomIndex === 0 && hub.homeName !== "" ? hub.homeName : hub.room.name;
                    return stage.device.alias || hub.tr("type." + HubModel.kind(stage.device));
                }
                color: "#ffffff"
                font.family: hub.titleFamily
                font.pixelSize: 72 * hub.unit
                font.weight: Font.Bold
                font.letterSpacing: -1.8 * hub.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (hub.failed && !hub.ready) return hub.tr("unreachable.detail");
                    if (!hub.ready) return "";
                    if (hub.devices.length === 0) return hub.tr("empty.detail");
                    if (stage.roomStage) return HubModel.roomSummary(hub.roomDevices, hub.tr);
                    var line = HubModel.stateText(stage.device, hub.tr);
                    return HubModel.remoteOff(stage.device) ? line + " · " + hub.tr("hint.remote_off") : line;
                }
                color: GlassStyle.textRaised
                font.family: hub.rowFamily
                font.pixelSize: 26 * hub.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            // What OK does here: a key cap and its meaning, for a short and a long OK.
            Row {
                readonly property bool switches: !stage.roomStage && HubModel.powerResource(stage.device) !== "" &&
                                                 HubModel.reachable(stage.device)
                readonly property bool details: !stage.roomStage && HubModel.hasDetail(stage.device)
                readonly property var hints: {
                    if (stage.roomStage) return hub.roomDevices.length > 0 ? [["▼", hub.tr("hint.devices")]] : [];
                    var list = [];
                    if (switches) list.push(["OK", hub.tr("hint.toggle")]);
                    if (details) list.push([switches ? hub.tr("key.hold_ok") : "OK", hub.tr("hint.details")]);
                    return list;
                }
                topPadding: 14 * hub.unit
                spacing: 32 * hub.unit
                visible: hub.ready && hints.length > 0

                Repeater {
                    model: parent.hints

                    Row {
                        spacing: 12 * hub.unit

                        Rectangle {
                            width: capText.width + 20 * hub.unit
                            height: 30 * hub.unit
                            radius: 9 * hub.unit
                            color: "transparent"
                            border.width: 1.5 * hub.unit
                            border.color: GlassStyle.optionRing

                            Text {
                                id: capText
                                anchors.centerIn: parent
                                text: modelData[0]
                                color: "#ffffff"
                                font.family: hub.titleFamily
                                font.pixelSize: 16 * hub.unit
                                font.hintingPreference: Font.PreferNoHinting
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: GlassStyle.textRaised
                            font.family: hub.rowFamily
                            font.pixelSize: 20 * hub.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 96 * hub.unit
        y: 592 * hub.unit
        visible: hub.backgroundCredit !== ""
        text: I18n.t("launcher", "label.image_credit", { credit: hub.backgroundCredit })
        color: GlassStyle.textFaint
        font.family: hub.rowFamily
        font.pixelSize: 16 * hub.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    // The shelf: rooms above, the room's devices below.
    GlassCard {
        id: shelf
        x: 56 * hub.unit
        y: hub.height - height - 56 * hub.unit
        width: 1808 * hub.unit
        height: 386 * hub.unit
        unit: hub.unit
        backdrop: shelfGlass.texture
        glassShader: GlassStyle.glassShader
        backdropMargin: shelfGlass.margin
        backdropArea: shelfGlass.area
        hasBackdrop: 1
        shadow: "shadow-panel"

        SectionTitle {
            x: 36 * hub.unit
            y: 24 * hub.unit
            unit: hub.unit
            text: hub.tr("label.rooms")
        }

        Row {
            x: 28 * hub.unit
            y: 58 * hub.unit
            spacing: 10 * hub.unit

            Repeater {
                model: hub.rooms

                Item {
                    readonly property bool focused: hub.row === 0 && hub.roomIndex === index
                    readonly property bool selected: hub.roomIndex === index
                    width: chipText.width + 44 * hub.unit
                    height: 56 * hub.unit
                    scale: focused ? GlassStyle.focusScale : 1

                    Behavior on scale {
                        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: hub.standardCurve }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: parent.focused ? GlassStyle.focusFill : (parent.selected ? GlassStyle.fillSelected : GlassStyle.fillRest)

                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    BorderImage {
                        anchors.fill: parent
                        visible: !parent.focused
                        opacity: Math.min(1, GlassStyle.edgeGain)
                        source: Qt.resolvedUrl("icons/edge-28.png")
                        border { left: 29; top: 29; right: 29; bottom: 29 }
                    }

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.name
                        color: parent.focused ? GlassStyle.focusText : "#ffffff"
                        font.family: hub.titleFamily
                        font.pixelSize: 19 * hub.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }
        }

        SectionTitle {
            x: 36 * hub.unit
            y: 138 * hub.unit
            unit: hub.unit
            text: hub.tr("label.devices_in", { room: hub.room ? hub.room.name : "" })
        }

        Item {
            x: 0
            y: 168 * hub.unit
            width: parent.width
            height: 204 * hub.unit
            clip: true

            Row {
                x: 28 * hub.unit - hub.tileScroll
                y: 6 * hub.unit
                spacing: 12 * hub.unit

                Behavior on x {
                    NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: hub.standardCurve }
                }

                Repeater {
                    model: hub.roomDevices

                    DeviceTile {
                        unit: hub.unit
                        focused: hub.row === 1 && hub.deviceIndex === index
                        kind: HubModel.kind(modelData)
                        name: modelData.alias || hub.tr("type." + kind)
                        stateLine: HubModel.stateText(modelData, hub.tr)
                        active: HubModel.reachable(modelData) && HubModel.isOn(modelData)
                        reachable: HubModel.reachable(modelData)
                        hasSwitch: HubModel.powerResource(modelData) !== ""
                        titleFamily: hub.titleFamily
                        rowFamily: hub.rowFamily
                    }
                }
            }
        }
    }

    HubDetail {
        id: detail
        anchors.fill: parent
        unit: hub.unit
        titleFamily: hub.titleFamily
        rowFamily: hub.rowFamily
        backdropItem: backdrop
        device: hub.detailDevice
        onClosed: {
            hub.detailId = "";
            hub.sendNow();
            hub.forceActiveFocus();
        }
        onChangeRequested: hub.setResource(device, resourceId, value, soon)
    }
}
