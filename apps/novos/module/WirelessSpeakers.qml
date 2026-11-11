import QtQuick 2.12
import WebOSServices 1.0
import "."
import "SettingsEngine.js" as Engine

// WiSA speakers and WOWCAST devices of the settings (TON-E, K3-Einst-WiSA-WOWCAST). Every call is
// the one LG's own settings app makes (main.js of com.palm.app.settings, webOS 10.3.2:
// WisaSpeakers, SpeakersItem…Panel, SoundWowcast); where it differs it says why. The lists land
// in the settings store: wisa and wisa_<position>, wowcast (the registered device) and
// wowcastFound, for the device list (DeviceList.js) and the device dialog (DeviceModal.qml).
//
// The pages decide when it talks to the services: session "wisa", "wisaSpeaker:<address>" and
// "wowcast" (SettingsModal.sessions). Everything that changes something goes through act().
//
// WiSA needs LG's WiSA dongle in a USB port (pdm, deviceType "WISADONGLE"); without it
// com.webos.service.wisa does not run and getSelectedSpeakerState never answers, so the state
// becomes "not available" after answerLimit. WOWCAST needs Wi-Fi on 2.4 GHz or on the 5 GHz
// channels LG lists, and no WOWCAST dongle at HDMI (ARC).
Item {
    id: radio

    property var settings: null
    readonly property var sessions: settings ? settings.sessions : []

    // Preview only (PREVIEW_MODULE_SED): made-up speakers and devices in the states of the
    // boards, and no call reaches LG. demoScene picks a state, demoHold keeps steps from ending.
    property bool demo: false
    property string demoScene: ""
    property bool demoHold: false

    readonly property string wisaUri: "luna://com.webos.service.wisa"
    readonly property string wowUri: "luna://com.webos.service.wowplay"
    readonly property int answerLimit: GlassStyle.answerLimit
    readonly property int volumeDelay: 120          // the trim goes out once the key rests
    readonly property int discoveryDelay: 500       // LG waits as long before it searches
    readonly property int connectLimit: 30000

    readonly property var actionNames: ["wisaSearch", "wisaPosition", "wisaVolume", "wisaTestTone", "wisaRemove",
                                        "wowSearch", "wowConnect", "wowDisconnect", "wowRemove"]
    // LG's SPEAKER_MAP_INDEX and the names of its positions.
    readonly property var wisaIndex: ({ LEFT_FRONT_MAP_INDEX: "left", RIGHT_FRONT_MAP_INDEX: "right",
                                        CENTER_MAP_INDEX: "center", SUB_MAP_INDEX: "subwoofer",
                                        LEFT_SURR_MAP_INDEX: "surround_left", RIGHT_SURR_MAP_INDEX: "surround_right" })
    readonly property var wisaPositions: ["left", "right", "center", "subwoofer", "surround_left", "surround_right"]

    property var wisaDongle: undefined     // pdm: a WiSA dongle in a USB port
    property var wisaServer: undefined     // registerServerStatus of com.webos.service.wisa
    property var wisaReady: undefined      // true once the speakers answered, false without answer
    property var wisaSpeakers: []          // { address, name, position, missing, volume, removing }
    property bool wisaSearching: false
    property bool wisaSearchRuns: false    // the searchSpeaker subscription lives
    property string wisaTesting: ""        // the address whose test tone plays

    property var wowWifi: undefined        // wifi/getconnectedprofile: connected
    property var wowFrequency: undefined   // its frequency is one WOWCAST can use
    property bool wowDongle: false         // LG's WOWCAST dongle at HDMI (ARC), from eim
    property var wowReady: undefined
    property var wowDevice: ({})           // getLatestConnectionInfo: the registered device
    property var wowFound: []              // startDiscovery: { address (BLE), name, connecting, failed }
    property bool wowSearching: false
    property bool wowDiscovering: false    // the startDiscovery subscription lives

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

    readonly property bool wisaOpen: has("wisa")
    readonly property string wisaDialog: paramOf("wisaSpeaker")
    readonly property bool wowOpen: has("wowcast")
    readonly property bool wowBlocked: wowDongle || wowWifi === false || (wowWifi === true && wowFrequency === false)

    function runs(name) {
        return actionNames.indexOf(name) >= 0;
    }

    function t(key, params) {
        return Engine.text(I18n, "sound", key, params);
    }

    function copy(source, changes) {
        var result = {};
        for (var key in source) result[key] = source[key];
        for (var name in changes) result[name] = changes[name];
        return result;
    }

    // ---- Calls -----------------------------------------------------------------------------

    // Everything that changes a speaker, a device or a search goes through here; a preview
    // cuts it off.
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

    // When the modal opens: is a WiSA dongle there, and how many speakers (the row's second line).
    function request() {
        if (demo) {
            demoStart();
            return;
        }
        read("luna://com.webos.service.pdm", "/getAttachedNonStorageDeviceList", {});
    }

    Service {
        id: readService
        appId: "com.webos.app.quicksettings"
        onResponse: radio.answer(method, JSON.parse(payload))
        onError: radio.answer(method, { returnValue: false })
    }

    Service {
        id: actionService
        appId: "com.webos.app.quicksettings"
        onResponse: radio.acted(method, JSON.parse(payload))
        onError: radio.acted(method, { returnValue: false })
    }

    function answer(method, response) {
        if (method === "/getAttachedNonStorageDeviceList") applyDongle(response);
        else if (method === "/registerServerStatus") applyServer(response);
        else if (method === "/getSelectedSpeakerState") applySpeakers(response);
        else if (method === "/getSoundTestState") applyTestState(response);
        else if (method === "/searchSpeaker") applySearch(response);
        else if (method === "/getconnectedprofile") applyWifi(response);
        else if (method === "/getLatestConnectionInfo") applyWowDevice(response);
        else if (method === "/startDiscovery") applyWowDiscovery(response);
    }

    // bleConnect {subscribe:true} answers here: connect true while it runs, then the end.
    function acted(method, response) {
        if (method === "/bleConnect") applyBleConnect(response);
        else if (method === "/soundTestOneSpeaker" && response.returnValue === false) {
            wisaTesting = "";
            publish();
        }
    }

    // ---- WiSA ------------------------------------------------------------------------------

    // LG's IB(): a WISADONGLE below USB port 16.
    function applyDongle(response) {
        var list = response.nonStorageDeviceList;
        if (!Array.isArray(list)) return;
        var found = false;
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].deviceType === "WISADONGLE" && list[i].usbPortNum < 16) found = true;
        }
        var first = wisaDongle === undefined;
        wisaDongle = found;
        // The number of speakers for the row on Audioausgabe, once.
        if (found && first && wisaReady === undefined) read(wisaUri, "/getSelectedSpeakerState", {});
        publish();
    }

    // The dongle can come and go while the modal is open.
    Instantiator {
        active: !!radio.settings && radio.settings.active && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call("luna://com.webos.service.pdm", "/getAttachedNonStorageDeviceList",
                                        JSON.stringify({ subscribe: true }))
            onResponse: radio.answer(method, JSON.parse(payload))
        }
    }

    // LG's WisaSpeakers: registerServerStatus of the service, and while it runs the speakers and
    // the test tone as subscriptions.
    Instantiator {
        active: radio.wisaOpen && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call("luna://com.palm.lunabus/signal", "/registerServerStatus",
                                        JSON.stringify({ serviceName: "com.webos.service.wisa", subscribe: true }))
            onResponse: radio.answer(method, JSON.parse(payload))
        }
    }

    Instantiator {
        active: radio.wisaOpen && radio.wisaServer === true && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: {
                call(radio.wisaUri, "/getSelectedSpeakerState", JSON.stringify({ subscribe: true }));
                call(radio.wisaUri, "/getSoundTestState", JSON.stringify({ subscribe: true }));
            }
            onResponse: radio.answer(method, JSON.parse(payload))
        }
    }

    // searchSpeaker {subscribe:true}: status start, searching, complete. A preview cuts it off
    // with the same line as act().
    Instantiator {
        active: radio.wisaSearchRuns && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: radio.searchCall(this)
            onResponse: radio.answer(method, JSON.parse(payload))
            onError: radio.stopWisaSearch()
        }
    }

    function searchCall(service) {
        service.call(wisaUri, "/searchSpeaker", JSON.stringify({ subscribe: true }));
    }

    onWisaOpenChanged: {
        if (wisaOpen) {
            if (wisaReady !== true) wisaReady = undefined;
            wisaTimer.restart();
        } else {
            wisaTimer.stop();
            stopWisaSearch();
        }
        publish();
    }

    // No answer of the speakers by then: the service is not there (no dongle, as on this TV).
    Timer {
        id: wisaTimer
        interval: radio.answerLimit
        onTriggered: {
            if (radio.wisaReady === undefined) {
                radio.wisaReady = false;
                radio.publish();
            }
        }
    }

    // Leaving a speaker's dialog stops its test tone (LG's onForceStop).
    property string lastDialog: ""
    onWisaDialogChanged: {
        if (lastDialog !== "" && wisaTesting === lastDialog) testTone(lastDialog, false);
        lastDialog = wisaDialog;
    }

    function applyServer(response) {
        if (response.connected === true) {
            wisaServer = true;
        } else if (response.connected === false) {
            wisaServer = false;
            wisaSpeakers = [];
            wisaTesting = "";
            wisaReady = false;
            stopWisaSearch();
        }
        publish();
    }

    function applySpeakers(response) {
        if (!Array.isArray(response.SelectedSpeakerlist)) return;
        wisaReady = true;
        var list = [];
        for (var i = 0; i < response.SelectedSpeakerlist.length; i++) {
            var speaker = response.SelectedSpeakerlist[i];
            var status = String(speaker.SPEAKER_STATUS || "").replace("SPEAKER_STATUS_", "").toLowerCase();
            list.push({ address: speaker.macAddress, name: speaker.SPEAKER_DESCRIPTION || speaker.macAddress,
                        position: wisaIndex[speaker.SPEAKER_MAP_INDEX] || "", missing: status === "missing",
                        volume: Number(speaker.VOLUME_TRIM) || 0, removing: !!speaker.REMOVING_STATUS });
        }
        wisaSpeakers = list;
        // LG searches by itself when the service asks for it.
        if (response.needAutoSearch === true && wisaOpen) startWisaSearch();
        publish();
    }

    function applyTestState(response) {
        var states = Array.isArray(response.SoundTestState) ? response.SoundTestState : [];
        var playing = states.filter(function (state) { return state.SOUND_TEST_STATE === "play"; }).length > 0;
        if (!playing && wisaTesting !== "") {
            wisaTesting = "";
            publish();
        }
    }

    function applySearch(response) {
        if (response.status === "start" || response.status === "searching") {
            wisaSearching = true;
            publish();
        } else if (response.status === "complete") {
            stopWisaSearch();
        }
    }

    function startWisaSearch() {
        if (wisaSearchRuns) return;
        wisaSearching = true;
        wisaSearchRuns = true;
        if (demo) demoSearchWisa();
        publish();
    }

    function stopWisaSearch() {
        wisaSearchRuns = false;
        wisaSearching = false;
        publish();
    }

    function speaker(address) {
        for (var i = 0; i < wisaSpeakers.length; i++) {
            if (wisaSpeakers[i].address === address) return wisaSpeakers[i];
        }
        return null;
    }

    // setSpeakerType {macAddress, type}. A place another speaker holds asks first
    // (K3-Einst-WiSA-WOWCAST-09); LG counts only speakers that are not missing.
    function setPosition(params) {
        var entry = speaker(params.id);
        if (!entry || entry.position === params.to) return;
        var holder = null;
        for (var i = 0; i < wisaSpeakers.length; i++) {
            var other = wisaSpeakers[i];
            if (other.address !== entry.address && other.position === params.to && !other.missing) holder = other;
        }
        if (holder && params.confirmed !== true) {
            settings.hostAction("confirm", { action: "wisaPosition", danger: false, icon: "alert-44",
                                             params: { id: params.id, to: params.to, confirmed: true },
                                             title: t("confirm.position_title", { position: t("value.position." + params.to) }),
                                             text: t("confirm.position_text", { name: holder.name }),
                                             confirm: t("confirm.position_button") });
            return;
        }
        act(wisaUri, "/setSpeakerType", { macAddress: entry.address, type: params.to });
        wisaSpeakers = wisaSpeakers.map(function (item) {
            return item.address === entry.address ? copy(item, { position: params.to }) : item;
        });
        publish();
    }

    // setLogVolumeTrim {macAddress, volumeTrim}, -5 … 10, once the key rests.
    Timer {
        id: trimTimer
        property string address: ""
        interval: radio.volumeDelay
        onTriggered: {
            var entry = radio.speaker(address);
            if (entry) radio.act(radio.wisaUri, "/setLogVolumeTrim", { macAddress: address, volumeTrim: entry.volume });
        }
    }

    function setVolume(address, value) {
        var level = Math.max(-5, Math.min(10, Number(value)));
        wisaSpeakers = wisaSpeakers.map(function (item) {
            return item.address === address ? copy(item, { volume: level }) : item;
        });
        trimTimer.address = address;
        trimTimer.restart();
        publish();
    }

    // soundTestOneSpeaker {macAddress, mode: "play" | "stop"}; getSoundTestState ends it.
    function testTone(address, play) {
        if (play && wisaTesting !== "" && wisaTesting !== address) testTone(wisaTesting, false);
        wisaTesting = play ? address : "";
        act(wisaUri, "/soundTestOneSpeaker", { macAddress: address, mode: play ? "play" : "stop" });
        publish();
    }

    // ---- WOWCAST ---------------------------------------------------------------------------

    // LG's SoundWowcast: p2pSearch, the Wi-Fi and the dongle as subscriptions, after 500 ms the
    // registered device; without one a search (startDiscovery). Leaving: cancelDiscovery and
    // p2pStopSearch.
    onWowOpenChanged: {
        if (wowOpen) {
            wowFound = [];
            if (!demo) wowReady = undefined;
            act(wowUri, "/p2pSearch", {});
            wowTimer.restart();
            wowAnswer.restart();
        } else {
            wowTimer.stop();
            wowAnswer.stop();
            stopWowSearch();
            act(wowUri, "/cancelDiscovery", {});
            act(wowUri, "/p2pStopSearch", {});
        }
        publish();
    }

    Instantiator {
        active: radio.wowOpen && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call("luna://com.webos.service.wifi", "/getconnectedprofile",
                                        JSON.stringify({ subscribe: true }))
            onResponse: radio.answer(method, JSON.parse(payload))
        }
    }

    property bool wowListening: false
    Timer {
        id: wowTimer
        interval: radio.discoveryDelay
        onTriggered: {
            radio.wowListening = true;
            if (radio.demo) return;
            readService.call(radio.wowUri, "/getLatestConnectionInfo", "{}");
        }
    }

    Timer {
        id: wowAnswer
        interval: radio.answerLimit
        onTriggered: {
            if (radio.wowReady === undefined) {
                radio.wowReady = false;
                radio.publish();
            }
        }
    }

    Instantiator {
        active: radio.wowOpen && radio.wowListening && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call(radio.wowUri, "/getLatestConnectionInfo", JSON.stringify({ subscribe: true }))
            onResponse: radio.answer(method, JSON.parse(payload))
        }
    }

    // startDiscovery {subscribe:true}: scan true while it searches, then one answer per device.
    Instantiator {
        active: radio.wowDiscovering && !radio.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: radio.wowDiscoveryCall(this)
            onResponse: radio.answer(method, JSON.parse(payload))
            onError: radio.stopWowSearch()
        }
    }

    function wowDiscoveryCall(service) {
        service.call(wowUri, "/startDiscovery", JSON.stringify({ subscribe: true }));
    }

    // LG's N5(): connected, and 2412–2484, 5170–5250 or 5745–5825 MHz.
    function applyWifi(response) {
        if (response.connected === undefined) return;
        var wasBlocked = wowBlocked;
        var frequency = Number(response.frequency || 0);
        wowWifi = response.connected === true;
        wowFrequency = (frequency >= 2412 && frequency <= 2484) || (frequency >= 5170 && frequency <= 5250) ||
                       (frequency >= 5745 && frequency <= 5825);
        // Back from the Wi-Fi setup with a network that fits: the list comes and searches.
        if (wasBlocked && !wowBlocked && wowOpen && wowListening && !registered()) startWowSearch();
        publish();
    }

    // LG's PB(): an HDMI input with a SIMPLINK device "LG WOWCAST" whose wowcastStatus is connected.
    function applyInputs(response) {
        var devices = response.devices || [];
        var found = false;
        for (var i = 0; i < devices.length; i++) {
            var list = devices[i].subList || [];
            for (var j = 0; j < list.length; j++) {
                if (list[j] && list[j].id === "SIMPLINK" && list[j].osdName === "LG WOWCAST" &&
                    list[j].wowcastStatus === "connected") found = true;
            }
        }
        if (found !== wowDongle) {
            wowDongle = found;
            publish();
        }
    }

    function registered() {
        return !!wowDevice && wowDevice.name !== undefined;
    }

    function applyWowDevice(response) {
        if (response.returnValue === false && response.device === undefined) return;
        var first = wowReady === undefined || wowReady === false;
        wowReady = true;
        var device = response.device || {};
        // LG keeps the last device while only p2pRequesting comes; an empty one clears it.
        if (device.name !== undefined || Object.keys(device).length === 0) {
            wowDevice = device;
            if (device.bleAddress) {
                wowFound = wowFound.filter(function (found) { return found.address !== device.bleAddress; });
                endJob(device.bleAddress);
            }
        }
        if (first && !registered() && !wowBlocked && wowOpen) startWowSearch();
        publish();
    }

    function applyWowDiscovery(response) {
        if (response.scan !== undefined) {
            wowSearching = response.scan === true;
            if (!wowSearching) wowDiscovering = false;
        }
        var device = response.device;
        if (device && (device.address || device.bleAddress)) {
            var address = device.address || device.bleAddress;
            var seen = false;
            for (var i = 0; i < wowFound.length; i++) {
                if (wowFound[i].address === address) seen = true;
            }
            if (!seen && !(registered() && wowDevice.bleAddress === address)) {
                wowFound = wowFound.concat([{ address: address, name: device.name || address, state: "found" }]);
            }
        }
        publish();
    }

    function startWowSearch() {
        if (wowDiscovering || wowBlocked) return;
        wowFound = wowFound.filter(function (found) { return found.state === "connecting"; });
        wowSearching = true;
        wowDiscovering = true;
        if (demo) demoSearchWow();
        publish();
    }

    function stopWowSearch() {
        wowDiscovering = false;
        wowSearching = false;
        publish();
    }

    // bleConnect: connect true while it runs; otherwise errorText ends it as failed.
    function applyBleConnect(response) {
        var address = pendingBle;
        if (address === "") return;
        if (response.connect === true) return;
        setFound(address, response.errorText || response.returnValue === false ? "failed" : "connected");
        if (response.errorText || response.returnValue === false) endJob(address);
    }

    property string pendingBle: ""

    function setFound(address, state) {
        wowFound = wowFound.map(function (found) {
            return found.address === address ? copy(found, { state: state }) : found;
        });
        publish();
    }

    function endJob(address) {
        if (pendingBle === address) pendingBle = "";
        bleTimer.stop();
    }

    Timer {
        id: bleTimer
        interval: radio.connectLimit
        onTriggered: {
            if (radio.pendingBle !== "") {
                radio.setFound(radio.pendingBle, "failed");
                radio.pendingBle = "";
            }
        }
    }

    // The state a row shows for the registered device; registering counts as connecting.
    function wowState(state) {
        if (state === "registering") return "connecting";
        return ["connected", "connecting", "disconnecting"].indexOf(state) >= 0 ? state : "disconnected";
    }

    // ---- Actions of the catalogs -----------------------------------------------------------

    function run(name, params, ctx) {
        var id = params.id !== undefined ? params.id : ctx.param;
        var entry;
        if (name === "wisaSearch") {
            startWisaSearch();
        } else if (name === "wisaPosition") {
            setPosition(params);
        } else if (name === "wisaVolume") {
            if (speaker(id)) setVolume(id, params.value);
        } else if (name === "wisaTestTone") {
            if (speaker(id)) testTone(id, wisaTesting !== id);
        } else if (name === "wisaRemove") {
            // deleteOneSpeaker {macAddress}.
            entry = speaker(id);
            if (!entry) return;
            if (wisaTesting === id) testTone(id, false);
            act(wisaUri, "/deleteOneSpeaker", { macAddress: id });
            wisaSpeakers = wisaSpeakers.filter(function (item) { return item.address !== id; });
            publish();
            if (settings.dialogOpen) settings.closeDialog();
            settings.showNotice(t("device.toast_removed", { name: entry.name }), "", "notice-speaker");
        } else if (name === "wowSearch") {
            startWowSearch();
        } else if (name === "wowConnect") {
            if (registered() && (wowDevice.p2pAddress === id || wowDevice.bleAddress === id)) {
                // A registered device: p2pConnect {address, soundOutput}, as LG's L7().
                wowDevice = copy(wowDevice, { state: "connecting" });
                act(wowUri, "/p2pConnect", { address: wowDevice.p2pAddress, soundOutput: "wow_cast" });
                publish();
                return;
            }
            // A found device: bleConnect {address: [ble], subscribe: true}; LG then registers it.
            if (pendingBle !== "") return;
            pendingBle = id;
            setFound(id, "connecting");
            bleTimer.restart();
            act(wowUri, "/bleConnect", { address: [id], subscribe: true });
        } else if (name === "wowDisconnect") {
            if (!registered()) return;
            wowDevice = copy(wowDevice, { state: "disconnecting" });
            act(wowUri, "/p2pDisconnect", { address: wowDevice.p2pAddress || id });
            publish();
        } else if (name === "wowRemove") {
            if (!registered()) return;
            var removed = wowDevice.name;
            act(wowUri, "/removePairedDevice", { address: wowDevice.p2pAddress || id });
            wowDevice = ({});
            publish();
            if (settings.dialogOpen) settings.closeDialog();
            settings.showNotice(t("device.toast_removed", { name: removed }), "", "notice-speaker");
        }
    }

    // ---- Into the store --------------------------------------------------------------------

    function publish() {
        if (!settings) return;
        var store = settings.store;
        var speakers = wisaSpeakers.map(function (item) {
            return { id: item.address, title: item.name, kind: "speaker", position: item.position,
                     missing: item.missing, removing: item.removing, volume: item.volume,
                     state: item.missing ? "disconnected" : "connected" };
        });
        store.lists.wisa = speakers;
        var taken = {};
        for (var p = 0; p < wisaPositions.length; p++) {
            var position = wisaPositions[p];
            store.lists["wisa_" + position] = speakers.filter(function (item) { return item.position === position; });
        }
        for (var s = 0; s < speakers.length; s++) {
            if (!speakers[s].missing && speakers[s].position) taken[speakers[s].position] = speakers[s].id;
        }
        store.state.wisaTaken = taken;
        store.state.wisaDongle = wisaDongle;
        store.state.wisaReady = wisaReady;
        store.state.wisaSearching = wisaSearching;
        store.state.wisaTesting = wisaTesting;

        store.lists.wowcast = registered() ?
            [{ id: wowDevice.p2pAddress || wowDevice.bleAddress || "wowcast", title: wowDevice.name, kind: "wowcast",
               state: wowState(wowDevice.state) }] : [];
        store.lists.wowcastFound = wowFound.map(function (found) {
            return { id: found.address, title: found.name, kind: "wowcast", state: found.state };
        });
        store.state.wowWifi = wowWifi;
        store.state.wowFrequency = wowFrequency;
        store.state.wowDongle = wowDongle;
        store.state.wowSearching = wowSearching;
        store.state.wowReady = wowReady;
        settings.changed();
    }

    // ---- Demo for previews -----------------------------------------------------------------
    // Speakers and devices as the boards show them. Nothing here reaches LG.
    //   WiSA:    wisa21, wisa20Search, wisaEmpty, wisaTest, wisaMissing, wisaNoDongle
    //   WOWCAST: wowConnected, wowSearching, wowEmpty, wowNoWifi, wowFrequency, wowDongle

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
            var due = radio.demoQueue.filter(function (entry) { return entry.at <= now; });
            radio.demoQueue = radio.demoQueue.filter(function (entry) { return entry.at > now; });
            for (var i = 0; i < due.length; i++) due[i].step();
            if (radio.demoQueue.length === 0) stop();
        }
    }

    function demoSpeaker(name, position, extra) {
        return copy({ address: "demo-" + name.replace(/[^A-Za-z0-9]/g, ""), name: name, position: position,
                      missing: false, volume: 0, removing: false }, extra || {});
    }

    // Values the demo shows, nothing is written; again later, in case LG's answers came after.
    function demoSound(values) {
        var apply = function () {
            if (!settings.store.values.sound) settings.store.values.sound = {};
            for (var key in values) settings.store.values.sound[key] = values[key];
            radio.publish();
        };
        apply();
        demoLater(1500, apply);
        demoLater(4000, apply);
    }

    function demoStart() {
        var scene = demoScene;
        wisaDongle = scene !== "wisaNoDongle";
        wisaReady = true;
        if (scene.indexOf("wisa") === 0) {
            var all = [demoSpeaker("Platin Milan L", "left", { missing: scene === "wisaMissing",
                                                                volume: scene === "wisaMissing" ? -5 : (scene === "wisaTest" ? 10 : 0) }),
                       demoSpeaker("Platin Milan R", "right"), demoSpeaker("Platin Milan Sub", "subwoofer"),
                       demoSpeaker("Platin Milan SL", "surround_left")];
            wisaSpeakers = scene === "wisaEmpty" || scene === "wisaNoDongle" ? [] :
                           (scene === "wisa20Search" ? all.slice(0, 2) : all);
            if (scene === "wisaTest") wisaTesting = all[0].address;
            if (scene === "wisa20Search") {
                wisaSearching = true;
                wisaSearchRuns = true;
            }
            demoSound({ wisaSpeakerChannelType: scene === "wisa20Search" || scene === "wisaEmpty" ? "2" : "2.1" });
        }
        if (scene.indexOf("wow") === 0) {
            wowWifi = scene !== "wowNoWifi";
            wowFrequency = scene !== "wowFrequency";
            wowDongle = scene === "wowDongle";
            wowReady = true;
            wowDevice = scene === "wowConnected" ? { name: "LG WOWCAST WTP3", state: "connected", p2pAddress: "demo-p2p",
                                                     bleAddress: "demo-ble" } : {};
        }
        publish();
    }

    function demoSearchWisa() {
        if (demoHold || demoScene === "wisa20Search") return;
        demoLater(3000, function () { radio.stopWisaSearch(); });
    }

    function demoSearchWow() {
        if (demoScene === "wowSearching" || demoScene === "wowEmpty") {
            if (demoScene === "wowEmpty" && !demoHold) demoLater(2000, function () { radio.stopWowSearch(); });
            return;
        }
        demoLater(1200, function () {
            radio.applyWowDiscovery({ device: { address: "demo-wtp3", name: "LG WOWCAST WTP3" } });
        });
        if (!demoHold) demoLater(4000, function () { radio.stopWowSearch(); });
    }

    function demoAct(method, params) {
        if (method === "/p2pSearch" && wowOpen && !registered()) {
            demoLater(radio.discoveryDelay + 100, function () { radio.wowListening = true; radio.startWowSearch(); });
        } else if (method === "/bleConnect" && !demoHold) {
            demoLater(3000, function () {
                radio.wowFound = [];
                radio.applyWowDevice({ device: { name: "LG WOWCAST WTP3", state: "connected", p2pAddress: "demo-p2p",
                                                 bleAddress: params.address[0] } });
            });
        } else if (method === "/p2pDisconnect" && !demoHold) {
            demoLater(1500, function () { radio.applyWowDevice({ device: copy(radio.wowDevice, { state: "disconnected" }) }); });
        } else if (method === "/p2pConnect" && !demoHold) {
            demoLater(2000, function () { radio.applyWowDevice({ device: copy(radio.wowDevice, { state: "connected" }) }); });
        }
    }
}
