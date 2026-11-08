import QtQuick 2.12
import WebOS.Global 1.0
import "."
import "HubModel.js" as HubModel

// A device's detail as a modal, after K3-Home-A-Heizung: 720 wide, glass, the device's
// symbol, name and line, then what left and right set (target temperature, brightness,
// blind position), then the buttons. Up and down move between the value and the
// buttons, OK presses a button, Back closes.
FocusScope {
    id: detail

    property real unit: 1
    property string titleFamily: ""
    property string rowFamily: ""
    property Item backdropItem
    property var device: null
    property bool shown: false
    signal closed()
    signal changeRequested(var device, string resourceId, var value, bool soon)

    readonly property var standardCurve: GlassStyle.curve
    readonly property bool reachable: !!device && HubModel.reachable(device)
    readonly property var setting: device && reachable ? HubModel.adjustable(device) : null
    property real pending: NaN
    readonly property real value: isNaN(pending) ? (setting ? setting.shown : 0) : pending
    readonly property var buttons: {
        var list = [];
        if (device && reachable) {
            if (HubModel.lockResource(device) !== "" && HubModel.resource(device, HubModel.lockResource(device)).writable)
                list.push({ key: "lock", text: tr(HubModel.isLocked(device) ? "action.unlock" : "action.lock") });
            else if (HubModel.powerResource(device) !== "")
                list.push({ key: "power", text: tr(HubModel.isOn(device) ? "action.turn_off" : "action.turn_on") });
        }
        list.push({ key: "done", text: I18n.t("global", "done") });
        return list;
    }
    readonly property var entries: (setting ? ["value"] : []).concat(buttons.map(function (entry) { return entry.key; }))
    property int focusIndex: 0
    readonly property string focusedEntry: entries[Math.min(focusIndex, entries.length - 1)]
    property int nudged: 0              // -1 or 1 while a stepper button lights up

    function tr(key, params) { return I18n.t("hub", key, params); }

    function open() {
        pending = NaN;
        focusIndex = 0;
        shown = true;
        forceActiveFocus();
    }

    // The hub is a focus scope: as long as this modal keeps its focus inside it, the
    // hub's own keys stay dead, also after the modal has faded out.
    function close() {
        focus = false;
        if (!shown) return;
        shown = false;
        closed();
    }

    function adjust(direction) {
        if (!setting) return;
        var next = Math.round((value + direction * setting.step) / setting.step) * setting.step;
        next = Math.max(setting.min, Math.min(setting.max, next));
        nudged = direction;
        nudgeTimer.restart();
        if (next === value) return;
        pending = next;
        changeRequested(device, setting.resourceId, HubModel.rawValue(setting, next), true);
        // Brightness on a light that is off switches it on, as the lamps themselves do.
        if (setting.kind === "level" && !HubModel.isOn(device) && HubModel.powerResource(device) !== "")
            changeRequested(device, HubModel.powerResource(device), HubModel.toggleValue(device), false);
    }

    function press() {
        if (focusedEntry === "lock") {
            changeRequested(device, HubModel.lockResource(device), HubModel.lockValue(device, !HubModel.isLocked(device)), false);
        } else if (focusedEntry === "power") {
            changeRequested(device, HubModel.powerResource(device), HubModel.toggleValue(device), false);
        } else {
            close();
        }
    }

    function isBack(key) {
        return Remote.isBack(key);
    }

    Keys.onPressed: {
        var ok = Remote.isOk(event.key);
        if (event.key === Qt.Key_Up) focusIndex = Math.max(0, focusIndex - 1);
        else if (event.key === Qt.Key_Down) focusIndex = Math.min(entries.length - 1, focusIndex + 1);
        else if (event.key === Qt.Key_Left) { if (focusedEntry === "value") adjust(-1); }
        else if (event.key === Qt.Key_Right) { if (focusedEntry === "value") adjust(1); }
        // A held OK that opened this modal keeps repeating; only a new press counts.
        else if (ok) { if (!event.isAutoRepeat) press(); }
        event.accepted = true;
    }

    Keys.onReleased: {
        if (isBack(event.key)) close();
        event.accepted = true;
    }

    Timer {
        id: nudgeTimer
        interval: 160
        onTriggered: detail.nudged = 0
    }

    visible: opacity > 0
    opacity: shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: detail.standardCurve }
    }

    Rectangle {
        anchors.fill: parent
        color: "#8c040608"
    }

    ImageGlass {
        id: cardGlass
        sourceItem: detail.backdropItem
        unit: detail.unit
        area: Qt.rect(card.x, card.y, card.width, card.height)
        visible: false
    }

    GlassCard {
        id: card
        x: (detail.width - width) / 2
        y: (detail.height - height) / 2
        width: 720 * detail.unit
        height: content.height + 88 * detail.unit
        unit: detail.unit
        backdrop: cardGlass.texture
        glassShader: GlassStyle.glassShader
        backdropMargin: cardGlass.margin
        backdropArea: cardGlass.area
        hasBackdrop: 1
        shadow: "shadow-modal"
        scale: detail.shown ? 1 : 0.96

        Behavior on scale {
            NumberAnimation { duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: detail.standardCurve }
        }

        Column {
            id: content
            x: 40 * detail.unit
            y: 48 * detail.unit
            width: parent.width - 80 * detail.unit

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 88 * detail.unit
                height: 88 * detail.unit

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#24ffffff"
                }

                BorderImage {
                    anchors.fill: parent
                    opacity: Math.min(1, GlassStyle.edgeGain)
                    source: Qt.resolvedUrl("icons/edge-44.png")
                    border { left: 45; top: 45; right: 45; bottom: 45 }
                }

                Image {
                    anchors.centerIn: parent
                    width: 48 * detail.unit
                    height: 48 * detail.unit
                    source: detail.device ? Qt.resolvedUrl("icons/device-" + HubModel.kind(detail.device) + "-48.png") : ""
                }
            }

            Item { width: 1; height: 28 * detail.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: detail.device ? detail.device.alias || detail.tr("type." + HubModel.kind(detail.device)) : ""
                color: "#ffffff"
                font.family: detail.titleFamily
                font.pixelSize: 36 * detail.unit
                font.weight: Font.Bold
                font.letterSpacing: -0.72 * detail.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Item { width: 1; height: 10 * detail.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: {
                    if (!detail.device) return "";
                    var line = HubModel.detailLine(detail.device, detail.tr);
                    return HubModel.remoteOff(detail.device) ? line + " · " + detail.tr("hint.remote_off") : line;
                }
                color: "#c7ffffff"
                font.family: detail.rowFamily
                font.pixelSize: 22 * detail.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            // The value with its two stepper buttons.
            Item {
                width: parent.width
                height: detail.setting ? 32 * detail.unit + stepper.height + 42 * detail.unit : 0
                visible: !!detail.setting

                Row {
                    id: stepper
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 32 * detail.unit
                    spacing: 20 * detail.unit

                    Repeater {
                        model: [-1, 0, 1]

                        Item {
                            readonly property bool box: modelData === 0
                            readonly property bool focused: detail.focusedEntry === "value"
                            width: (box ? 280 : 72) * detail.unit
                            height: (box ? 128 : 72) * detail.unit
                            anchors.verticalCenter: parent.verticalCenter
                            scale: box && focused ? 1.03 : (detail.nudged !== 0 && detail.nudged === modelData ? 0.92 : 1)

                            Behavior on scale {
                                NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: detail.standardCurve }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: (parent.box ? 40 : 36) * detail.unit
                                color: parent.box ? (parent.focused ? GlassStyle.focusFill : "#24ffffff") :
                                       (detail.nudged === modelData ? "#40ffffff" : "#1fffffff")

                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            BorderImage {
                                anchors.fill: parent
                                visible: !parent.box
                                opacity: Math.min(1, GlassStyle.edgeGain)
                                source: Qt.resolvedUrl("icons/edge-36.png")
                                border { left: 37; top: 37; right: 37; bottom: 37 }
                            }

                            Image {
                                visible: !parent.box
                                anchors.centerIn: parent
                                width: 28 * detail.unit
                                height: 28 * detail.unit
                                source: Qt.resolvedUrl(modelData < 0 ? "icons/minus-28.png" : "icons/plus-28.png")
                            }

                            Column {
                                visible: parent.box
                                anchors.centerIn: parent

                                SectionTitle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: implicitHeight
                                    unit: detail.unit
                                    text: detail.setting ? detail.tr("label." + detail.setting.kind) : ""
                                    color: parent.parent.focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: detail.setting ? HubModel.shownText(detail.setting, detail.value) : ""
                                    color: parent.parent.focused ? GlassStyle.focusText : "#ffffff"
                                    font.family: detail.titleFamily
                                    font.pixelSize: 64 * detail.unit
                                    font.weight: Font.Bold
                                    font.letterSpacing: -1.28 * detail.unit
                                    font.hintingPreference: Font.PreferNoHinting
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: detail.setting ? detail.tr("hint." + detail.setting.kind) : ""
                    color: GlassStyle.textSecondary
                    font.family: detail.rowFamily
                    font.pixelSize: 18 * detail.unit
                    font.hintingPreference: Font.PreferNoHinting
                }
            }

            Item { width: 1; height: 32 * detail.unit }

            Column {
                width: parent.width
                spacing: 12 * detail.unit

                Repeater {
                    model: detail.buttons

                    Item {
                        readonly property bool focused: detail.focusedEntry === modelData.key
                        width: parent.width
                        height: 72 * detail.unit
                        scale: focused ? GlassStyle.focusScale : 1

                        Behavior on scale {
                            NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: detail.standardCurve }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: parent.focused ? GlassStyle.focusFill : "#1fffffff"

                            Behavior on color { ColorAnimation { duration: 180 } }
                        }

                        BorderImage {
                            anchors.fill: parent
                            visible: !parent.focused
                            opacity: Math.min(1, GlassStyle.edgeGain)
                            source: Qt.resolvedUrl("icons/edge-36.png")
                            border { left: 37; top: 37; right: 37; bottom: 37 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.text
                            color: parent.focused ? GlassStyle.focusText : "#ffffff"
                            font.family: detail.titleFamily
                            font.pixelSize: 22 * detail.unit
                            font.weight: Font.DemiBold
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }
        }
    }
}
