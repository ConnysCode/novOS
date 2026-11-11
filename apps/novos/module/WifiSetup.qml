import QtQuick 2.12
import WebOSServices 1.0
import "."
import "ListScroll.js" as ListScroll

// Wi-Fi setup of Konzept 3: a modal flow in the screen centre. It talks to the same
// com.webos.service.wifi methods as LG's own network screen. A password stays in
// memory only for the running attempt and is never written or logged. The short
// confirmation dialogs of other pages run here too, see openDialog().
Item {
    id: setup

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property variant backdrop
    property string glassShader: ""
    property string shadowShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property var focusCurve: GlassStyle.curve

    property bool active: false          // the flow owns the keys
    property bool shown: false           // the card is on screen, set by the panel
    property string screen: ""
    property string listState: "searching"   // searching, ready, empty, unavailable
    property var networks: []
    property var dialog: ({})
    property string errorText: I18n.t("wifi", "error.not_saved")   // until showError() sets one
    property string listSignature: ""
    property string focusId: ""
    property bool focusAnimated: true

    // Current attempt.
    property var target: null
    property string password: ""
    property string entryValue: ""
    property string entryError: ""
    property bool showPassword: false
    property string customName: ""
    property string customSecurity: "psk"
    property string lastKey: "k-2-0"         // last QWERTZ key
    property string lastT9Key: "t-2"
    property int lastColumn: 0
    property string failureKey: ""            // error.* key of the failed attempt
    property bool internetKnown: false
    property int closeCountdown: 3
    property int forgetProfile: 0
    property string forgetName: ""

    signal networkChanged()              // the panel should read the state again
    signal textSaved(string value)       // the name entry was confirmed
    signal deviceNameSaved(string value) // the name of an input was confirmed
    signal profileNameSaved(string value) // the name of a profile was confirmed
    signal dialogConfirmed(string action)   // the page runs it, then closeFlow() or showError()

    readonly property int maxNetworks: 32
    readonly property var emptyNetwork: ({ name: "", showBand: false, secure: false, connected: false, bars: 1 })
    readonly property var messageScreens: ["open", "connecting", "connected", "failed", "forget", "error", "dialog", "dialogBusy"]
    readonly property bool isMessage: messageScreens.indexOf(screen) >= 0
    // TV and device names: the entry screens with a name, a counter and Save.
    readonly property bool isOwnName: screen === "tvName" || screen === "deviceName" || screen === "profileName"
    readonly property bool isNameEntry: screen === "customName" || isOwnName
    // LG's limits; a profile's name as long as LG's account app shows one.
    readonly property int nameLimit: screen === "deviceName" ? 30 : (screen === "profileName" ? 20 : 32)
    readonly property bool isEntry: screen === "password" || isNameEntry ||
                                    screen === "customPassword"
    readonly property bool isPasswordEntry: screen === "password" || screen === "customPassword"
    readonly property var message: messageOf(screen)
    readonly property string securityOfEntry: target ? target.securityType : "psk"
    readonly property int entryLimit: isNameEntry ? nameLimit : 64
    // The text with the T9 character that is not final yet.
    readonly property string typedValue: entryValue + keyboard.pendingChar
    readonly property bool entryValid: isNameEntry ? isValidName(typedValue)
                                                               : isValidPasskey(securityOfEntry, typedValue)

    function quoted(name) {
        return I18n.t("wifi", "format.quoted", { name: name });
    }

    function messageOf(name) {
        var title = target ? quoted(target.name) : "";
        if (name === "open") {
            return { icon: "wifi-44", title: I18n.t("wifi", "title.connect_open", { name: title }),
                     text: I18n.t("wifi", "text.open_network"),
                     buttons: [{ id: "confirmOpen", label: I18n.t("wifi", "button.connect") },
                               { id: "toList", label: I18n.t("global", "cancel") }] };
        }
        if (name === "connecting") {
            return { spinner: true, title: I18n.t("wifi", "title.connecting", { name: title }),
                     text: I18n.t("wifi", "text.few_seconds"),
                     buttons: [{ id: "cancelConnect", label: I18n.t("global", "cancel") }] };
        }
        if (name === "connected") {
            var seconds = closeCountdown === 1 ? I18n.t("wifi", "unit.second_one")
                                               : I18n.t("wifi", "unit.second_many", { count: closeCountdown });
            return { icon: "check-44", title: I18n.t("wifi", "title.connected", { name: title }),
                     text: internetKnown ? I18n.t("wifi", "text.closing_online", { seconds: seconds })
                                         : I18n.t("wifi", "text.closing", { seconds: seconds }),
                     buttons: [{ id: "done", label: I18n.t("global", "done") }] };
        }
        if (name === "failed") {
            return { icon: "wifi-off-44", title: I18n.t("wifi", "title.failed"),
                     text: failureKey !== "" ? I18n.t("wifi", failureKey, { name: title }) : "",
                     buttons: [{ id: "retry", label: I18n.t("global", "retry") },
                               { id: "toList", label: I18n.t("wifi", "button.choose_other") }] };
        }
        if (name === "forget") {
            return { icon: "wifi-44", title: I18n.t("wifi", "title.forget"),
                     text: I18n.t("wifi", "text.forget", { name: quoted(forgetName) }),
                     buttons: [{ id: "confirmForget", label: I18n.t("wifi", "button.forget"), danger: true },
                               { id: "done", label: I18n.t("global", "cancel") }] };
        }
        if (name === "error") {
            return { icon: "alert-44", title: I18n.t("wifi", "title.error"),
                     text: errorText, buttons: [{ id: "done", label: I18n.t("global", "ok") }] };
        }
        if (name === "dialog") {
            return { appIcon: dialog.appIcon, icon: dialog.icon, title: dialog.title, text: dialog.text,
                     buttons: [{ id: "dialogConfirm", label: dialog.confirm, danger: dialog.safe !== true },
                               { id: "done", label: I18n.t("global", "cancel") }] };
        }
        if (name === "dialogBusy") {
            return { spinner: true, title: dialog.busyTitle, text: I18n.t("wifi", "text.few_seconds"),
                     buttons: [] };
        }
        return { title: "", text: "", buttons: [] };
    }

    function isValidName(value) {
        var bytes = unescape(encodeURIComponent(value)).length;
        if (screen === "deviceName") return value.trim().length >= 1 && value.length <= 30;
        if (screen === "profileName") return value.trim().length >= 1 && value.length <= 20;
        return bytes >= 1 && bytes <= 32;
    }

    // Same rules as LG's network screen.
    function isValidPasskey(security, value) {
        var hex = /^[A-Fa-f0-9]*$/;
        if (security === "wep") {
            if (value.length === 5 || value.length === 13) return /^[\x00-\x7f]*$/.test(value);
            return (value.length === 10 || value.length === 26) && hex.test(value);
        }
        return (value.length >= 8 && value.length <= 63) || (value.length === 64 && hex.test(value));
    }

    function bandOf(frequency) {
        if (!frequency) return "";
        if (frequency < 3000) return "2,4 GHz";
        return frequency < 5925 ? "5 GHz" : "6 GHz";
    }

    // The band values above stay ids, only "2,4 GHz" reads differently per language.
    function bandLabel(band) {
        return band === "2,4 GHz" ? I18n.t("wifi", "band.ghz_2_4") : band;
    }

    // Secured or open, with the band when a name appears twice.
    function detailOf(network) {
        if (network.name === "") return "";
        if (network.showBand) {
            return network.secure ? I18n.t("wifi", "detail.secured_band", { band: bandLabel(network.band) })
                                  : I18n.t("wifi", "detail.open_band", { band: bandLabel(network.band) });
        }
        return network.secure ? I18n.t("wifi", "label.secured") : I18n.t("wifi", "label.open");
    }

    // One row per name and band. The band only shows when a name appears twice.
    function buildNetworks(found) {
        var result = [];
        var seen = {};
        var names = {};
        for (var i = 0; i < found.length; i++) {
            var info = found[i].networkInfo;
            if (!info || !info.supported || !info.displayName) continue;
            var security = (info.availableSecurityTypes || ["none"])[0];
            if (security === "ieee8021x") continue;     // no enterprise login in the design
            var bss = info.bssInfo && info.bssInfo[0];
            var band = bandOf(bss ? bss.frequency : 0);
            var key = info.displayName + "|" + band + "|" + security;
            if (seen[key] !== undefined) {
                var earlier = result[seen[key]];
                if (info.signalLevel <= earlier.level) continue;
                result[seen[key]] = null;
            }
            seen[key] = result.length;
            names[info.displayName] = (names[info.displayName] || 0) + 1;
            result.push({
                name: info.displayName, ssid: info.ssid, group: info.group || "",
                profileId: info.profileId || 0, securityType: security,
                secure: security !== "none", band: band,
                bars: Math.max(1, Math.min(3, info.signalBars || 1)),
                level: info.signalLevel || 0,
                connected: info.connectState === "ipConfigured"
            });
        }
        result = result.filter(function (network) { return network !== null; });
        result.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if ((a.profileId > 0) !== (b.profileId > 0)) return a.profileId > 0 ? -1 : 1;
            return b.level - a.level;
        });
        result = result.slice(0, maxNetworks);
        result.forEach(function (network) {
            network.showBand = names[network.name] > 1 && network.band !== "";
        });
        return result;
    }

    function setScreen(name, focus) {
        keyboard.cancelPending();
        focusAnimated = false;
        screen = name;
        focusId = focus;
        Qt.callLater(function () { setup.focusAnimated = true; });
    }

    // Filled while the network page opens, so that the modal never waits for rows.
    function prepareList() {
        wifiService.call("luna://com.webos.service.wifi", "/findnetworks", "{}");
    }

    function firstRow() {
        var first = 0;
        while (first < networks.length - 1 && networks[first].connected) first++;
        return first;
    }

    function openList() {
        clearAttempt();
        active = true;
        showList();
    }

    function showList() {
        if (networks.length === 0) {
            searchNetworks(false);
            return;
        }
        listState = "ready";
        listScroll = 0;
        setScreen("list", "row-" + firstRow());
        listRefresh.restart();
    }

    function openForget(profileId, name) {
        forgetProfile = profileId;
        forgetName = name;
        active = true;
        setScreen("forget", "done");
    }

    // { action, appIcon or icon, title, text, confirm, busyTitle, safe }. Destructive
    // dialogs start on Cancel, safe ones on the confirm button.
    function openDialog(config) {
        dialog = config;
        active = true;
        setScreen("dialog", config.safe === true ? "dialogConfirm" : "done");
    }

    // The name of the TV, with the same keyboard as the Wi-Fi setup.
    function openTvName(current) {
        active = true;
        entryValue = current;
        entryError = "";
        startKeyboard("tvName");
    }

    // The name of a profile (K3-Profil-Einst-Bearbeiten): up to 20 characters.
    function openProfileName(current) {
        active = true;
        entryValue = current.substring(0, 20);
        entryError = "";
        startKeyboard("profileName");
    }

    // The name of an input, as in LG's input editor: up to 30 characters.
    function openDeviceName(current) {
        active = true;
        entryValue = current.substring(0, 30);
        entryError = "";
        startKeyboard("deviceName");
    }

    function showError(text) {
        errorText = text;
        setScreen("error", "done");
    }

    function clearAttempt() {
        target = null;
        password = "";
        entryValue = "";
        entryError = "";
        showPassword = false;
        customName = "";
        customSecurity = "psk";
    }

    function closeFlow() {
        connectTimeout.stop();
        statusPoll.stop();
        countdown.stop();
        scanDelay.stop();
        listRefresh.stop();
        clearAttempt();
        active = false;
    }

    // The panel calls this once the card has faded out.
    function reset() {
        screen = "";
        focusId = "";
    }

    function searchNetworks(fresh) {
        listState = "searching";
        networks = [];
        listSignature = "";
        listScroll = 0;
        setScreen("list", "add");
        if (fresh) {
            wifiService.call("luna://com.webos.service.wifi", "/scan", "{}");
            scanDelay.restart();
        } else {
            wifiService.call("luna://com.webos.service.wifi", "/findnetworks", "{}");
        }
    }

    // The first answer can be a partial scan, so a second one follows. Rows only
    // change when the list did, and the focus stays on its network.
    function applyNetworks(found) {
        var focused = focusId.indexOf("row-") === 0 ? networks[Number(focusId.substring(4))] : null;
        var wasReady = listState === "ready" && networks.length > 0;
        var next = buildNetworks(found);
        var signature = JSON.stringify(next.map(function (network) {
            return [network.name, network.band, network.connected, network.bars, network.secure, network.showBand];
        }));
        var changed = signature !== listSignature;
        listSignature = signature;
        if (changed) networks = next;
        listState = next.length > 0 ? "ready" : "empty";
        if (screen !== "list") return;
        if (wasReady) {
            if (!changed || !focused) return;
            for (var i = 0; i < next.length; i++) {
                if (next[i].name === focused.name && next[i].band === focused.band) {
                    focusId = "row-" + i;
                    return;
                }
            }
            focusId = "row-" + firstRow();
            return;
        }
        focusId = next.length > 0 ? "row-" + firstRow() : "refresh";
        listRefresh.restart();
    }

    function chooseNetwork(network) {
        if (network.connected) return;
        target = network;
        if (network.profileId > 0) {
            connect();
        } else if (network.secure) {
            openEntry("password");
        } else {
            setScreen("open", "confirmOpen");
        }
    }

    function openEntry(name) {
        entryValue = name === "customName" ? customName : "";
        entryError = "";
        showPassword = false;
        startKeyboard(name);
    }

    // Every entry opens in the mode used last, on the first letter key.
    function startKeyboard(name) {
        keyboard.reset(GlassStyle.keyboardMode);
        lastKey = "k-2-0";
        lastT9Key = "t-2";
        lastColumn = 0;
        setScreen(name, keyboard.mode === "t9" ? lastT9Key : lastKey);
    }

    function setKeyboardMode(mode) {
        if (keyboard.mode === mode) return;
        keyboard.commitPending();
        keyboard.mode = mode;
        GlassStyle.keyboardMode = mode;
    }

    function currentLastKey() {
        return keyboard.mode === "t9" ? lastT9Key : lastKey;
    }

    function submitEntry() {
        keyboard.commitPending();
        if (!entryValid) return;
        if (screen === "tvName") {
            textSaved(entryValue);
            closeFlow();
        } else if (screen === "deviceName") {
            deviceNameSaved(entryValue.trim());
            closeFlow();
        } else if (screen === "profileName") {
            profileNameSaved(entryValue.trim());
            closeFlow();
        } else if (screen === "customName") {
            customName = entryValue;
            setScreen("customSecurity", customSecurity === "none" ? "secOpen" : "secSecured");
        } else {
            password = entryValue;
            connect();
        }
    }

    function continueCustom() {
        target = { name: customName, ssid: customName, group: "", profileId: 0,
                   securityType: customSecurity, secure: customSecurity !== "none", hidden: true };
        if (target.secure) openEntry("customPassword");
        else connect();
    }

    function connectRequest() {
        var request = {};
        if (target.profileId > 0 && password === "") {
            request.profileId = target.profileId;
        } else {
            request.ssid = target.ssid;
        }
        if (target.group !== "") request.group = target.group;
        if (target.hidden) request.wasCreatedWithJoinOther = true;
        if (password !== "") {
            request.security = { securityType: target.securityType,
                                 simpleSecurity: { passKey: password } };
        }
        return JSON.stringify(request);
    }

    function connect() {
        failureKey = "";
        internetKnown = false;
        setScreen("connecting", "cancelConnect");
        wifiService.call("luna://com.webos.service.wifi", "/cancel", "{}");
        wifiService.call("luna://com.webos.service.wifi", "/connect", connectRequest());
        connectTimeout.restart();
        statusPoll.restart();
    }

    function cancelConnect() {
        connectTimeout.stop();
        statusPoll.stop();
        wifiService.call("luna://com.webos.service.wifi", "/cancel", "{}");
        toList();
    }

    function toList() {
        clearAttempt();
        showList();
    }

    function connectSucceeded() {
        connectTimeout.stop();
        statusPoll.stop();
        password = "";
        closeCountdown = 3;
        setScreen("connected", "done");
        countdown.restart();
        wifiService.call("luna://com.webos.service.connectionmanager", "/getStatus", "{}");
        networkChanged();
    }

    function connectFailed(code) {
        connectTimeout.stop();
        statusPoll.stop();
        wifiService.call("luna://com.webos.service.wifi", "/cancel", "{}");
        if (code === 10 || code === 15) {
            // A saved password can be outdated too, so this always asks again.
            if (target.secure) {
                password = "";
                openEntry(target.hidden ? "customPassword" : "password");
                entryError = "error.wrong_password";
                return;
            }
        }
        // The text is built in messageOf(), so it follows a change of language.
        if (code === 11 || code === 12) {
            failureKey = "error.rejected";
        } else if (code === 14) {
            failureKey = "error.no_ip";
        } else {
            failureKey = "error.unreachable";
        }
        setScreen("failed", "retry");
    }

    function matchesTarget(info) {
        if (!target) return false;
        if (target.profileId > 0 && info.profileId === target.profileId) return true;
        return info.ssid === target.ssid;
    }

    function handleStatus(response) {
        var info = response.networkInfo;
        if (screen !== "connecting" || !info || !matchesTarget(info)) return;
        if (info.connectState === "ipConfigured") connectSucceeded();
        else if (info.connectState === "ipFailed") connectFailed(14);
    }

    function forget() {
        wifiService.call("luna://com.webos.service.wifi", "/deleteprofile",
                         JSON.stringify({ profileIdsArray: [forgetProfile] }));
    }

    function handleReply(method, payload) {
        var response = {};
        try {
            response = JSON.parse(payload);
        } catch (error) {
            response = { returnValue: false };
        }
        if (method === "/findnetworks") {
            if (screen !== "list" && screen !== "") return;
            if (response.returnValue === false) {
                listState = "unavailable";
                focusId = "refresh";
            } else {
                applyNetworks(response.foundNetworks || []);
            }
        } else if (method === "/connect") {
            if (screen === "connecting" && response.returnValue === false) {
                connectFailed(response.errorCode || -1);
            }
        } else if (method === "/getstatus") {
            handleStatus(response);
        } else if (method === "/getStatus") {
            internetKnown = !!(response.wifi && response.wifi.onInternet === "yes");
        } else if (method === "/deleteprofile") {
            if (response.returnValue === false) {
                setScreen("error", "done");
            } else {
                networkChanged();
                closeFlow();
            }
        }
    }

    Service {
        id: wifiService
        appId: "com.webos.app.quicksettings"
        onResponse: setup.handleReply(method, payload)
        onError: setup.handleReply(method, payload)
    }

    // A real scan takes a few seconds and only then fills the list.
    Timer {
        id: scanDelay
        interval: 3500
        onTriggered: wifiService.call("luna://com.webos.service.wifi", "/findnetworks", "{}")
    }

    Timer {
        id: listRefresh
        interval: 3000
        onTriggered: wifiService.call("luna://com.webos.service.wifi", "/findnetworks", "{}")
    }

    // The service answers a connect when it ends, which can take long.
    Timer {
        id: statusPoll
        interval: 1000
        repeat: true
        onTriggered: wifiService.call("luna://com.webos.service.wifi", "/getstatus", "{}")
    }

    Timer {
        id: connectTimeout
        interval: 60000
        onTriggered: setup.connectFailed(-1)
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            if (setup.closeCountdown > 1) {
                setup.closeCountdown--;
            } else {
                stop();
                setup.finishFlow();
            }
        }
    }

    function finishFlow() {
        closeFlow();
    }

    // ---- Keys ------------------------------------------------------------

    function handleKey(key, autoRepeat) {
        var ok = Remote.isOk(key);
        if (ok) {
            if (!autoRepeat || focusId === "delete" || focusId === "t-delete") {
                keyboard.pressKey(focusId);
                activate(focusId);
            } else if (keyboard.isT9Key(focusId)) {
                keyboard.holdT9(focusId);
            }
            return;
        }
        if (key >= Qt.Key_0 && key <= Qt.Key_9) {
            if (isEntry) typeDigit(String(key - Qt.Key_0), autoRepeat);
            return;
        }
        if (key !== Qt.Key_Up && key !== Qt.Key_Down && key !== Qt.Key_Left && key !== Qt.Key_Right) return;
        if (isMessage) moveInMessage(key);
        else if (screen === "list") moveInList(key);
        else if (screen === "customSecurity") moveInSecurity(key);
        else if (isEntry) moveInEntry(key);
    }

    function moveInMessage(key) {
        var buttons = message.buttons;
        var index = -1;
        for (var i = 0; i < buttons.length; i++) {
            if (buttons[i].id === focusId) index = i;
        }
        if (key === Qt.Key_Up && index > 0) focusId = buttons[index - 1].id;
        if (key === Qt.Key_Down && index >= 0 && index < buttons.length - 1) focusId = buttons[index + 1].id;
    }

    function moveInList(key) {
        var isRow = focusId.indexOf("row-") === 0;
        var index = isRow ? Number(focusId.substring(4)) : -1;
        var refreshUsable = listState !== "searching";
        if (key === Qt.Key_Up) {
            if (isRow && index > 0) focusId = "row-" + (index - 1);
            else if (!isRow && networks.length > 0) focusId = "row-" + (networks.length - 1);
        } else if (key === Qt.Key_Down) {
            if (isRow) focusId = index < networks.length - 1 ? "row-" + (index + 1) : "add";
        } else if (key === Qt.Key_Right && focusId === "add" && refreshUsable) {
            focusId = "refresh";
        } else if (key === Qt.Key_Left && focusId === "refresh") {
            focusId = "add";
        }
    }

    function moveInSecurity(key) {
        if (key === Qt.Key_Up) {
            if (focusId === "next") focusId = customSecurity === "none" ? "secOpen" : "secSecured";
            else if (focusId === "secOpen") selectSecurity("secSecured");
        } else if (key === Qt.Key_Down) {
            if (focusId === "secSecured") selectSecurity("secOpen");
            else focusId = "next";
        }
    }

    function selectSecurity(id) {
        focusId = id;
        customSecurity = id === "secOpen" ? "none" : "psk";
    }

    function leftOfKeys(row) {
        var submit = entryValid ? "submit" : "";
        var show = isPasswordEntry ? "show" : "";
        var first = row <= 2 ? (show || submit) : (submit || show);
        return first;
    }

    function moveToKey(id) {
        if (id === "" || !keyboard.isEnabled(id)) return;
        focusId = id;
        rememberKey(id);
    }

    function rememberKey(id) {
        if (keyboard.isT9Key(id)) lastT9Key = id;
        else if (keyboard.isKey(id)) lastKey = id;
    }

    // A number key of the remote: QWERTZ hands over to T9 and the digit types at once.
    // Holding it types the digit itself.
    function typeDigit(digit, held) {
        var id = "t-" + digit;
        if (held) {
            keyboard.holdT9(id);
            return;
        }
        setKeyboardMode("t9");
        focusId = id;
        lastT9Key = id;
        keyboard.pressKey(id);
        keyboard.tapT9(id);
    }

    // Up from the top row of keys. The other mode lies under the focus, so that a
    // single OK switches.
    function toModeSwitch() {
        keyboard.commitPending();
        focusId = keyboard.mode === "t9" ? "mode-qwertz" : "mode-t9";
    }

    function moveInT9(key) {
        var next = keyboard.t9Neighbour(focusId, key);
        if (next !== "") {
            moveToKey(next);
        } else if (key === Qt.Key_Up) {
            toModeSwitch();
        } else if (key === Qt.Key_Left && leftOfKeys(keyboard.t9Row(focusId)) !== "") {
            keyboard.commitPending();
            focusId = leftOfKeys(keyboard.t9Row(focusId));
        }
    }

    function moveInEntry(key) {
        if (focusId === "mode-qwertz" || focusId === "mode-t9") {
            if (key === Qt.Key_Left && focusId === "mode-t9") focusId = "mode-qwertz";
            else if (key === Qt.Key_Right && focusId === "mode-qwertz") focusId = "mode-t9";
            else if (key === Qt.Key_Down) focusId = currentLastKey();
            return;
        }
        if (keyboard.isT9Key(focusId)) {
            moveInT9(key);
            return;
        }
        if (focusId === "show" || focusId === "submit") {
            if (key === Qt.Key_Right) focusId = currentLastKey();
            else if (key === Qt.Key_Up && focusId === "submit" && isPasswordEntry) focusId = "show";
            else if (key === Qt.Key_Down && focusId === "show" && entryValid) focusId = "submit";
            return;
        }
        if (focusId.indexOf("k-") === 0) {
            var parts = focusId.split("-");
            var row = Number(parts[1]);
            var col = Number(parts[2]);
            if (key === Qt.Key_Left) {
                if (col > 0) moveToKey("k-" + row + "-" + (col - 1));
                else if (leftOfKeys(row) !== "") { lastKey = focusId; focusId = leftOfKeys(row); }
            } else if (key === Qt.Key_Right) {
                if (col < keyboard.columns - 1) moveToKey("k-" + row + "-" + (col + 1));
            } else if (key === Qt.Key_Up) {
                if (row > 0) moveToKey("k-" + (row - 1) + "-" + col);
                else toModeSwitch();
            } else if (row < 3) {
                moveToKey("k-" + (row + 1) + "-" + col);
            } else {
                lastColumn = col;
                var below = keyboard.bottomKeyAt(col);
                moveToKey(keyboard.isEnabled(below) ? below : "symbols");
            }
            return;
        }
        var bottom = keyboard.bottomKeys;
        var index = keyboard.bottomIndexOf(focusId);
        if (key === Qt.Key_Up) {
            var keyHere = bottom[index];
            var inside = lastColumn * 64 >= keyHere.x && lastColumn * 64 < keyHere.x + keyHere.w;
            moveToKey("k-3-" + (inside ? lastColumn : keyHere.col));
        } else if (key === Qt.Key_Right) {
            if (index < bottom.length - 1) moveToKey(bottom[index + 1].id);
        } else if (key === Qt.Key_Left) {
            var previous = index - 1;
            if (previous >= 0 && !keyboard.isEnabled(bottom[previous].id)) previous--;
            if (previous >= 0) {
                moveToKey(bottom[previous].id);
            } else if (leftOfKeys(4) !== "") {
                lastKey = focusId;
                focusId = leftOfKeys(4);
            }
        }
    }

    function typeCharacter(value) {
        if (entryValue.length >= entryLimit) return;
        entryValue += value;
        entryError = "";
    }

    function deleteCharacter() {
        entryValue = entryValue.substring(0, entryValue.length - 1);
        entryError = "";
    }

    function pressKey(id) {
        if (id.indexOf("k-") === 0) {
            var parts = id.split("-");
            typeCharacter(keyboard.charAt(Number(parts[1]), Number(parts[2])));
        } else if (id === "space") {
            typeCharacter(" ");
        } else if (id === "delete") {
            deleteCharacter();
        } else if (id === "shift") {
            if (keyboard.isEnabled("shift")) keyboard.shifted = !keyboard.shifted;
        } else if (id === "symbols") {
            keyboard.symbols = !keyboard.symbols;
        } else if (id === "t-delete") {
            // A character still being chosen goes first.
            if (!keyboard.cancelPending()) deleteCharacter();
        } else if (id === "t-shift") {
            keyboard.commitPending();
            keyboard.shifted = !keyboard.shifted;
        } else if (id === "t-symbols") {
            // T9 has no symbols of its own: the QWERTZ symbols take over.
            setKeyboardMode("qwertz");
            keyboard.symbols = true;
            focusId = "symbols";
            lastKey = "symbols";
            lastColumn = 2;
        } else if (keyboard.isT9Key(id)) {
            lastT9Key = id;
            keyboard.tapT9(id);
        }
    }

    function activate(id) {
        if (id.indexOf("row-") === 0) chooseNetwork(networks[Number(id.substring(4))]);
        else if (id === "add") openEntry("customName");
        else if (id === "refresh") searchNetworks(listState !== "unavailable");
        else if (id === "secSecured" || id === "secOpen") { selectSecurity(id); continueCustom(); }
        else if (id === "next") continueCustom();
        else if (id === "show") showPassword = !showPassword;
        else if (id === "mode-qwertz" || id === "mode-t9") setKeyboardMode(id.substring(5));
        else if (id === "submit") submitEntry();
        else if (id === "confirmOpen") connect();
        else if (id === "toList") toList();
        else if (id === "cancelConnect") cancelConnect();
        else if (id === "done") finishFlow();
        else if (id === "retry") connect();
        else if (id === "confirmForget") forget();
        else if (id === "dialogConfirm") {
            setScreen("dialogBusy", "");
            dialogConfirmed(dialog.action);
        }
        else pressKey(id);
    }

    function back() {
        if (screen === "dialogBusy") return;
        if (screen === "list" || screen === "connected" || screen === "forget" || screen === "error" ||
            screen === "dialog" || isOwnName) {
            finishFlow();
        } else if (screen === "password" || screen === "open" || screen === "failed") {
            toList();
        } else if (screen === "connecting") {
            cancelConnect();
        } else if (screen === "customName") {
            toList();
        } else if (screen === "customSecurity") {
            openEntry("customName");
        } else if (screen === "customPassword") {
            setScreen("customSecurity", customSecurity === "none" ? "secOpen" : "secSecured");
        }
    }

    // ---- Layout ----------------------------------------------------------

    readonly property size cardSize: {
        if (screen === "list") return Qt.size(1120, 740);
        if (screen === "customSecurity") return Qt.size(1120, 428);
        if (isEntry) return Qt.size(1200, 484);
        return Qt.size(720, messageHeight);
    }
    readonly property real messageHeight: (88 + 28 + 14 + 36 + 48 + 40) * 1 +
        (messageTitle.height + messageText.height) / unit +
        message.buttons.length * 72 + Math.max(0, message.buttons.length - 1) * 12

    // Position of the list inside the card, in logical px.
    readonly property int listTop: 132
    readonly property int listHeight: 476
    readonly property int rowPitch: 80
    readonly property int listFade: 96
    readonly property int listLimit: Math.max(0, networks.length * rowPitch - 4 - listHeight)
    property int listScroll: 0

    onFocusIdChanged: {
        if (focusId.indexOf("row-") === 0) {
            listScroll = ListScroll.centred(Number(focusId.substring(4)) * rowPitch, rowPitch - 4, listHeight,
                                            listLimit + listHeight);
        }
    }

    readonly property rect focusRect: rectOf(focusId, cardSize, listScroll, footerAdd.width,
                                             footerRefresh.width, footerNext.width, modeSwitch.width)

    function rectOf(id, size, scroll, addWidth, refreshWidth, nextWidth, switchWidth) {
        var u = unit;
        if (id === "") return Qt.rect(0, 0, 0, 0);
        if (id.indexOf("row-") === 0) {
            return Qt.rect(40 * u, (listTop + Number(id.substring(4)) * rowPitch - scroll) * u, 1040 * u, 76 * u);
        }
        if (id === "add") return Qt.rect(48 * u, 636 * u, addWidth, 64 * u);
        if (id === "refresh") return Qt.rect(size.width * u - 48 * u - refreshWidth, 636 * u, refreshWidth, 64 * u);
        if (id === "secSecured") return Qt.rect(40 * u, 132 * u, 1040 * u, 80 * u);
        if (id === "secOpen") return Qt.rect(40 * u, 216 * u, 1040 * u, 80 * u);
        if (id === "next") return Qt.rect(size.width * u - 48 * u - nextWidth, 324 * u, nextWidth, 64 * u);
        if (id === "show") return Qt.rect(40 * u, 281 * u, 380 * u, 64 * u);
        if (id === "submit") return Qt.rect(40 * u, 372 * u, 380 * u, 72 * u);
        if (id === "mode-qwertz" || id === "mode-t9") {
            var segment = modeSwitch.segmentRect(id.substring(5));
            return Qt.rect(header.x + segment.x, header.y + segment.y, segment.width, segment.height);
        }
        if (keyboard.isKey(id)) {
            var key = keyboard.keyRect(id);
            return Qt.rect(464 * u + key.x, 132 * u + key.y, key.width, key.height);
        }
        var buttons = message.buttons;
        var count = buttons.length;
        for (var i = 0; i < count; i++) {
            if (buttons[i].id === id) {
                var top = size.height - 40 - count * 72 - (count - 1) * 12 + i * 84;
                return Qt.rect(40 * u, top * u, 640 * u, 72 * u);
            }
        }
        return Qt.rect(0, 0, 0, 0);
    }

    readonly property real focusRadius: {
        if (keyboard.isT9Key(focusId)) return 20;
        if (focusId === "mode-qwertz" || focusId === "mode-t9") return 28;
        if (focusId.indexOf("k-") === 0 || keyboard.bottomIndexOf(focusId) >= 0) return 16;
        if (focusId === "add" || focusId === "refresh" || focusId === "next") return 32;
        if (focusId.indexOf("row-") === 0 || focusId === "show" ||
            focusId === "secSecured" || focusId === "secOpen") return 26;
        return 36;
    }
    readonly property real focusScaleNow: {
        if (focusId.indexOf("k-") === 0) return 1.08;
        return keyboard.bottomIndexOf(focusId) >= 0 ? 1.05 : 1.03;
    }

    Item {
        anchors.fill: parent
        visible: opacity > 0
        opacity: setup.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        MouseArea {
            anchors.fill: parent
        }

        GlassCard {
            id: card
            x: (setup.width - width) / 2
            y: (setup.height - height) / 2
            width: setup.cardSize.width * setup.unit
            height: setup.cardSize.height * setup.unit
            unit: setup.unit
            backdrop: setup.backdrop
            glassShader: setup.glassShader
            backdropMargin: setup.backdropMargin
            backdropArea: setup.backdropArea
            hasBackdrop: setup.hasBackdrop
            glideCurve: setup.focusCurve

            // The single focus surface of the flow.
            FocusSurface {
                id: focusSurface
                x: setup.focusRect.x
                y: setup.focusRect.y
                width: setup.focusRect.width
                height: setup.focusRect.height
                visible: setup.focusId !== ""
                unit: setup.unit
                animated: setup.focusAnimated
                focusScale: setup.focusScaleNow
                pressScale: keyboard.pressScaleOf(setup.focusId)
                radius: setup.focusRadius
            }

            // Header of list, security and entry steps.
            Item {
                id: header
                x: 48 * setup.unit
                y: 40 * setup.unit
                width: card.width - 96 * setup.unit
                height: 64 * setup.unit
                visible: !setup.isMessage

                GlassControl {
                    width: 64 * setup.unit
                    height: width
                    unit: setup.unit
                    radius: 32
                    fill: "#24ffffff"

                    Image {
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl(setup.screen === "list" ?
                                               (setup.listState === "unavailable" ? "icons/wifi-off-32.png" : "icons/wifi-32.png") :
                                               "icons/back-26.png")
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: setup.screen !== "list"
                        onClicked: setup.back()
                    }
                }

                Text {
                    x: 84 * setup.unit
                    y: 3 * setup.unit
                    width: parent.width - x - setup.switchRoom
                    height: 41 * setup.unit
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: setup.headerTitle
                    color: "#ffffff"
                    font.family: setup.titleFont
                    font.pixelSize: 34 * setup.unit
                    font.letterSpacing: -0.68 * setup.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    x: 84 * setup.unit
                    y: 40 * setup.unit
                    width: parent.width - x - setup.switchRoom
                    height: 26 * setup.unit
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: setup.headerSubtitle
                    color: GlassStyle.textSecondary
                    font.family: setup.valueFont
                    font.pixelSize: 20 * setup.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                // QWERTZ | T9 of every text entry.
                KeyboardModeSwitch {
                    id: modeSwitch
                    x: parent.width - width
                    visible: setup.isEntry
                    unit: setup.unit
                    labelFont: setup.rowFont
                    mode: keyboard.mode
                    focusedSegment: setup.focusId === "mode-qwertz" ? "qwertz" :
                                    (setup.focusId === "mode-t9" ? "t9" : "")
                    onChosen: {
                        setup.focusId = "mode-" + choice;
                        setup.setKeyboardMode(choice);
                    }
                }
            }

            // List step.
            Item {
                anchors.fill: parent
                visible: setup.screen === "list"

                Item {
                    x: 20 * setup.unit
                    y: setup.listTop * setup.unit
                    width: 1080 * setup.unit
                    height: setup.listHeight * setup.unit
                    visible: setup.listState === "ready"

                    // The list fades out at whichever end has more rows.
                    layer.enabled: true
                    layer.effect: EdgeFade {
                        topFade: setup.listFade / setup.listHeight
                        bottomFade: setup.listFade / setup.listHeight
                        topAmount: setup.listScroll > 0 ? 1 : 0
                        bottomAmount: setup.listScroll < setup.listLimit ? 1 : 0
                    }

                    Item {
                        id: listContent
                        width: parent.width
                        y: -setup.listScroll * setup.unit

                        Behavior on y {
                            enabled: setup.focusAnimated
                            NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: setup.focusCurve }
                        }

                        // A fixed pool of rows. New scan results only change their
                        // text, because rebuilding them stalled the key handling.
                        Repeater {
                            model: setup.maxNetworks

                            Item {
                                id: networkRow
                                readonly property var network: setup.networks[index] || setup.emptyNetwork
                                readonly property bool focused: setup.focusId === "row-" + index
                                visible: index < setup.networks.length
                                x: 20 * setup.unit
                                y: index * setup.rowPitch * setup.unit
                                width: 1040 * setup.unit
                                height: 76 * setup.unit

                                Text {
                                    x: 24 * setup.unit
                                    y: 10 * setup.unit
                                    width: parent.width - x - 330 * setup.unit
                                    height: 29 * setup.unit
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: networkRow.network.name
                                    color: networkRow.focused ? GlassStyle.focusText : "#ffffff"
                                    font.family: setup.rowFont
                                    font.pixelSize: 23 * setup.unit
                                    font.hintingPreference: Font.PreferNoHinting
                                }

                                Text {
                                    x: 24 * setup.unit
                                    y: 41 * setup.unit
                                    height: 22 * setup.unit
                                    verticalAlignment: Text.AlignVCenter
                                    text: setup.detailOf(networkRow.network)
                                    color: networkRow.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                                    font.family: setup.valueFont
                                    font.pixelSize: 17 * setup.unit
                                    font.hintingPreference: Font.PreferNoHinting
                                }

                                GlassControl {
                                    id: connectedPill
                                    visible: networkRow.network.connected
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    anchors.rightMargin: 118 * setup.unit
                                    width: pillRow.width + 24 * setup.unit
                                    height: 34 * setup.unit
                                    unit: setup.unit
                                    radius: 17
                                    fill: networkRow.focused ? "#1a0b0c10" : "#29ffffff"

                                    Row {
                                        id: pillRow
                                        x: 10 * setup.unit
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6 * setup.unit

                                        Image {
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: Qt.resolvedUrl("icons/check-18.png")
                                            visible: !networkRow.focused
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.t("wifi", "label.connected")
                                            color: networkRow.focused ? GlassStyle.focusText : "#ffffff"
                                            font.family: setup.rowFont
                                            font.pixelSize: 17 * setup.unit
                                            font.hintingPreference: Font.PreferNoHinting
                                        }
                                    }
                                }

                                Image {
                                    visible: networkRow.network.secure
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.width - 98 * setup.unit
                                    source: Qt.resolvedUrl(networkRow.focused ? "icons/lock-24-dark.png" : "icons/lock-24.png")
                                }

                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.width - 54 * setup.unit
                                    source: Qt.resolvedUrl("icons/signal-" + networkRow.network.bars + "-30" +
                                                           (networkRow.focused ? "-dark" : "") + ".png")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        setup.focusId = "row-" + index;
                                        setup.activate(setup.focusId);
                                    }
                                }
                            }
                        }
                    }
                }

                // Searching, nothing found, Wi-Fi not available.
                Column {
                    y: setup.listTop * setup.unit + (setup.listHeight * setup.unit - height) / 2
                    width: parent.width
                    visible: setup.listState !== "ready"
                    spacing: 0

                    Item {
                        width: parent.width
                        height: (setup.listState === "searching" ? 44 : 72) * setup.unit

                        Spinner {
                            anchors.centerIn: parent
                            size: 44 * setup.unit
                            lineWidth: 4 * setup.unit
                            running: setup.shown && setup.screen === "list" && setup.listState === "searching"
                            visible: running
                        }

                        GlassControl {
                            anchors.centerIn: parent
                            visible: setup.listState !== "searching"
                            width: 72 * setup.unit
                            height: width
                            unit: setup.unit
                            radius: 36
                            fill: "#24ffffff"

                            Image {
                                anchors.centerIn: parent
                                source: Qt.resolvedUrl(setup.listState === "unavailable" ?
                                                       "icons/wifi-off-36.png" : "icons/wifi-36.png")
                            }
                        }
                    }

                    Item { width: 1; height: 20 * setup.unit }

                    Text {
                        width: parent.width
                        height: 30 * setup.unit
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: setup.listState === "searching" ? I18n.t("wifi", "state.searching") :
                              (setup.listState === "empty" ? I18n.t("wifi", "state.empty") : I18n.t("wifi", "state.unavailable"))
                        color: "#ffffff"
                        font.family: setup.rowFont
                        font.pixelSize: 24 * setup.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Item { width: 1; height: 6 * setup.unit }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 520 * setup.unit
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                        text: setup.listState === "searching" ? I18n.t("wifi", "text.few_seconds") :
                              (setup.listState === "empty" ? I18n.t("wifi", "hint.empty") :
                               I18n.t("wifi", "hint.unavailable"))
                        color: GlassStyle.textSecondary
                        font.family: setup.valueFont
                        font.pixelSize: 18 * setup.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }

                FooterButton {
                    id: footerAdd
                    x: 48 * setup.unit
                    y: 636 * setup.unit
                    unit: setup.unit
                    fontFamily: setup.rowFont
                    label: I18n.t("wifi", "button.add_other")
                    icon: "plus-22"
                    focused: setup.focusId === "add"
                    onClicked: { setup.focusId = "add"; setup.activate("add"); }
                }

                FooterButton {
                    id: footerRefresh
                    x: parent.width - width - 48 * setup.unit
                    y: 636 * setup.unit
                    unit: setup.unit
                    fontFamily: setup.rowFont
                    label: setup.listState === "unavailable" ? I18n.t("global", "retry") : I18n.t("wifi", "button.search_again")
                    icon: "refresh-22"
                    focused: setup.focusId === "refresh"
                    opacity: setup.listState === "searching" ? 0.4 : 1
                    onClicked: {
                        if (setup.listState !== "searching") {
                            setup.focusId = "refresh";
                            setup.activate("refresh");
                        }
                    }
                }
            }

            // Security step of "add another network".
            Item {
                anchors.fill: parent
                visible: setup.screen === "customSecurity"

                Repeater {
                    model: [
                        { id: "secSecured", value: "psk", title: I18n.t("wifi", "label.secured"),
                          hint: I18n.t("wifi", "hint.secured"), y: 132 },
                        { id: "secOpen", value: "none", title: I18n.t("wifi", "label.open"),
                          hint: I18n.t("wifi", "hint.open"), y: 216 }
                    ]

                    Item {
                        readonly property bool focused: setup.focusId === modelData.id
                        x: 40 * setup.unit
                        y: modelData.y * setup.unit
                        width: 1040 * setup.unit
                        height: 80 * setup.unit

                        Text {
                            x: 20 * setup.unit
                            y: 12 * setup.unit
                            height: 28 * setup.unit
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.title
                            color: parent.focused ? GlassStyle.focusText : "#ffffff"
                            font.family: setup.rowFont
                            font.pixelSize: 22 * setup.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Text {
                            x: 20 * setup.unit
                            y: 42 * setup.unit
                            height: 22 * setup.unit
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.hint
                            color: parent.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                            font.family: setup.valueFont
                            font.pixelSize: 17 * setup.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Image {
                            visible: setup.customSecurity === modelData.value
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width - 44 * setup.unit
                            source: Qt.resolvedUrl(parent.focused ? "icons/check-24-dark.png" : "icons/check-24.png")
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: setup.activate(modelData.id)
                        }
                    }
                }

                FooterButton {
                    id: footerNext
                    x: parent.width - width - 48 * setup.unit
                    y: 324 * setup.unit
                    unit: setup.unit
                    fontFamily: setup.rowFont
                    label: I18n.t("global", "next")
                    focused: setup.focusId === "next"
                    onClicked: setup.activate("next")
                }
            }

            // Text entry with the keyboard.
            Item {
                anchors.fill: parent
                visible: setup.isEntry

                Text {
                    x: 48 * setup.unit
                    y: 132 * setup.unit
                    height: 23 * setup.unit
                    verticalAlignment: Text.AlignVCenter
                    text: setup.isOwnName ? I18n.t("wifi", "label.name") :
                          (setup.screen === "customName" ? I18n.t("wifi", "label.network_name") : I18n.t("wifi", "label.password"))
                    color: GlassStyle.textSecondary
                    font.family: setup.rowFont
                    font.pixelSize: 18 * setup.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Rectangle {
                    id: entryField
                    x: 40 * setup.unit
                    y: 163 * setup.unit
                    width: 380 * setup.unit
                    height: 72 * setup.unit
                    radius: 26 * setup.unit
                    color: "transparent"
                    clip: true

                    readonly property bool masked: setup.isPasswordEntry && !setup.showPassword
                    readonly property real room: width - 48 * setup.unit

                    GlassControl {
                        anchors.fill: parent
                        unit: setup.unit
                        radius: 26
                        fill: "#38000000"
                        edge: "edge-field-26"
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        visible: setup.entryError !== ""
                        color: "transparent"
                        border.width: 2 * setup.unit
                        border.color: GlassStyle.danger
                    }

                    Item {
                        id: entryLine
                        x: 24 * setup.unit + Math.min(0, entryField.room - width - 4 * setup.unit)
                        width: entryText.width + pendingText.width
                        height: parent.height

                        Text {
                            id: entryText
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            text: entryField.masked ? Array(setup.entryValue.length + 1).join("•") : setup.entryValue
                            color: "#ffffff"
                            font.family: setup.rowFont
                            font.pixelSize: 26 * setup.unit
                            font.letterSpacing: (entryField.masked ? 3 : 0) * setup.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        // The T9 character being chosen, readable and underlined even in a
                        // password until it is final.
                        Text {
                            id: pendingText
                            x: entryText.width
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            text: keyboard.pendingChar
                            color: "#ffffff"
                            font.family: setup.rowFont
                            font.pixelSize: 26 * setup.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Rectangle {
                            visible: keyboard.pendingChar !== ""
                            x: pendingText.x
                            y: pendingText.baselineOffset + 6 * setup.unit
                            width: Math.max(pendingText.width, 10 * setup.unit)
                            height: 2 * setup.unit
                            radius: 1 * setup.unit
                            color: "#ffffff"
                        }
                    }

                    Rectangle {
                        x: entryLine.x + entryLine.width + 2 * setup.unit
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2 * setup.unit
                        height: 32 * setup.unit
                        radius: 1 * setup.unit
                        color: "#ffffff"
                        visible: setup.shown

                        SequentialAnimation on opacity {
                            running: setup.shown && setup.isEntry
                            loops: Animation.Infinite
                            PropertyAction { value: 1 }
                            PauseAnimation { duration: 550 }
                            PropertyAction { value: 0 }
                            PauseAnimation { duration: 550 }
                        }
                    }
                }

                Row {
                    x: 48 * setup.unit
                    y: 243 * setup.unit
                    height: 22 * setup.unit
                    spacing: 8 * setup.unit

                    Image {
                        visible: setup.entryError !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl("icons/alert-20.png")
                    }

                    Text {
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: setup.entryHint
                        color: setup.entryError !== "" ? GlassStyle.danger : GlassStyle.textDetail
                        font.family: setup.entryError !== "" ? setup.rowFont : setup.valueFont
                        font.pixelSize: 17 * setup.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }

                Item {
                    x: 40 * setup.unit
                    y: 281 * setup.unit
                    width: 380 * setup.unit
                    height: 64 * setup.unit
                    visible: setup.isPasswordEntry
                    readonly property bool focused: setup.focusId === "show"

                    Text {
                        x: 20 * setup.unit
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: I18n.t("wifi", "label.show_password")
                        color: parent.focused ? GlassStyle.focusText : "#ffffff"
                        font.family: setup.rowFont
                        font.pixelSize: 20 * setup.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    GlassSwitch {
                        x: parent.width - width - 20 * setup.unit
                        anchors.verticalCenter: parent.verticalCenter
                        unit: setup.unit
                        on: setup.showPassword
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { setup.focusId = "show"; setup.activate("show"); }
                    }
                }

                Item {
                    x: 40 * setup.unit
                    y: 372 * setup.unit
                    width: 380 * setup.unit
                    height: 72 * setup.unit
                    opacity: setup.entryValid ? 1 : 0.4
                    readonly property bool focused: setup.focusId === "submit"

                    GlassControl {
                        anchors.fill: parent
                        visible: !parent.focused
                        unit: setup.unit
                        radius: 36
                    }

                    Text {
                        anchors.centerIn: parent
                        text: setup.isOwnName ? I18n.t("global", "save") :
                              (setup.screen === "customName" ? I18n.t("global", "next") : I18n.t("wifi", "button.connect"))
                        color: parent.focused ? GlassStyle.focusText : "#ffffff"
                        font.family: setup.rowFont
                        font.pixelSize: 22 * setup.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (setup.entryValid) setup.activate("submit")
                    }
                }

                OnScreenKeyboard {
                    id: keyboard
                    x: 464 * setup.unit
                    y: 132 * setup.unit
                    width: implicitWidth
                    height: implicitHeight
                    unit: setup.unit
                    keyFont: setup.rowFont
                    focusedKey: setup.focusId
                    full: setup.entryValue.length >= setup.entryLimit
                    onKeyClicked: {
                        setup.focusId = keyName;
                        setup.rememberKey(keyName);
                        setup.pressKey(keyName);
                    }
                    onTyped: setup.typeCharacter(value)
                }
            }

            // Short dialogs.
            Item {
                anchors.fill: parent
                visible: setup.isMessage

                AppIcon {
                    x: (parent.width - width) / 2
                    y: 48 * setup.unit
                    width: 88 * setup.unit
                    height: width
                    cornerRadius: 22 * setup.unit
                    visible: setup.message.appIcon !== undefined
                    source: setup.message.appIcon || ""
                }

                GlassControl {
                    x: (parent.width - width) / 2
                    y: 48 * setup.unit
                    width: 88 * setup.unit
                    height: width
                    unit: setup.unit
                    radius: 44
                    fill: "#24ffffff"
                    visible: setup.message.appIcon === undefined

                    Spinner {
                        anchors.centerIn: parent
                        size: 40 * setup.unit
                        lineWidth: 4 * setup.unit
                        running: setup.shown && setup.message.spinner === true
                        visible: running
                    }

                    Image {
                        anchors.centerIn: parent
                        visible: setup.message.icon !== undefined
                        source: setup.message.icon !== undefined ?
                                Qt.resolvedUrl("icons/" + setup.message.icon + ".png") : ""
                    }
                }

                Text {
                    id: messageTitle
                    x: 40 * setup.unit
                    y: 164 * setup.unit
                    width: parent.width - 80 * setup.unit
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: setup.message.title
                    color: "#ffffff"
                    font.family: setup.titleFont
                    font.pixelSize: 36 * setup.unit
                    font.letterSpacing: -0.72 * setup.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    id: messageText
                    x: (parent.width - width) / 2
                    y: messageTitle.y + messageTitle.height + 14 * setup.unit
                    width: 560 * setup.unit
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                    text: setup.message.text
                    color: "#c7ffffff"
                    font.family: setup.valueFont
                    font.pixelSize: 22 * setup.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Repeater {
                    model: setup.message.buttons

                    Item {
                        readonly property bool focused: setup.focusId === modelData.id
                        readonly property int count: setup.message.buttons.length
                        x: 40 * setup.unit
                        y: card.height - (40 + count * 72 + (count - 1) * 12 - index * 84) * setup.unit
                        width: 640 * setup.unit
                        height: 72 * setup.unit

                        GlassControl {
                            anchors.fill: parent
                            visible: !parent.focused
                            unit: setup.unit
                            radius: 36
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: modelData.danger ? (parent.focused ? GlassStyle.dangerFocused : GlassStyle.danger) :
                                                      (parent.focused ? GlassStyle.focusText : "#ffffff")
                            font.family: setup.rowFont
                            font.pixelSize: 22 * setup.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                setup.focusId = modelData.id;
                                setup.activate(modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }

    // Room the header text leaves for the keyboard switch.
    readonly property real switchRoom: isEntry ? modeSwitch.width + 20 * unit : 0
    readonly property string headerTitle: {
        if (screen === "tvName") return I18n.t("wifi", "title.tv_name");
        if (screen === "deviceName") return I18n.t("wifi", "title.device_name");
        if (screen === "profileName") return I18n.t("wifi", "title.profile_name");
        if (screen === "customName" || screen === "customSecurity") return I18n.t("wifi", "title.add_other");
        if (screen === "password" || screen === "customPassword") {
            return I18n.t("wifi", "title.password", { name: quoted(target ? target.name : "") });
        }
        return I18n.t("wifi", "title.setup");
    }
    readonly property string headerSubtitle: {
        if (screen === "tvName") return I18n.t("wifi", "subtitle.tv_name");
        if (screen === "deviceName") return I18n.t("wifi", "subtitle.device_name");
        if (screen === "profileName") return I18n.t("wifi", "subtitle.profile_name");
        if (screen === "customName") return I18n.t("wifi", "subtitle.custom_name");
        if (screen === "customSecurity") return I18n.t("wifi", "subtitle.custom_security");
        if (screen === "customPassword") return I18n.t("wifi", "subtitle.custom_password");
        if (screen === "password") return I18n.t("wifi", "subtitle.password");
        return I18n.t("wifi", "subtitle.list");
    }
    // ---- Audio-Guidance --------------------------------------------------
    // { layer, intro, subject, text, change } of what has the focus. The panel adds
    // its page, the guide reads it. Typed characters are not read back: the field
    // can hold a password.
    readonly property var characterNames: ({
        ".": I18n.t("wifi", "speech.character_period"),
        "-": I18n.t("wifi", "speech.character_hyphen"),
        "_": I18n.t("wifi", "speech.character_underscore"),
        "@": I18n.t("wifi", "speech.character_at"),
        "!": I18n.t("wifi", "speech.character_exclamation"),
        "\"": I18n.t("wifi", "speech.character_quotation"),
        "§": I18n.t("wifi", "speech.character_section"),
        "$": I18n.t("wifi", "speech.character_dollar"),
        "%": I18n.t("wifi", "speech.character_percent"),
        "&": I18n.t("wifi", "speech.character_ampersand"),
        "/": I18n.t("wifi", "speech.character_slash"),
        "(": I18n.t("wifi", "speech.character_parenthesis_open"),
        ")": I18n.t("wifi", "speech.character_parenthesis_close"),
        "=": I18n.t("wifi", "speech.character_equals"),
        "?": I18n.t("wifi", "speech.character_question"),
        "+": I18n.t("wifi", "speech.character_plus"),
        "*": I18n.t("wifi", "speech.character_asterisk"),
        "#": I18n.t("wifi", "speech.character_hash"),
        "'": I18n.t("wifi", "speech.character_apostrophe"),
        "~": I18n.t("wifi", "speech.character_tilde"),
        "<": I18n.t("wifi", "speech.character_less_than"),
        ">": I18n.t("wifi", "speech.character_greater_than"),
        "|": I18n.t("wifi", "speech.character_vertical_bar"),
        "\\": I18n.t("wifi", "speech.character_backslash"),
        "{": I18n.t("wifi", "speech.character_brace_open"),
        "}": I18n.t("wifi", "speech.character_brace_close"),
        "[": I18n.t("wifi", "speech.character_bracket_open"),
        "]": I18n.t("wifi", "speech.character_bracket_close"),
        "^": I18n.t("wifi", "speech.character_circumflex"),
        "°": I18n.t("wifi", "speech.character_degree"),
        ";": I18n.t("wifi", "speech.character_semicolon"),
        ":": I18n.t("wifi", "speech.character_colon"),
        ",": I18n.t("wifi", "speech.character_comma"),
        "€": I18n.t("wifi", "speech.character_euro"),
        "´": I18n.t("wifi", "speech.character_acute"),
        "`": I18n.t("wifi", "speech.character_grave"),
        "µ": I18n.t("wifi", "speech.character_micro"),
        "ß": I18n.t("wifi", "speech.character_sharp_s")
    })
    readonly property var speech: speechOf(screen, focusId, listState, networks, message, entryValue,
                                           entryErrorText, showPassword, customSecurity, keyboard.shifted,
                                           keyboard.symbols, keyboard.mode)

    function keySpeech(id) {
        if (id === "mode-qwertz" || id === "mode-t9") {
            var mode = I18n.t("keyboard", id === "mode-t9" ? "speech.mode_t9" : "speech.mode_qwertz");
            return keyboard.mode === id.substring(5) ? mode + ", " + I18n.t("wifi", "speech.selected") : mode;
        }
        if (id === "t-shift") id = "shift";
        else if (id === "t-delete") id = "delete";
        else if (id === "t-symbols") return I18n.t("wifi", "speech.symbols");
        if (keyboard.isT9Key(id)) {
            var digit = keyboard.t9Digit(id);
            if (digit === "0") return I18n.t("keyboard", "speech.digit_key", { digit: digit, letters: I18n.t("wifi", "speech.space") });
            var names = keyboard.t9Label(digit, keyboard.shifted).split("").map(function (value) {
                return characterNames[value] || value;
            });
            return I18n.t("keyboard", "speech.digit_key", { digit: digit, letters: names.join(" ") });
        }
        if (id === "shift") return keyboard.shifted ? I18n.t("wifi", "speech.shift_on") : I18n.t("wifi", "speech.shift_off");
        if (id === "symbols") return keyboard.symbols ? I18n.t("wifi", "speech.letters") : I18n.t("wifi", "speech.symbols");
        if (id === "space") return I18n.t("wifi", "speech.space");
        if (id === "delete") return I18n.t("wifi", "speech.delete");
        var parts = id.split("-");
        var value = keyboard.charAt(Number(parts[1]), Number(parts[2]));
        if (characterNames[value]) return characterNames[value];
        return value !== value.toLowerCase() ? I18n.t("wifi", "speech.capital_letter", { letter: value }) : value;
    }

    function listIntro(state, count) {
        var found = state === "searching" ? I18n.t("wifi", "speech.searching") :
                    (state === "empty" ? I18n.t("wifi", "state.empty") :
                     (state === "unavailable" ? I18n.t("wifi", "state.unavailable") :
                      (count === 1 ? I18n.t("wifi", "speech.found_one")
                                   : I18n.t("wifi", "speech.found_many", { count: count }))));
        return [headerTitle, headerSubtitle, found].join(". ");
    }

    function speechOf(screen, focusId, listState, networks, message, entryValue, entryError,
                      showPassword, customSecurity) {
        var focus = { layer: screen, intro: "", subject: focusId, text: "" };
        if (screen === "list") {
            focus.layer = "list:" + listState;
            focus.intro = listIntro(listState, networks.length);
            if (focusId.indexOf("row-") === 0) {
                var network = networks[Number(focusId.substring(4))];
                if (network) {
                    var signal = network.bars >= 3 ? I18n.t("wifi", "speech.signal_strong") :
                                 (network.bars === 2 ? I18n.t("wifi", "speech.signal_good") :
                                                       I18n.t("wifi", "speech.signal_weak"));
                    focus.subject = focusId + ":" + network.name + ":" + network.band;
                    focus.text = [network.name, detailOf(network),
                              network.connected ? I18n.t("wifi", "speech.connected") : signal]
                                 .join(", ");
                }
            } else if (focusId === "add") {
                focus.text = I18n.t("wifi", "button.add_other");
            } else if (focusId === "refresh") {
                focus.text = listState === "unavailable" ? I18n.t("global", "retry") : I18n.t("wifi", "button.search_again");
            }
        } else if (screen === "customSecurity") {
            focus.intro = headerTitle + ". " + headerSubtitle;
            var chosen = (focusId === "secOpen") === (customSecurity === "none") ?
                         ", " + I18n.t("wifi", "speech.selected") : "";
            if (focusId === "secSecured") {
                focus.text = I18n.t("wifi", "label.secured") + ", " + I18n.t("wifi", "hint.secured") + chosen;
            } else if (focusId === "secOpen") {
                focus.text = I18n.t("wifi", "label.open") + ", " + I18n.t("wifi", "hint.open") + chosen;
            } else {
                focus.text = I18n.t("global", "next");
            }
        } else if (isEntry) {
            var field = isOwnName ? I18n.t("wifi", "label.name") :
                        (screen === "customName" ? I18n.t("wifi", "label.network_name") : I18n.t("wifi", "label.password"));
            var current = isPasswordEntry || entryValue === "" ? "" : ", " + entryValue;
            focus.intro = headerTitle + ". " + headerSubtitle + ". " + field + current + ". " + entryHint;
            var said = "";
            if (focusId === "show") said = showPassword ? I18n.t("wifi", "speech.show_password_on")
                                                        : I18n.t("wifi", "speech.show_password_off");
            else if (focusId === "submit") said = isOwnName ? I18n.t("global", "save") :
                                                  (screen === "customName" ? I18n.t("global", "next") : I18n.t("wifi", "button.connect"));
            else said = keySpeech(focusId);
            // A typed character reads the key again as the confirmation.
            focus.subject = focusId + ":" + entryValue.length;
            focus.text = said + (entryError !== "" ? ", " + entryError : "");
            focus.change = entryError !== "" ? entryError : said;
        } else if (isMessage) {
            focus.layer = screen + ":" + (target ? target.name : "") + ":" + (dialog.action || "");
            focus.intro = message.title + ". " + message.text;
            var buttons = message.buttons;
            for (var i = 0; i < buttons.length; i++) {
                if (buttons[i].id === focusId) focus.text = buttons[i].label;
            }
        }
        return focus;
    }

    // entryError holds an error.* key, this is its text.
    readonly property string entryErrorText: entryError !== "" ? I18n.t("wifi", entryError) : ""
    readonly property string entryHint: {
        if (entryError !== "") return entryErrorText;
        if (screen === "tvName") return I18n.t("wifi", "hint.name_length", { count: typedValue.length });
        if (screen === "deviceName") return I18n.t("wifi", "hint.device_name_length", { count: typedValue.length });
        if (screen === "profileName") return I18n.t("wifi", "hint.profile_name_length", { count: typedValue.length });
        if (screen === "customName") return I18n.t("wifi", "hint.case_sensitive");
        return typedValue.length >= 8 ? I18n.t("wifi", "hint.password_count", { count: typedValue.length })
                                      : I18n.t("wifi", "hint.password_length");
    }
}
