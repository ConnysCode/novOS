import QtQuick 2.12
import WebOSServices 1.0
import "."
import "SettingsEngine.js" as Engine
import "DeviceList.js" as DeviceList

// Bluetooth devices of the settings: headphones and speakers through LG's btaudiosrc (TON-B,
// Ton › Audioausgabe), Bluetooth speakers together with the TV speaker (TON-D, Bluetooth und
// Fernsehlautsprecher: btaudiosrc/surround) and gamepads, keyboards and mice through
// bthidmanager (QG-1, Quellen › Bluetooth-Geräte). Every call is the one LG's own settings app makes (main.js of
// com.palm.app.settings, webOS 10.3.2: SoundBluetooth and ConnectBluetooth); where it
// differs it says why. The lists land in the settings store for the device list
// (DeviceList.js): bluetooth, bluetoothFound, btSurround, bluetoothInput, bluetoothInputFound.
//
// The pages decide when it talks to the services: a page with session "btAudio", "btAudioPair",
// "btAudioDevice", "btSurround", "btInput" or "btInputDevice" keeps its subscriptions while it is in the stack
// of the modal (SettingsModal.sessions). Everything that changes something goes through act().
Item {
    id: bt

    property var settings: null
    readonly property var sessions: settings ? settings.sessions : []

    // Preview only (PREVIEW_MODULE_SED): made-up devices in the states of the boards, and no
    // call reaches LG. demoScene picks a state, demoHold keeps running steps from ending.
    property bool demo: false
    property string demoScene: ""
    property bool demoHold: false

    readonly property string audioUri: "luna://com.webos.service.btaudiosrc"
    readonly property string hidUri: "luna://com.webos.service.bthidmanager"
    readonly property int connectLimit: 30000      // LG's spinner for input devices; audio as well
    readonly property int answerLimit: 5000        // no answer by then: the service is not there
    readonly property int menuDelay: 500           // LG waits as long after onDeviceSelectionMenu
    readonly property int volumeDelay: 120         // the volume goes out once the key rests
    readonly property int inputLimit: 4            // LG: "up to 4 input devices"
    readonly property string surroundUri: "luna://com.webos.service.btaudiosrc/surround"
    // Positions of a speaker beside the TV speaker, as btaudiosrc names them in "surround".
    readonly property var positions: ["left", "right", "front", "rear"]

    readonly property var actionNames: ["btAudioConnect", "btAudioDisconnect", "btAudioRemove", "btAudioSearch",
                                        "btAudioUse", "btAudioVolume", "btInputConnect", "btInputDisconnect",
                                        "btInputRemove", "btInputSearch", "btInputPick", "btSurroundPosition",
                                        "btSurroundLevel", "btSurroundBalance", "btSurroundReset",
                                        "btSurroundHearing"]

    // What the services reported, before it becomes the store's lists.
    property var audioPaired: []        // getPairedDevices, only entries with display
    property var audioFound: []         // startDiscovery and getDeviceStatus (listType discovered)
    property var inputPaired: []        // getPairedDeviceLists without its empty places
    property var inputFound: []         // subscribeDiscovery
    property bool audioSearching: false
    property bool inputSearching: false
    property var audioReady: undefined  // true once getPairedDevices answered, false without answer
    property var inputReady: undefined
    property var volumes: ({})          // address -> getDeviceVolume
    // address -> { name, kind, list: "audio" | "input", job: "connect" | "disconnect", output }
    property var jobs: ({})
    property var failed: ({})           // address -> true until it is tried again
    property var lastAudioState: ({})   // address -> state, to see connecting end in disconnected
    // surround/getVolumeBalancing: tvspeaker_bluetooth (0–10) and bluetooth_left_right (0–10, 5
    // the middle); undefined until it answers. LG asks only while a device is connected.
    property var balancing: ({})

    function has(name) {
        for (var i = 0; i < sessions.length; i++) {
            if (sessions[i] === name || sessions[i].indexOf(name + ":") === 0) return true;
        }
        return false;
    }

    function paramOf(name) {
        for (var i = 0; i < sessions.length; i++) {
            if (sessions[i].indexOf(name + ":") === 0) return sessions[i].substring(name.length + 1);
        }
        return "";
    }

    readonly property bool audioOpen: has("btAudio") || has("btAudioPair") || has("btAudioDevice")
    readonly property bool pairOpen: has("btAudioPair")
    readonly property string audioDevice: paramOf("btAudioDevice")
    readonly property bool inputOpen: has("btInput") || has("btInputDevice")
    readonly property bool surroundOpen: has("btSurround")
    // The first connected speaker of Bluetooth und Fernsehlautsprecher, and with a hearing aid
    // over Bluetooth (BF-1) the one whose device volume the page sets (LG's jte()). Set by
    // publish(): the store's values are no QML properties.
    property string surroundConnected: ""
    property string hearingDevice: ""
    readonly property string volumeDevice: audioDevice !== "" ? audioDevice : hearingDevice
    onSurroundOpenChanged: publish()
    property bool audioListening: false     // the subscriptions run, 500 ms after the menu flag
    property bool audioDiscovering: false   // the startDiscovery subscription runs

    function runs(name) {
        return actionNames.indexOf(name) >= 0;
    }

    function t(areaId, key, params) {
        return Engine.text(I18n, areaId, key, params);
    }

    // ---- Calls -----------------------------------------------------------------------------

    // Everything that changes a device or a service goes through here; a preview cuts it off.
    function act(uri, method, params) {
        if (demo) {
            demoAct(method, params || {});
            return;
        }
        actionService.call(uri, method, JSON.stringify(params || {}));
    }

    function read(uri, method, params) {
        if (demo) return;
        readService.call(uri, method, JSON.stringify(params || {}));
    }

    // Read once when the modal opens: the rows of Audioausgabe and Quellen need the lists before
    // any of their pages is open.
    function request() {
        if (demo) {
            demoStart();
            return;
        }
        read(audioUri, "/getPairedDevices", {});
        read(hidUri, "/getPairedDeviceLists", {});
        readyTimer.restart();
    }

    Timer {
        id: readyTimer
        interval: bt.answerLimit
        onTriggered: {
            if (bt.audioReady === undefined) bt.audioReady = false;
            if (bt.inputReady === undefined) bt.inputReady = false;
            bt.publish();
        }
    }

    Service {
        id: readService
        appId: "com.webos.app.quicksettings"
        onResponse: bt.answer(method, JSON.parse(payload))
        onError: bt.answer(method, { returnValue: false })
    }

    Service {
        id: actionService
        appId: "com.webos.app.quicksettings"
        onResponse: bt.acted(method, JSON.parse(payload))
        onError: bt.acted(method, { returnValue: false })
    }

    function answer(method, response) {
        if (method === "/getPairedDevices") applyAudioPaired(response);
        else if (method === "/getDeviceStatus") applyAudioStatus(response);
        else if (method === "/startDiscovery") applyAudioDiscovery(response);
        else if (method === "/getDeviceVolume") applyVolume(response);
        else if (method === "/getVolumeBalancing") applyBalancing(response);
        else if (method === "/getPairedDeviceLists") applyInputPaired(response);
        else if (method === "/subscribeDevicesStatus") applyInputStatus(response);
        else if (method === "/subscribeDiscovery") applyInputDiscovery(response);
    }

    // A refused change ends its job at once.
    function acted(method, response) {
        if (response.returnValue !== false) return;
        for (var address in jobs) {
            var job = jobs[address];
            if ((method === "/connect" || method === "/requestConnect") && job.job === "connect") fail(address);
            else if ((method === "/disconnect" || method === "/requestDisconnect") && job.job === "disconnect") endJob(address);
        }
    }

    // ---- Sessions -----------------------------------------------------------------------------

    // LG's SoundBluetooth: onDeviceSelectionMenu {state:true}, after 500 ms getDeviceStatus and
    // getPairedDevices as subscriptions; on leaving the subscriptions end and the flag goes back.
    onAudioOpenChanged: {
        if (audioOpen) {
            act(audioUri, "/onDeviceSelectionMenu", { state: true });
            menuTimer.restart();
        } else {
            menuTimer.stop();
            audioListening = false;
            stopAudioSearch();
            act(audioUri, "/onDeviceSelectionMenu", { state: false });
        }
    }

    Timer {
        id: menuTimer
        interval: bt.menuDelay
        onTriggered: bt.audioListening = !bt.demo
    }

    // "Neues Gerät koppeln" searches as soon as it opens; leaving it ends the search.
    onPairOpenChanged: {
        if (pairOpen) startAudioSearch();
        else stopAudioSearch();
    }

    // QG-1, as LG's ConnectBluetooth: subscribeDiscovery and subscribeDevicesStatus, the list,
    // and a search when no device is connected. Leaving cancels the search (cancelDiscovery).
    onInputOpenChanged: {
        if (inputOpen) {
            inputFound = [];
            read(hidUri, "/getPairedDeviceLists", {});
            autoSearch.restart();
        } else {
            autoSearch.stop();
            act(hidUri, "/cancelDiscovery", {});
            inputSearching = false;
            inputFound = [];
            publish();
        }
    }

    Timer {
        id: autoSearch
        interval: bt.menuDelay
        onTriggered: {
            if (bt.connectedInputs() === 0) bt.startInputSearch();
        }
    }

    // A device's page asks for its volume while it is open (AVRCP only, as LG).
    onAudioDeviceChanged: volumeTimer.stop()

    Instantiator {
        active: bt.audioListening && !bt.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            // getDeviceStatus wants subscribe: {} is refused with errorCode 1003 (schema) on
            // 10.3.2, so LG's first call without it never answers anything.
            Component.onCompleted: {
                call(bt.audioUri, "/getDeviceStatus", JSON.stringify({ subscribe: true }));
                call(bt.audioUri, "/getPairedDevices", JSON.stringify({ subscribe: true }));
            }
            onResponse: bt.answer(method, JSON.parse(payload))
        }
    }

    // startDiscovery {subscribe:true}: the answer names timeOut (seconds), then one answer per
    // device with state "started", at the end state "stopped". Destroying the service ends the
    // subscription, which is how LG stops it (no cancelDiscovery).
    Instantiator {
        active: bt.audioDiscovering && !bt.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: {
                // The one call that changes something without act(): it lives as long as this
                // subscription. A preview cuts it off with the same line as act().
                bt.discoveryCall(this);
            }
            onResponse: bt.answer(method, JSON.parse(payload))
            onError: bt.stopAudioSearch()
        }
    }

    function discoveryCall(service) {
        service.call(audioUri, "/startDiscovery", JSON.stringify({ subscribe: true }));
    }

    Instantiator {
        active: bt.volumeDevice !== "" && !bt.demo && bt.avrcpConnected(bt.volumeDevice)
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call(bt.audioUri, "/getDeviceVolume",
                                        JSON.stringify({ subscribe: true, address: bt.volumeDevice }))
            onResponse: bt.answer(method, JSON.parse(payload))
        }
    }

    // Bluetooth und Fernsehlautsprecher, as LG's BluetoothSurround reads it: the paired devices as
    // a subscription and, while one is connected, surround/getVolumeBalancing {subscribe:true}.
    // The page changes nothing by opening; onDeviceSelectionMenu belongs to the device lists.
    Instantiator {
        active: bt.surroundOpen && !bt.audioListening && !bt.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call(bt.audioUri, "/getPairedDevices", JSON.stringify({ subscribe: true }))
            onResponse: bt.answer(method, JSON.parse(payload))
        }
    }

    Instantiator {
        active: bt.surroundOpen && !bt.demo && bt.surroundConnected !== ""
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call(bt.surroundUri, "/getVolumeBalancing", JSON.stringify({ subscribe: true }))
            onResponse: bt.answer(method, JSON.parse(payload))
        }
    }

    Instantiator {
        active: bt.inputOpen && !bt.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: {
                call(bt.hidUri, "/subscribeDiscovery", JSON.stringify({ subscribe: true }));
                call(bt.hidUri, "/subscribeDevicesStatus", JSON.stringify({ subscribe: true }));
            }
            onResponse: bt.answer(method, JSON.parse(payload))
        }
    }

    // ---- Audio ---------------------------------------------------------------------------------

    function audioKind(device) {
        return DeviceList.audioKind(device.name);
    }

    function applyAudioPaired(response) {
        if (response.returnValue === false && response.devices === undefined) return;
        audioReady = true;
        var devices = (response.devices || []).filter(function (device) { return device.display !== false; });
        var list = [];
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i];
            var address = device.address;
            var before = lastAudioState[address];
            if (jobs[address] && jobs[address].list === "audio") {
                var job = jobs[address];
                if (job.job === "connect" && device.state === "connected") succeed(address, device.name);
                else if (job.job === "connect" && device.state === "disconnected" &&
                         (before === "connecting" || before === "pairing")) fail(address);
                else if (job.job === "disconnect" && device.state === "disconnected") disconnected(address, device.name);
            }
            lastAudioState[address] = device.state;
            // surround: the position a speaker holds beside the TV speaker ("left", "right",
            // "front", "rear"), set by LG's setup app or setChannel.
            list.push({ address: address, name: device.name || address, state: device.state || "disconnected",
                        position: positions.indexOf(device.surround) >= 0 ? device.surround : "",
                        avrcpSupported: device.avrcpSupported === true,
                        avrcpConnected: device.avrcpConnected === true, atmos: !!device.ATMOSDevice,
                        kind: audioKind(device) });
        }
        audioPaired = list;
        // A device that just paired leaves the found ones.
        audioFound = audioFound.filter(function (found) { return !pairedAudio(found.address); });
        publish();
    }

    function pairedAudio(address) {
        for (var i = 0; i < audioPaired.length; i++) {
            if (audioPaired[i].address === address) return audioPaired[i];
        }
        return null;
    }

    // getDeviceStatus: listType "paired" with state "paired" moves a found device to the paired
    // ones (LG removes it from the found list); listType "discovered" sets a found device's state.
    function applyAudioStatus(response) {
        if (!response.address) return;
        if (response.listType === "paired" && response.state === "paired") {
            audioFound = audioFound.filter(function (found) { return found.address !== response.address; });
        } else if (response.listType === "discovered") {
            var known = false;
            audioFound = audioFound.map(function (found) {
                if (found.address !== response.address) return found;
                known = true;
                var job = jobs[found.address];
                if (job && job.job === "connect" && response.state === "disconnected" &&
                    (found.state === "pairing" || found.state === "connecting")) {
                    bt.fail(found.address);
                }
                return copy(found, { state: response.state || found.state });
            });
            // LG adds a device that pairs from the TV's side as well.
            if (!known && response.state === "pairing") {
                audioFound = audioFound.concat([{ address: response.address, name: response.name || response.address,
                                                  state: "pairing", kind: audioKind(response) }]);
            }
        }
        if (response.state === "connected" && jobs[response.address]) succeed(response.address, response.name);
        publish();
    }

    function applyAudioDiscovery(response) {
        if (response.timeOut !== undefined) {
            audioSearching = true;
            searchEnd.interval = Number(response.timeOut) * 1000;
            searchEnd.restart();
        }
        if (response.state === "started" && response.device && response.device.address) {
            var device = response.device;
            var seen = pairedAudio(device.address) !== null;
            for (var i = 0; i < audioFound.length; i++) {
                if (audioFound[i].address === device.address) seen = true;
            }
            if (!seen) {
                audioFound = audioFound.concat([{ address: device.address, name: device.name || device.address,
                                                  state: "disconnected", kind: audioKind(device) }]);
            }
        } else if (response.state === "stopped") {
            stopAudioSearch();
        }
        publish();
    }

    Timer {
        id: searchEnd
        onTriggered: bt.stopAudioSearch()
    }

    function startAudioSearch() {
        if (audioDiscovering || audioBusy()) return;
        audioFound = audioFound.filter(function (found) { return jobs[found.address] !== undefined; });
        failed = ({});
        audioSearching = true;
        audioDiscovering = true;
        if (demo) demoSearchAudio();
        publish();
    }

    function stopAudioSearch() {
        searchEnd.stop();
        audioDiscovering = false;
        audioSearching = false;
        publish();
    }

    function audioBusy() {
        var lists = [audioPaired, audioFound];
        for (var l = 0; l < lists.length; l++) {
            for (var i = 0; i < lists[l].length; i++) {
                if (DeviceList.busyStates.indexOf(lists[l][i].state) >= 0) return true;
            }
        }
        return false;
    }

    function avrcpConnected(address) {
        var device = pairedAudio(address);
        return !!device && device.avrcpConnected;
    }

    // An answer with errorCode (1012 "There is no connected device") changes nothing, as LG.
    function applyBalancing(response) {
        if (!response || response.errorCode !== undefined || response.returnValue === false) return;
        var next = copy(balancing, {});
        if (response.tvspeaker_bluetooth !== undefined) next.level = Number(response.tvspeaker_bluetooth);
        if (response.bluetooth_left_right !== undefined) next.balance = Number(response.bluetooth_left_right);
        balancing = next;
        publish();
    }

    // ---- Bluetooth und Fernsehlautsprecher (TON-D) -------------------------------------------

    function hearingAid() {
        var sound = settings && settings.store.values.sound ? settings.store.values.sound : {};
        return sound.hearingAid === "bluetooth";
    }

    function bluetoothTv() {
        var sound = settings && settings.store.values.sound ? settings.store.values.sound : {};
        return sound.soundOutput === "tv_speaker_bluetooth";
    }

    // The speakers of the page: those that hold a position, and while Bluetooth plays with the
    // TV speaker every connected one that is no headphones. LG lists every paired device there;
    // headphones of the device list would read wrong under "Lautsprecher".
    function surroundSpeakers() {
        var both = bluetoothTv();
        return audioPaired.filter(function (device) {
            return device.position !== "" || (both && device.state === "connected" && device.kind !== "headphones");
        });
    }

    function firstSurroundConnected() {
        var speakers = surroundSpeakers();
        for (var i = 0; i < speakers.length; i++) {
            if (speakers[i].state === "connected") return speakers[i].address;
        }
        return "";
    }

    // The values LG offers for a speaker: left and right, or front and rear (LG's tne()).
    function positionPair(position) {
        return position === "front" || position === "rear" ? ["front", "rear"] : ["left", "right"];
    }

    function holderOf(position, except) {
        var speakers = surroundSpeakers();
        for (var i = 0; i < speakers.length; i++) {
            if (speakers[i].address !== except && speakers[i].position === position) return speakers[i];
        }
        return null;
    }

    // setChannel {address, from, to}, as LG's nne(). A position another speaker holds asks first
    // (K3-Einst-BT-und-TV-06); LG asks for the swap of left and right.
    function setPosition(params) {
        var entry = pairedAudio(params.id);
        if (!entry || params.to === entry.position) return;
        var holder = holderOf(params.to, entry.address);
        if (holder && params.confirmed !== true) {
            var name = t("sound", "value.position." + params.to);
            settings.hostAction("confirm", { action: "btSurroundPosition", danger: false,
                                             params: { id: params.id, to: params.to, confirmed: true },
                                             icon: "alert-44",
                                             title: t("sound", "confirm.position_title", { position: name }),
                                             text: t("sound", "confirm.position_text", { name: holder.name }),
                                             confirm: t("sound", "confirm.position_button") });
            return;
        }
        act(audioUri, "/setChannel", { address: entry.address, from: entry.position, to: params.to });
        // Shown at once; getPairedDevices brings the positions LG keeps.
        audioPaired = audioPaired.map(function (device) {
            if (device.address === entry.address) return copy(device, { position: params.to });
            if (holder && device.address === holder.address) return copy(device, { position: entry.position });
            return device;
        });
        publish();
    }

    // setVolumeBalancing once the key rests, as the volume of a device.
    Timer {
        id: balancingTimer
        property var request: ({})
        interval: bt.volumeDelay
        onTriggered: bt.act(bt.surroundUri, "/setVolumeBalancing", request)
    }

    function setBalancing(name, field, value) {
        var next = copy(balancing, {});
        next[name] = Math.max(0, Math.min(10, Number(value)));
        balancing = next;
        var request = {};
        request[field] = next[name];
        balancingTimer.request = request;
        balancingTimer.restart();
        publish();
    }

    function applyVolume(response) {
        if (response.returnValue && typeof response.deviceVolume === "number" && response.address) {
            var next = copy(volumes, {});
            next[response.address] = response.deviceVolume;
            volumes = next;
            publish();
        }
    }

    // ---- Input devices -------------------------------------------------------------------------

    function inputKind(type) {
        return type === "gamepad" || type === "keyboard" || type === "mouse" ? type : "unknown";
    }

    // Always four places; empty ones read {isPaired:false, deviceName:"Not Paired", deviceAddr:"N/A"}.
    function applyInputPaired(response) {
        if (response.returnValue === false && response.deviceLists === undefined) return;
        inputReady = true;
        var places = response.deviceLists || [];
        var list = [];
        for (var key in places) {
            var place = places[key];
            if (!place || place.isPaired !== true || !place.deviceAddr || place.deviceAddr === "N/A") continue;
            var address = place.deviceAddr;
            var job = jobs[address];
            if (job && job.list === "input" && job.job === "connect" && place.isConnected === true) succeed(address, place.deviceName);
            else if (job && job.list === "input" && job.job === "disconnect" && place.isConnected !== true)
                disconnected(address, place.deviceName);
            list.push({ address: address, name: place.deviceName || address, kind: inputKind(place.deviceType),
                        connected: place.isConnected === true });
        }
        inputPaired = list;
        inputFound = inputFound.filter(function (found) { return !pairedInput(found.address); });
        publish();
    }

    function pairedInput(address) {
        for (var i = 0; i < inputPaired.length; i++) {
            if (inputPaired[i].address === address) return inputPaired[i];
        }
        return null;
    }

    function connectedInputs() {
        var count = 0;
        for (var i = 0; i < inputPaired.length; i++) {
            if (inputPaired[i].connected) count++;
        }
        return count;
    }

    // Every change of a device: LG reads the list again. status "fail" ends a connect without
    // success, "connected" and "paired" with it.
    function applyInputStatus(response) {
        var status = response.status || "";
        var address = response.address || response.deviceAddr || "";
        if (status === "fail") {
            for (var pending in jobs) {
                if (jobs[pending].list === "input" && jobs[pending].job === "connect" &&
                    (address === "" || address === pending)) fail(pending);
            }
        }
        read(hidUri, "/getPairedDeviceLists", {});
    }

    function applyInputDiscovery(response) {
        if (response.status === "startDiscovery" || response.status === "endDiscovery") {
            inputSearching = response.status === "startDiscovery";
        } else if (response.address) {
            var seen = pairedInput(response.address) !== null;
            for (var i = 0; i < inputFound.length; i++) {
                if (inputFound[i].address === response.address) seen = true;
            }
            if (!seen) {
                inputFound = inputFound.concat([{ address: response.address, name: response.name || response.address,
                                                  kind: inputKind(response.deviceType || response.type) }]);
            }
        }
        publish();
    }

    function startInputSearch() {
        if (inputSearching) return;
        inputFound = inputFound.filter(function (found) { return jobs[found.address] !== undefined; });
        failed = ({});
        inputSearching = true;
        act(hidUri, "/requestDiscovery", {});
        publish();
    }

    // ---- Jobs: connect and disconnect with their end ---------------------------------------------

    function startJob(address, entry, list, job, output) {
        var next = copy(jobs, {});
        next[address] = { name: entry.name, kind: entry.kind, list: list, job: job, output: output === true };
        jobs = next;
        var cleared = copy(failed, {});
        delete cleared[address];
        failed = cleared;
        jobTimer.restart();
    }

    function endJob(address) {
        var next = copy(jobs, {});
        delete next[address];
        jobs = next;
        publish();
    }

    // Success: a notice, and on "Neues Gerät koppeln" the device's page with "Als Audioausgabe
    // verwenden" in focus (K3-Einst-Bluetooth-Audio-10).
    function succeed(address, name) {
        var job = jobs[address];
        if (!job) return;
        endJob(address);
        notice(t(job.list === "audio" ? "sound" : "sources", "device.toast_connected", { name: name || job.name }), "",
               job.kind);
        if (job.output) useAsOutput(address);
        else if (job.list === "audio" && settings && settings.page && settings.page.id === "bluetoothPair") {
            settings.back();
            settings.push({ kind: "page", page: "bluetoothDevice", param: address, rowId: "paired:" + address, focus: 0 });
        }
    }

    function fail(address) {
        if (!jobs[address]) return;
        var next = copy(failed, {});
        next[address] = true;
        failed = next;
        endJob(address);
    }

    function disconnected(address, name) {
        var job = jobs[address];
        if (!job) return;
        endJob(address);
        var output = settings ? settings.store.values.sound && settings.store.values.sound.soundOutput : "";
        var detail = job.list === "audio" && output && output !== "bt_soundbar" ?
                     t("sound", "toast.sound_back", { output: settings.settingsStore.label("sound.soundOutput", output) }) : "";
        notice(t("sound", "device.toast_disconnected", { name: name || job.name }), detail, job.kind);
    }

    // A job without an answer ends after LG's 30 s; a connect counts as failed then.
    Timer {
        id: jobTimer
        interval: bt.connectLimit
        onTriggered: {
            for (var address in bt.jobs) {
                if (bt.jobs[address].job === "connect") bt.fail(address);
                else bt.endJob(address);
            }
        }
    }

    function notice(title, detail, kind) {
        if (settings) settings.showNotice(title, detail, kind === "headphones" ? "notice-headphones" :
                                          (kind === "speaker" || kind === "soundbar" ? "notice-speaker" : "notice-bluetooth"));
    }

    // ---- Actions of the catalogs -------------------------------------------------------------

    function entryOf(list, id) {
        var lists = list === "audio" ? [audioPaired, audioFound] : [inputPaired, inputFound];
        for (var l = 0; l < lists.length; l++) {
            for (var i = 0; i < lists[l].length; i++) {
                if (lists[l][i].address === id) return lists[l][i];
            }
        }
        return null;
    }

    function run(name, params, ctx) {
        var id = params.id !== undefined ? params.id : ctx.param;
        var entry;
        if (name === "btAudioSearch") {
            startAudioSearch();
        } else if (name === "btAudioConnect") {
            entry = entryOf("audio", id);
            if (!entry || audioBusy()) return;
            // LG: connect {address}, for a found device as for a paired one.
            startJob(id, entry, "audio", "connect", params.output === true);
            setAudioState(id, pairedAudio(id) ? "connecting" : "pairing");
            act(audioUri, "/connect", { address: id });
        } else if (name === "btAudioDisconnect") {
            entry = entryOf("audio", id);
            if (!entry) return;
            startJob(id, entry, "audio", "disconnect");
            setAudioState(id, "disconnecting");
            act(audioUri, "/disconnect", { address: id });
        } else if (name === "btAudioRemove") {
            entry = entryOf("audio", id);
            if (!entry) return;
            act(audioUri, "/removePairedDevice", { address: id });
            audioPaired = audioPaired.filter(function (device) { return device.address !== id; });
            publish();
            leaveDevice();
            notice(t("sound", "device.toast_removed", { name: entry.name }), "", entry.kind);
        } else if (name === "btAudioUse") {
            entry = pairedAudio(id);
            if (!entry) return;
            if (entry.state === "connected") useAsOutput(id);
            else run("btAudioConnect", { id: id, output: true }, ctx);
        } else if (name === "btAudioVolume") {
            var next = copy(volumes, {});
            next[id] = Math.max(0, Math.min(100, Number(params.value)));
            volumes = next;
            volumeTimer.address = id;
            volumeTimer.restart();
            publish();
        } else if (name === "btInputSearch") {
            startInputSearch();
        } else if (name === "btInputConnect") {
            entry = entryOf("input", id);
            if (!entry || jobRunning("input")) return;
            if (connectedInputs() >= inputLimit) {
                // Board QG-1 05: first disconnect one of the four.
                settings.hostAction("confirm", { action: "btInputPick", params: {}, safe: true, danger: false,
                                                 icon: "alert-44",
                                                 title: t("sources", "confirm.limit_title"),
                                                 text: t("sources", "confirm.limit_text"),
                                                 confirm: t("sources", "confirm.limit_button") });
                return;
            }
            startJob(id, entry, "input", "connect");
            // LG: requestConnect {name, address}, spinner for at most 30 s.
            act(hidUri, "/requestConnect", { name: entry.name, address: id });
            publish();
        } else if (name === "btInputDisconnect") {
            entry = entryOf("input", id);
            if (!entry) return;
            startJob(id, entry, "input", "disconnect");
            act(hidUri, "/requestDisconnect", { deviceAddr: id });
            publish();
        } else if (name === "btInputRemove") {
            entry = entryOf("input", id);
            if (!entry) return;
            act(hidUri, "/requestDelete", { deviceAddr: id });
            inputPaired = inputPaired.filter(function (device) { return device.address !== id; });
            read(hidUri, "/getPairedDeviceLists", {});
            publish();
            leaveDevice();
            notice(t("sources", "device.toast_removed", { name: entry.name }), "", entry.kind);
        } else if (name === "btSurroundPosition") {
            setPosition(params);
        } else if (name === "btSurroundLevel") {
            setBalancing("level", "tvspeaker_bluetooth", params.value);
        } else if (name === "btSurroundBalance") {
            setBalancing("balance", "bluetooth_left_right", params.value);
        } else if (name === "btSurroundHearing") {
            if (hearingDevice !== "") run("btAudioVolume", { id: hearingDevice, value: params.value }, ctx);
        } else if (name === "btSurroundReset") {
            // LG's "Einstellungen zurücksetzen": surround/notifyEvent {event:"resetSetup"}.
            act(surroundUri, "/notifyEvent", { event: "resetSetup" });
        } else if (name === "btInputPick") {
            // "Ein Gerät trennen": the focus goes to the first connected device.
            for (var i = 0; i < inputPaired.length; i++) {
                if (inputPaired[i].connected && settings.focusRow("paired:" + inputPaired[i].address)) return;
            }
        }
    }

    function jobRunning(list) {
        for (var address in jobs) {
            if (jobs[address].list === list) return true;
        }
        return false;
    }

    // The page of a device that is gone: one level up.
    function leaveDevice() {
        if (settings && settings.dialogOpen) settings.closeDialog();
        else if (settings && settings.page && (settings.page.id === "bluetoothDevice" || settings.page.id === "bluetoothInputDevice"))
            settings.back();
    }

    // As LG's "Bluetooth-Gerät" output: sound.soundOutput = bt_soundbar once a device is connected.
    function useAsOutput(address) {
        var entry = pairedAudio(address);
        if (!settings || !entry) return;
        settings.settingsStore.set("sound.soundOutput", "bt_soundbar");
        settings.flushWrite();
        notice(t("sound", "toast.sound_via", { name: entry.name }), "", entry.kind);
    }

    function setAudioState(address, state) {
        lastAudioState[address] = state;
        audioPaired = audioPaired.map(function (device) {
            return device.address === address ? copy(device, { state: state }) : device;
        });
        audioFound = audioFound.map(function (device) {
            return device.address === address ? copy(device, { state: state }) : device;
        });
        publish();
    }

    // setDeviceVolume {address, deviceVolume}, once the key rests.
    Timer {
        id: volumeTimer
        property string address: ""
        interval: bt.volumeDelay
        onTriggered: bt.act(bt.audioUri, "/setDeviceVolume", { address: address, deviceVolume: bt.volumes[address] })
    }

    // ---- Into the store ------------------------------------------------------------------------

    function copy(source, changes) {
        var result = {};
        for (var key in source) result[key] = source[key];
        for (var name in changes) result[name] = changes[name];
        return result;
    }

    // The state a row shows: a job running, a failed try, or what the service said.
    function shownState(address, state, list) {
        var job = jobs[address];
        if (job && job.list === list) {
            if (job.job === "disconnect") return "disconnecting";
            return state === "pairing" ? "pairing" : "connecting";
        }
        if (failed[address]) return "failed";
        return state;
    }

    function publish() {
        if (!settings) return;
        var store = settings.store;
        var output = store.values.sound ? store.values.sound.soundOutput : "";
        store.lists.bluetooth = audioPaired.map(function (device) {
            return { id: device.address, title: device.name, kind: device.kind, atmos: device.atmos,
                     state: shownState(device.address, device.state, "audio"),
                     avrcpSupported: device.avrcpSupported, avrcpConnected: device.avrcpConnected,
                     position: device.position, output: output === "bt_soundbar" && device.state === "connected" };
        });
        // Bluetooth und Fernsehlautsprecher: the speakers with their position and the values LG
        // offers for it.
        store.lists.btSurround = surroundSpeakers().map(function (device) {
            return { id: device.address, title: device.name, kind: "speaker", position: device.position,
                     positions: positionPair(device.position),
                     state: shownState(device.address, device.state, "audio"),
                     avrcpSupported: device.avrcpSupported, avrcpConnected: device.avrcpConnected };
        });
        store.lists.bluetoothFound = audioFound.map(function (device) {
            return { id: device.address, title: device.name, kind: device.kind,
                     state: shownState(device.address, device.state === "disconnected" ? "found" : device.state, "audio") };
        });
        store.lists.bluetoothInput = inputPaired.map(function (device) {
            return { id: device.address, title: device.name, kind: device.kind,
                     state: shownState(device.address, device.connected ? "connected" : "disconnected", "input") };
        });
        store.lists.bluetoothInputFound = inputFound.map(function (device) {
            return { id: device.address, title: device.name, kind: device.kind,
                     state: shownState(device.address, "found", "input") };
        });
        var counts = { gamepad: 0, keyboard: 0, mouse: 0 };
        for (var i = 0; i < inputPaired.length; i++) {
            if (inputPaired[i].connected && counts[inputPaired[i].kind] !== undefined) counts[inputPaired[i].kind]++;
        }
        store.state.btAudioSearching = audioSearching;
        store.state.btAudioReady = audioReady;
        store.state.btAudioVolume = volumes;
        store.state.btSurroundLevel = balancing.level;
        store.state.btSurroundBalance = balancing.balance;
        surroundConnected = firstSurroundConnected();
        hearingDevice = surroundOpen && hearingAid() ? surroundConnected : "";
        store.state.btSurroundDevice = surroundConnected;
        store.state.btInputSearching = inputSearching;
        store.state.btInputReady = inputReady;
        store.state.btInputCounts = counts;
        store.state.btInputConnected = connectedInputs();
        settings.changed();
    }

    // ---- Demo for previews ---------------------------------------------------------------------
    // Devices as the boards show them. Nothing here reaches LG; act() comes here instead.

    function demoAudio(name, kind, state, extra) {
        var device = { address: "demo-" + name.replace(/[^A-Za-z0-9]/g, ""), name: name, kind: kind, state: state,
                       avrcpSupported: true, avrcpConnected: state === "connected", atmos: false, position: "" };
        return copy(device, extra || {});
    }

    function demoInput(name, kind, connected) {
        return { address: "demo-" + name.replace(/[^A-Za-z0-9]/g, ""), name: name, kind: kind, connected: connected };
    }

    function demoStart() {
        var scene = demoScene;
        audioReady = scene === "unavailable" ? false : true;
        inputReady = audioReady;
        audioPaired = [demoAudio("Sony WH-1000XM5", "headphones", "connected"),
                       demoAudio("JBL Charge 5", "speaker", scene === "noAvrcp" ? "connected" : "disconnected",
                                 { avrcpConnected: false }),
                       demoAudio("LG Soundbar S90TY", "soundbar", scene === "atmos" ? "connected" : "disconnected",
                                 { atmos: true, avrcpSupported: false, avrcpConnected: false })];
        if (scene !== "atmos" && scene !== "noAvrcp") audioPaired = audioPaired.slice(0, 2);
        if (scene === "connecting") audioPaired[1].state = "connecting";
        volumes = { "demo-SonyWH1000XM5": 45 };
        inputPaired = [demoInput("DualSense Wireless Controller", "gamepad", true),
                       demoInput("Logitech K380", "keyboard", true),
                       demoInput("Logitech MX Anywhere 3S", "mouse", scene === "limit")];
        if (scene === "limit") inputPaired.splice(1, 0, demoInput("Xbox Wireless Controller", "gamepad", true));
        inputFound = scene === "limit" ? [demoInput("8BitDo Pro 2", "gamepad", false)]
                                       : [demoInput("8BitDo Pro 2", "gamepad", false),
                                          demoInput("Apple Magic Keyboard", "keyboard", false)];
        // Bluetooth is the output (K3-Einst-Bluetooth-Audio-02) or Bluetooth with the TV
        // speaker (-15): shown here only, nothing is written.
        if (scene === "output" || scene === "btTv") demoSound({ soundOutput: scene === "output" ? "bt_soundbar"
                                                                                             : "tv_speaker_bluetooth" });
        if (scene.indexOf("surround") === 0) demoSurround(scene);
        publish();
    }

    // Values the demo shows, nothing is written. Again later, in case LG's answers came after.
    function demoSound(values) {
        var apply = function () {
            if (!settings.store.values.sound) settings.store.values.sound = {};
            for (var key in values) settings.store.values.sound[key] = values[key];
            bt.publish();
        };
        apply();
        demoLater(1500, apply);
        demoLater(4000, apply);
    }

    // TON-D (K3-Einst-BT-und-TV): surroundOne, surroundTwo, surroundEmpty, surroundHearing,
    // surroundSecondOff (the second speaker not connected), surroundOff (output not Bluetooth
    // with the TV speaker: position greyed out).
    function demoSurround(scene) {
        var first = demoAudio("LG XBOOM Go XG8T", "speaker", "connected", { position: "left" });
        // The balance needs two speakers of the same model (LG's wte()).
        var second = demoAudio("LG XBOOM Go XG8T (2)", "speaker", scene === "surroundSecondOff" ? "disconnected" : "connected",
                               { position: "right" });
        // The headphones of the other boards stay paired, not connected.
        audioPaired = audioPaired.map(function (device) { return copy(device, { state: "disconnected", avrcpConnected: false }); });
        if (scene === "surroundEmpty") audioPaired = audioPaired.filter(function (device) { return device.kind === "headphones"; });
        else if (scene === "surroundTwo" || scene === "surroundSecondOff") audioPaired = audioPaired.concat([first, second]);
        else audioPaired = audioPaired.concat([first]);
        balancing = scene === "surroundEmpty" ? {} : { level: 6, balance: 4 };
        volumes = copy(volumes, { "demo-LGXBOOMGoXG8T": 40 });
        demoSound({ soundOutput: scene === "surroundOff" ? "tv_speaker" : "tv_speaker_bluetooth",
                    hearingAid: scene === "surroundHearing" ? "bluetooth" : "off", avSyncBtSurround: "20",
                    bluetoothMode: "surroundMode" });
    }

    property var demoQueue: []

    function demoLater(delay, step) {
        demoQueue = demoQueue.concat([{ at: Date.now() + delay, step: step }]);
        demoTimer.start();
    }

    Timer {
        id: demoTimer
        interval: 100
        repeat: true
        onTriggered: {
            var now = Date.now();
            var due = bt.demoQueue.filter(function (entry) { return entry.at <= now; });
            bt.demoQueue = bt.demoQueue.filter(function (entry) { return entry.at > now; });
            for (var i = 0; i < due.length; i++) due[i].step();
            if (bt.demoQueue.length === 0) stop();
        }
    }

    function demoSearchAudio() {
        var found = demoScene === "empty" ? [] :
                    [demoAudio("Bose QuietComfort Ultra", "headphones", "disconnected"),
                     demoAudio("Marshall Emberton II", "speaker", "disconnected"),
                     demoAudio("Sennheiser Momentum 4", "headphones", "disconnected")];
        var count = demoScene === "searching" ? 1 : found.length;
        for (var i = 0; i < count; i++) {
            (function (device, delay) {
                bt.demoLater(delay, function () { bt.applyAudioDiscovery({ state: "started", device: device }); });
            })(found[i], 800 + i * 900);
        }
        if (!demoHold && demoScene !== "searching") demoLater(800 + count * 900 + 1500, function () { bt.stopAudioSearch(); });
    }

    function demoAct(method, params) {
        var address = params.address || params.deviceAddr || "";
        if (method === "/connect") {
            if (demoHold) return;
            // Marshall fails as on K3-Einst-Bluetooth-Audio-08, every other device connects.
            demoLater(3000, function () {
                if (/Marshall/.test(bt.jobs[address] ? bt.jobs[address].name : "")) {
                    bt.applyAudioStatus({ listType: "discovered", address: address, state: "disconnected" });
                    return;
                }
                var entry = bt.entryOf("audio", address);
                if (!bt.pairedAudio(address) && entry) {
                    bt.audioPaired = bt.audioPaired.concat([copy(entry, { state: "connected", avrcpSupported: true,
                                                                          avrcpConnected: true })]);
                }
                bt.applyAudioPaired({ devices: bt.audioPaired.map(function (device) {
                    return { address: device.address, name: device.name, display: true,
                             state: device.address === address ? "connected" : device.state,
                             avrcpSupported: device.avrcpSupported,
                             avrcpConnected: device.address === address ? true : device.avrcpConnected,
                             ATMOSDevice: device.atmos };
                }) });
            });
        } else if (method === "/disconnect") {
            if (demoHold) return;
            demoLater(1500, function () {
                bt.applyAudioPaired({ devices: bt.audioPaired.map(function (device) {
                    return { address: device.address, name: device.name, display: true,
                             state: device.address === address ? "disconnected" : device.state,
                             avrcpSupported: device.avrcpSupported,
                             avrcpConnected: device.address === address ? false : device.avrcpConnected,
                             ATMOSDevice: device.atmos };
                }) });
            });
        } else if (method === "/requestDiscovery") {
            if (!demoHold) demoLater(4000, function () { bt.applyInputDiscovery({ status: "endDiscovery" }); });
        } else if (method === "/requestConnect") {
            if (demoHold) return;
            demoLater(3000, function () {
                if (/8BitDo/.test(params.name || "")) {
                    bt.applyInputStatus({ status: "fail", address: address });
                    return;
                }
                var entry = bt.entryOf("input", address);
                if (entry && !bt.pairedInput(address)) bt.inputPaired = bt.inputPaired.concat([copy(entry, { connected: true })]);
                bt.inputPaired = bt.inputPaired.map(function (device) {
                    return device.address === address ? copy(device, { connected: true }) : device;
                });
                bt.applyInputPaired({ deviceLists: bt.inputPaired.map(function (device) {
                    return { isPaired: true, deviceAddr: device.address, deviceName: device.name,
                             deviceType: device.kind, isConnected: device.connected };
                }) });
            });
        } else if (method === "/requestDisconnect") {
            if (demoHold) return;
            demoLater(1500, function () {
                bt.inputPaired = bt.inputPaired.map(function (device) {
                    return device.address === address ? copy(device, { connected: false }) : device;
                });
                bt.applyInputPaired({ deviceLists: bt.inputPaired.map(function (device) {
                    return { isPaired: true, deviceAddr: device.address, deviceName: device.name,
                             deviceType: device.kind, isConnected: device.connected };
                }) });
            });
        }
    }
}
