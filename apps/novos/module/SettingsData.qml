import QtQuick 2.12
import Qt.labs.folderlistmodel 2.11
import Qt.labs.settings 1.0
import WebOSServices 1.0
import "."
import "SourceList.js" as SourceList

// Lists, facts and actions of the settings modal that are more than one settings key.
// Every Luna call here is the one LG's own settings app makes (docs/lg-settings and the
// reports behind the catalogs). Rows name these by action; what is not here goes on to
// the panel, which owns the Wi-Fi flow, name entry and confirmations.
Item {
    id: tvData

    property var settings: null
    property var pinCallback: null

    readonly property var actions: ({
        pinPrompt: true, resetAdId: true, cmpSettings: true, resetHbbtvId: true,
        resetHbbtvConnections: true, autoTime: true, sleepTimer: true, setSleepTimer: true,
        timerTime: true, onTimerEnable: true, screenOff: true, resetSound: true, resetGameGenre: true,
        deleteConnectionHistory: true, deepColorChanged: true, toggleInputLock: true,
        checkUpdates: true, installUpdate: true, cancelUpdate: true, tonightUpdate: true, loadVersions: true,
        restoreVersion: true, openNetwork: true, blockUpdates: true, lgAutoUpdate: true,
        lgUpdateCheck: true, lgUpdateInstall: true, lgUpdateCancel: true
    })
    property var bluetoothFeatures: []

    function runs(name) {
        return actions[name] === true;
    }

    function luna(uri, method, params) {
        service.call(uri, method, JSON.stringify(params || {}));
    }

    // Facts the pages show, read once per opening of the modal.
    function request() {
        luna("luna://com.webos.applicationManager", "/listApps", {});
        luna("luna://com.webos.service.sm", "/deviceid/getIDs", { idType: ["IFAID"], origin: "read" });
        luna("luna://com.palm.systemservice", "/deviceInfo/query", { parameters: ["product_id", "serial_number"] });
        luna("luna://com.palm.systemservice", "/osInfo/query", { parameters: ["core_os_release"] });
        luna("luna://com.webos.service.attachedstoragemanager", "/getProperties", { deviceId: "INTERNAL_STORAGE" });
        luna("luna://com.webos.service.connectionmanager", "/getinfo", {});
        luna("luna://com.webos.service.wifi", "/getstatus", {});
        luna("luna://com.webos.service.voiceconductor", "/getSupportedLanguages",
             { languageCodes: [I18n.speechLocale], showAll: true });
        luna("luna://com.webos.service.config", "/getConfigs", { configNames: ["system.supportBluetoothFeatures"] });
        luna("luna://com.webos.service.sm/crypto", "/checkSeStore", { id: ["esn", "widevine"] });
        readVersion();
        readSleepTimer();
        readUpdates();
        readLgUpdates();
    }

    // The input of a page opened for one input, for example "hdmi2".
    function inputOf(ctx) {
        var items = ctx.list("inputs");
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === ctx.param) return items[i];
        }
        return null;
    }

    // As LG: reset only what belongs to the current sound mode.
    function resetSound(ctx) {
        var mode = ctx.val("sound.soundMode");
        var keys = ["audioBalance", "soundModeModified"];
        if (mode === "standard") keys = ["audioBalance", "userEqualizerValues", "soundModeModified"];
        else if (mode === "game") keys = ["audioBalance", "gameTVEqualizer", "gameTVEqualizer10band", "soundModeModified"];
        luna("luna://com.webos.settingsservice", "/resetSystemSettings", { category: "sound", keys: keys });
    }

    // The genre values of the Game Optimizer, those this TV shows and lets change.
    function resetGameGenre(ctx) {
        var keys = ["blackStabilizer", "whiteStabilizer"];
        var optional = ["gameAdjustContrast", "gameBlackLevel", "gameSharpness", "gameColorDepth"];
        for (var i = 0; i < optional.length; i++) {
            var desc = ctx.desc("other." + optional[i]);
            if (desc && desc.ui && desc.ui.visible !== false && desc.ui.active !== false) keys.push(optional[i]);
        }
        luna("luna://com.webos.settingsservice", "/resetSystemSettings", { category: "other", keys: keys });
    }

    // LG forgets phones and devices in this order, some only where the TV has the feature.
    function deleteConnectionHistory() {
        if (bluetoothFeatures.indexOf("remoteapp") >= 0) luna("luna://com.webos.service.asc", "/resetWoBLE", {});
        luna("luna://com.webos.service.miracast", "/deletePairedDeviceList", {});
        if (bluetoothFeatures.indexOf("btsoundsink") >= 0) {
            luna("luna://com.webos.service.btaudiosnk", "/removePairedDevices", {});
        }
        luna("luna://com.webos.service.ics/blaster", "/deleteIPConnectionHistory", {});
        luna("luna://com.webos.service.ftms", "/removeBlockedDeviceList", {});
    }

    // The release names its version beside the module folder (install/build-release.sh).
    // A preview has none and keeps the panel's own version.
    function readVersion() {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../VERSION"), false);
            request.send();
            var lines = String(request.responseText || "").split("\n");
            for (var i = 0; i < lines.length; i++) {
                var pair = lines[i].split("=");
                if (pair[0] === "version" && pair[1]) setState("novosVersion", pair[1]);
                if (pair[0] === "built" && pair[1]) {
                    var date = new Date(pair[1].replace(" ", "T"));
                    setState("novosBuilt", isNaN(date.getTime()) ? pair[1] :
                             date.toLocaleDateString(Qt.locale(I18n.qtLocale), Locale.LongFormat));
                }
            }
        } catch (error) {
        }
        if (!settings.store.state.novosVersion && settings.hostState.panelVersion) {
            setState("novosVersion", settings.hostState.panelVersion);
        }
    }

    function readSleepTimer() {
        luna("luna://com.webos.service.tvReservationAgent/timer/sleep", "/getRemainTime", {});
    }

    function setList(name, items) {
        settings.store.lists[name] = items;
        settings.changed();
    }

    function setState(name, value) {
        settings.store.state[name] = value;
        settings.changed();
    }

    // novOS's own values: the switches GlassStyle keeps in its ini file.
    function readNovos() {
        if (!settings.store.values.novos) settings.store.values.novos = {};
        settings.store.values.novos.hideInputBanner = NovosSettings.hideInputBanner;
        settings.store.values.novos.keyboardMode = GlassStyle.keyboardMode;
        settings.store.values.novos.shutdownScreen = NovosSettings.shutdownScreen;
        settings.store.values.novos.updateChannel = settings.store.state.updateChannel || "stable";
        settings.store.values.novos.betaChannel = settings.store.state.updateChannel === "beta";
        settings.store.values.novos.autoUpdate = settings.store.state.autoUpdate === true;
        settings.store.values.novos.blockUpdates = settings.store.state.blockUpdates === true ? "on" : "off";
    }

    function writeNovos(name, value) {
        if (name === "hideInputBanner") NovosSettings.hideInputBanner = value === true || value === "on";
        else if (name === "keyboardMode") GlassStyle.keyboardMode = String(value);
        else if (name === "shutdownScreen") NovosSettings.shutdownScreen = String(value);
        else if (name === "updateChannel" || name === "betaChannel") {
            // The updater stores it; a check of the new channel follows its answer.
            var channel = name === "betaChannel" ? (value === true || value === "on" ? "beta" : "stable") : String(value);
            settings.store.state.updateChannel = channel;
            sendUpdate("channel", { source: channel });
            checkAfterChannel = true;
        } else if (name === "autoUpdate") {
            // Kept by the updater in state/auto-update; the supervisor installs at night.
            settings.store.state.autoUpdate = value === true || value === "on";
            sendUpdate("settings", { autoUpdate: settings.store.state.autoUpdate ? "on" : "off" });
        }
        readNovos();
        settings.changed();
    }

    Component.onCompleted: readNovos()

    // LG's own PIN prompt; the PIN itself never reaches this window.
    function askPin(kind, callback) {
        pinCallback = callback;
        luna("luna://com.webos.notification", "/createPincodePrompt", { promptType: kind });
    }

    // ---- Software-Update ---------------------------------------------------------------
    // Commands go to the updater through /tmp/novos-update (SetupBridge); novOS' supervisor
    // starts the newest signed setup release for them. Its last answer of the channel stays
    // in state/last-check.json, so the page knows it after a restart too.

    readonly property string updateFolder: "/tmp/novos-update"
    readonly property string novosState: "/var/lib/novos/state"
    readonly property int updateTimeout: 60000      // no answer: no updater on this TV
    property string sentCommand: ""
    property bool checkAfterChannel: false
    property bool updateLost: false

    SetupBridge {
        id: updates
        folder: tvData.updateFolder
        active: !!tvData.settings && tvData.settings.active
        onInfoChanged: tvData.applyUpdates()
    }

    // While the modal is open its update page shows the progress; the supervisor shows the
    // pill over the picture (Update-3) only once the modal is closed.
    Settings {
        fileName: tvData.updateFolder + "/ui.ini"
        property bool settingsOpen: !!tvData.settings && tvData.settings.active
    }

    Timer {
        id: updateWatch
        interval: tvData.updateTimeout
        onTriggered: {
            var info = updates.info || {};
            if (info.id === updates.sentId && (info.phase === "done" || info.phase === "error")) return;
            tvData.updateLost = true;
            tvData.applyUpdates();
        }
    }

    function sendUpdate(command, values) {
        sentCommand = command;
        updateLost = false;
        updates.send(command, values || {});
        updateWatch.restart();
        applyUpdates();
    }

    function readFile(path) {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", "file://" + path, false);
            request.send();
            return String(request.responseText || "");
        } catch (error) {
            return "";
        }
    }

    function readUpdates() {
        var state = settings.store.state;
        var channel = readFile(novosState + "/channel").trim();
        if (channel === "stable" || channel === "beta") state.updateChannel = channel;
        state.autoUpdate = readFile(novosState + "/auto-update").trim() === "on";
        state.updateTonight = readFile(novosState + "/update-tonight").trim();
        try {
            var found = JSON.parse(readFile(novosState + "/last-check.json") || "null");
            if (found && (!state.updateCheck || (found.checked || 0) >= (state.updateCheck.checked || 0))) {
                state.updateCheck = found;
            }
        } catch (error) {
        }
        // The installed release's own notes, signed in its manifest beside the module folder.
        try {
            var request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../manifest.json"), false);
            request.send();
            var manifest = JSON.parse(String(request.responseText || "null"));
            state.notesInstalled = manifest && manifest.notes ? localNotes(manifest.notes) : null;
        } catch (error) {
            state.notesInstalled = null;
        }
        applyUpdates();
    }

    // ---- Release notes and versions in the TV's language ----------------------------------

    // A text of the notes in the menu's language, else English, else what there is.
    function localText(texts) {
        if (!texts || typeof texts !== "object") return String(texts || "");
        if (texts[I18n.language]) return texts[I18n.language];
        if (texts.en) return texts.en;
        for (var key in texts) return texts[key];
        return "";
    }

    // "2026-11-09" as the design writes it: "9. November 2026".
    function localDate(text) {
        var parts = String(text || "").split("T")[0].split("-");
        if (parts.length !== 3) return "";
        var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        return date.toLocaleDateString(Qt.locale(I18n.qtLocale), settings.settingsStore.text("info", "format.date"));
    }

    function localNotes(notes) {
        var items = [];
        for (var i = 0; i < (notes.items || []).length; i++) {
            items.push({ title: localText(notes.items[i].title), text: localText(notes.items[i].text) });
        }
        return { date: localDate(notes.date), items: items };
    }

    // 1.0.0-beta.2 < 1.0.0-beta.10 < 1.0.0-rc.1 < 1.0.0 < 1.0.1, as release.py orders them.
    function compareVersions(a, b) {
        var pattern = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$/;
        var x = pattern.exec(a || "");
        var y = pattern.exec(b || "");
        if (!x || !y) return x ? 1 : (y ? -1 : 0);
        for (var i = 1; i <= 3; i++) {
            if (Number(x[i]) !== Number(y[i])) return Number(x[i]) < Number(y[i]) ? -1 : 1;
        }
        if (!x[4] || !y[4]) return x[4] ? -1 : (y[4] ? 1 : 0);
        var p = x[4].split(".");
        var q = y[4].split(".");
        for (var j = 0; j < Math.max(p.length, q.length); j++) {
            if (p[j] === undefined || q[j] === undefined) return p[j] === undefined ? -1 : 1;
            var numeric = /^\d+$/.test(p[j]) && /^\d+$/.test(q[j]);
            if (numeric && Number(p[j]) !== Number(q[j])) return Number(p[j]) < Number(q[j]) ? -1 : 1;
            if (!numeric && p[j] !== q[j]) return p[j] < q[j] ? -1 : 1;
        }
        return 0;
    }

    // Frühere Versionen: every published version, and a kept release that was never published.
    function applyVersions(result) {
        var state = settings.store.state;
        var installed = result.installed || state.novosVersion || "";
        var items = [];
        var listed = {};
        var published = result.versions || [];
        for (var i = 0; i < published.length; i++) {
            var entry = published[i];
            listed[entry.version] = true;
            var notes = localNotes({ date: entry.date || entry.published, items: entry.items || [] });
            var topics = localText(entry.topics);
            items.push({ id: entry.version, title: "novOS " + entry.version,
                         subtitle: notes.date + (topics ? " · " + topics : ""),
                         value: entry.version === installed ? settings.settingsStore.text("info", "value.installed") : "",
                         date: notes.date, items: notes.items, manifest: entry.manifest || "",
                         size: entry.size > 0 ? Math.max(1, Math.round(entry.size / 1000000)) : 0,
                         newer: compareVersions(entry.version, installed) > 0 });
        }
        var kept = result.kept || [];
        for (var k = 0; k < kept.length; k++) {
            if (listed[kept[k]]) continue;
            items.push({ id: kept[k], title: "novOS " + kept[k], subtitle: "", value: "", date: "", items: [],
                         manifest: "", size: 0, newer: false });
        }
        state.versionsKept = kept;
        setList("novosVersions", items);
    }

    function checkedText(found) {
        if (!found || !found.checked) return "";
        var date = new Date(found.checked * 1000);
        return date.toLocaleString(Qt.locale(I18n.qtLocale), Locale.ShortFormat);
    }

    function applyUpdates() {
        var state = settings.store.state;
        var info = updates.info || {};
        // From info itself: in onInfoChanged the bridge's bindings may not have followed yet.
        var mine = updates.sentId !== "" && info.id === updates.sentId;
        var answered = mine && (info.phase === "done" || info.phase === "error");
        if (mine) updateLost = false;
        if (info.channel === "stable" || info.channel === "beta") state.updateChannel = info.channel;
        var result = info.result || null;
        if (result && result.check && (!state.updateCheck || (result.check.checked || 0) >= (state.updateCheck.checked || 0))) {
            state.updateCheck = result.check;
        }
        if (result && result.check) {
            state.notesAvailable = result.check.notes ? localNotes(result.check.notes) : null;
        }
        if (result && result.downloaded && state.updateCheck && state.updateCheck.available === result.downloaded) {
            var ready = JSON.parse(JSON.stringify(state.updateCheck));
            ready.downloaded = true;
            state.updateCheck = ready;
        }
        if (result && result.tonight !== undefined) state.updateTonight = result.tonight || "";
        if (info.choices && typeof info.choices.autoUpdate === "boolean") state.autoUpdate = info.choices.autoUpdate;
        if (mine && info.command === "versions") {
            if (info.phase === "done" && result && result.versions) applyVersions(result);
            state.versionsState = info.phase === "error" ? "error" : (info.phase === "done" ? "done" : "loading");
        }
        // A command that only reads (the versions) runs beside the card, not as its task.
        var reading = sentCommand === "versions";
        var waiting = updates.sentId !== "" && !answered && !updateLost;
        state.updateBusy = (waiting && !reading) || (info.busy === true && info.command !== "versions");
        state.updateCommand = waiting && !reading ? sentCommand : (info.busy === true ? info.command : "");
        state.updateStage = info.busy === true ? info.stage || "" : "";
        state.updatePercent = info.busy === true ? info.percent || 0 : 0;
        state.updateBytes = info.busy === true ? info.bytes || 0 : 0;
        state.updateTotal = info.busy === true ? info.total || 0 : 0;
        state.updateEta = info.busy === true ? info.eta : null;
        if (updateLost && reading) state.versionsState = "error";
        // Errors of the own last command; a failed check at night says nothing here.
        var error = updateLost ? "no updater" : (mine && info.phase === "error" ? info.error || "?" : "");
        var ownCommand = mine ? info.command : sentCommand;
        // The block of LG's updates goes through the same updater, but is no novOS update.
        state.blockBusy = waiting && sentCommand === "settings";
        if (ownCommand === "settings") {
            state.blockError = error;
            if (answered && info.choices && typeof info.choices.blockUpdates === "boolean") {
                state.blockUpdates = info.choices.blockUpdates;
                state.blockedNow = info.choices.blockedNow === true;
            }
        } else if (ownCommand !== "versions" && ownCommand !== "cancel") {
            state.updateError = error;
            state.updateErrorKind = updateLost ? "failed" : (mine ? info.errorKind || "" : "");
        }
        state.updateChecked = checkedText(state.updateCheck);
        if (answered && checkAfterChannel) {
            checkAfterChannel = false;
            if (info.phase === "done") sendUpdate("check");
        }
        readNovos();
        settings.changed();
    }

    // ---- LG's system updates ----------------------------------------------------------
    // The block is the Homebrew Channel's: its flag makes its startup.sh point LG's update
    // servers to the TV itself, from the next restart on. The flag file is watched here (the
    // Homebrew Channel's service refuses this window: "Not permitted to send"), /etc/hosts
    // says whether the block holds in this boot. novos-setupd writes it (command
    // "settings") and notes once what was there before novOS; the uninstall restores that.
    // Searching, installing and cancelling are the calls of LG's Support › Software-Update
    // (com.webos.service.update); the system page offers them while the block is off.

    readonly property int lgCheckTimeout: 90000
    property bool lgSubscribed: false
    property bool lgProgressSubscribed: false

    Timer {
        id: lgCheckWatch
        interval: tvData.lgCheckTimeout
        onTriggered: {
            if (!tvData.settings.store.state.lgChecking) return;
            tvData.setState("lgChecking", false);
            tvData.setState("lgCheck", { returnValue: false });
        }
    }

    FolderListModel {
        id: blockFlag
        folder: "file:///var/luna/preferences"
        nameFilters: ["webosbrew_block_updates"]
        showDirs: false
        showHidden: true
        onStatusChanged: tvData.readBlockFlag()
        onCountChanged: tvData.readBlockFlag()
    }

    function readBlockFlag() {
        if (!settings || blockFlag.status !== FolderListModel.Ready) return;
        // While the updater writes the flag, the page keeps what was chosen.
        if (settings.store.state.blockBusy === true) return;
        setState("blockUpdates", blockFlag.count > 0);
        readNovos();
    }

    function readLgUpdates() {
        readBlockFlag();
        setState("blockedNow", readFile("/etc/hosts").indexOf("snu.lge.com") >= 0);
        luna("luna://com.webos.settingsservice", "/getSystemSettings", { keys: ["eulaStatus"] });
        luna("luna://com.webos.service.update", "/getVersionChecked", {});
        if (!lgSubscribed) {
            lgSubscribed = true;
            luna("luna://com.webos.service.update", "/getStatus", { subscribe: true });
        }
    }

    // A risky step asks first; the panel's dialog runs the action again with confirmed.
    function ask(params, ctx, action, name, danger, then) {
        if (params.confirmed === true) {
            then();
            return;
        }
        var again = { confirmed: true };
        for (var key in params) again[key] = params[key];
        settings.hostAction("confirm", { action: action, params: again, danger: danger,
                                         title: ctx.t("confirm." + name + "_title"),
                                         text: ctx.t("confirm." + name + "_text"),
                                         confirm: ctx.t("confirm." + name + "_button") });
    }

    function setBlock(params, ctx) {
        var state = settings.store.state;
        if (state.blockBusy || state.updateBusy) return;
        var apply = function () {
            setState("blockUpdates", params.value === "on");     // shown at once, the answer confirms
            setState("blockError", "");
            sendUpdate("settings", { blockUpdates: params.value === "on" ? "on" : "off" });
        };
        if (params.value === "on") apply();
        else ask(params, ctx, "blockUpdates", "allow_updates", true, apply);
    }

    // As LG: without the general terms the switch opens them first and writes nothing.
    function setLgAutoUpdate(params, ctx) {
        var write = function () {
            if (params.value === "on" && settings.store.state.generalTermsAllowed === false) {
                settings.launchApp({ id: "com.webos.app.firstuse-overlay",
                                     params: { target: "eula", context: "generalTerms" } });
                return;
            }
            settings.commit({ category: "support", settings: { automaticUpdate: params.value } }, null, ctx);
            settings.flushWrite();
        };
        if (params.value === "on") ask(params, ctx, "lgAutoUpdate", "lg_auto_update", true, write);
        else write();
    }

    function checkLg() {
        if (settings.store.state.lgChecking) return;
        setState("lgChecking", true);
        setState("lgCheck", null);
        luna("luna://com.webos.service.update", "/checkUpdate", { manual: true });
        lgCheckWatch.restart();
    }

    // LG's sizes in MB: below one MB counts as one.
    function megabytes(bytes) {
        var value = Number(bytes || 0);
        return value > 1048576 ? Math.floor(value / 1048576) : (value === 0 ? 0 : 1);
    }

    function applyLgStatus(response) {
        var type = response.updateType || "";
        var size = type === "nsu" ? response.nsuImageSize : type === "ssu" ? response.ssuImageSize :
                   type === "usb" ? response.usbImageSize : 0;
        setState("lgStatus", { status: response.status || "", updateType: type, size: megabytes(size),
                               platformUpgrade: response.platformUpgrade === true });
        var status = response.status;
        if (!lgProgressSubscribed && (status === "in progress" || status === "ExternalChipInstall" ||
                                      status === "completed")) {
            lgProgressSubscribed = true;
            luna("luna://com.webos.service.update", "/getProgress", { subscribe: true });
        }
    }

    function run(name, params, ctx) {
        var updateState = settings.store.state;
        if (name === "checkUpdates") {
            sendUpdate("check");
        } else if (name === "installUpdate") {
            // Loads first, the settings may close meanwhile; once loaded the same button installs.
            if (updateState.updateBusy) return;
            var offer = updateState.updateCheck || {};
            updateState.updateTarget = offer.available || "";
            sendUpdate(offer.downloaded ? "update" : "download");
        } else if (name === "cancelUpdate") {
            sendUpdate("cancel");
        } else if (name === "tonightUpdate") {
            sendUpdate("tonight", { version: params.version || "" });
        } else if (name === "loadVersions") {
            if (updateState.updateBusy) return;
            updateState.versionsState = "loading";
            setList("novosVersions", []);
            sendUpdate("versions");
        } else if (name === "restoreVersion") {
            if (updateState.updateBusy) return;
            updateState.updateTarget = params.version || "";
            sendUpdate("restore", { version: params.version || "", manifest: params.manifest || "" });
        } else if (name === "openNetwork") {
            settings.open("network", "");
        } else if (name === "blockUpdates") {
            setBlock(params, ctx);
        } else if (name === "lgAutoUpdate") {
            setLgAutoUpdate(params, ctx);
        } else if (name === "lgUpdateCheck") {
            checkLg();
        } else if (name === "lgUpdateInstall") {
            ask(params, ctx, "lgUpdateInstall", "lg_install", true, function () {
                luna("luna://com.webos.service.update", "/startUpdate", { confirm: true });
            });
        } else if (name === "lgUpdateCancel") {
            ask(params, ctx, "lgUpdateCancel", "lg_cancel", false, function () {
                luna("luna://com.webos.service.update", "/cancelUpdate", {});
            });
        } else if (name === "pinPrompt") {
            luna("luna://com.webos.notification", "/createPincodePrompt", { promptType: "set_match" });
        } else if (name === "resetAdId") {
            luna("luna://com.webos.service.admanager", "/resetIFA", {});
        } else if (name === "cmpSettings") {
            luna("luna://com.webos.service.admanager", "/launchCMPApp", { forceStatus: true });
            settings.hostAction("closePanel", {});
        } else if (name === "resetHbbtvId") {
            luna("luna://com.webos.service.wampluggable.hbbtv", "/resetDeviceId", {});
        } else if (name === "resetHbbtvConnections") {
            luna("luna://com.webos.service.wampluggable.hbbtv", "/resetDialConnection", {});
        } else if (name === "autoTime") {
            // LG writes time.autoClock and the system preference together.
            luna("luna://com.palm.systemservice", "/setPreferences", { useNetworkTime: params.value === "on" });
        } else if (name === "sleepTimer") {
            settings.pushChoice({ id: "sleepTimer", title: "row.sleep_timer", options: sleepOptions });
        } else if (name === "setSleepTimer") {
            luna("luna://com.webos.service.tvReservationAgent/timer/sleep", "/add",
                 { sleepTimeMinute: params.minutes });
            setState("sleepMinutes", params.minutes);
            settings.back();
        } else if (name === "timerTime") {
            settings.pushPage(timePage(params.timer));
        } else if (name === "onTimerEnable") {
            var request = { onTimerEnable: params.value };
            // Without a channel LG would switch the timer off again; Home keeps it.
            if (params.value === "on" && ctx.val("time.onTimerAppId") === "com.webos.app.livetv") {
                request.onTimerAppId = "com.webos.app.home";
            }
            settings.commit({ category: "time", settings: request }, null, ctx);
            settings.flushWrite();
        } else if (name === "resetSound") {
            resetSound(ctx);
        } else if (name === "resetGameGenre") {
            resetGameGenre(ctx);
        } else if (name === "deleteConnectionHistory") {
            deleteConnectionHistory();
        } else if (name === "deepColorChanged") {
            // Without Deep Color the Game Optimizer cannot run on that input, so LG switches it off.
            var running = String(ctx.state.foreground || "").replace("com.webos.app.", "");
            var modes = ctx.val("other.gameMode") || {};
            if (params.value === "off" && modes[running] === "on") {
                var next = {};
                for (var input in modes) next[input] = modes[input];
                next[running] = "off";
                settings.commit({ category: "other", settings: { gameMode: next } }, null, ctx);
                settings.flushWrite();
            }
        } else if (name === "toggleInputLock") {
            var item = inputOf(ctx);
            if (item && item.lockBit !== undefined) {
                var mask = Number(ctx.val("lock.inputBlock") || 0) ^ (1 << item.lockBit);
                settings.commit({ category: "lock", settings: { inputBlock: mask } }, null, ctx);
                settings.flushWrite();
            }
        } else if (name === "screenOff") {
            luna("luna://com.webos.service.tvpower/power", "/turnOffScreen", {});
            settings.hostAction("closePanel", {});
        }
    }

    function sleepOptions(ctx) {
        var current = ctx.state.sleepMinutes || 0;
        var options = [];
        // The list and the names come from the shared store, as in the quick panel.
        var choices = settings.settingsStore.sleepChoices;
        for (var i = 0; i < choices.length; i++) {
            var minutes = choices[i];
            options.push({ id: String(minutes), label: settings.settingsStore.minutesLabel(minutes),
                           selected: minutes === current, action: "setSleepTimer", params: { minutes: minutes } });
        }
        return options;
    }

    // Hour and minute of the on or off timer, as two sliders over LG's keys. Setting a
    // time switches the timer on, the way LG's time picker does.
    function timePage(timer) {
        var prefix = timer === "off" ? "time.offTimer" : "time.onTimer";
        var enable = timer === "off" ? { offTimerEnable: "on" } : { onTimerEnable: "on" };
        var also = function (ctx) {
            var extra = {};
            for (var key in enable) extra[key] = enable[key];
            if (timer !== "off" && ctx.val("time.onTimerAppId") === "com.webos.app.livetv") {
                extra.onTimerAppId = "com.webos.app.home";
            }
            return extra;
        };
        return {
            id: timer + "TimerTime",
            title: "row.timer_time",
            sections: [{ rows: [
                { id: "hour", type: "slider", key: prefix + "Hour", title: "row.hour", min: 0, max: 23,
                  alsoWrite: also, descOptional: true },
                { id: "minute", type: "slider", key: prefix + "Minute", title: "row.minute", min: 0, max: 59,
                  alsoWrite: also, descOptional: true }
            ] }]
        };
    }

    // HDMI inputs as LG's input list knows them, with the names the source picker shows.
    function applyInputs(response) {
        var devices = response.devices || [];
        var items = [];
        var bit = 0;   // LG's bit in lock.inputBlock: the place among the inputs without MVPD entries
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i];
            var lockBit = String(device.id || "").indexOf("MVPD") >= 0 ? undefined : bit++;
            if (String(device.id || "").indexOf("HDMI") !== 0) continue;
            var number = Number(String(device.id).replace(/[^0-9]/g, ""));
            items.push({ id: device.id, number: number, port: number, appId: device.appId, lockBit: lockBit,
                         title: SourceList.deviceName(device) || device.label,
                         subtitle: device.hdmiPlugIn ? device.label : "",
                         connected: device.hdmiPlugIn === true, device: device });
        }
        setList("inputs", items);
        setState("hasArc", response.arcDevice === true);
    }

    function activateItem(row, ctx) {
        var item = row.item;
        if (item && item.app) settings.launchApp(item.app);
        else if (item && item.action) settings.runAction(item.action, item.params || {});
    }

    function applyApps(apps) {
        var ids = [];
        for (var i = 0; i < apps.length; i++) ids.push(apps[i].id);
        settings.store.apps = ids;
        settings.changed();
    }

    Service {
        id: service
        appId: "com.webos.app.quicksettings"
        onError: {
            if (method === "/checkUpdate") {
                lgCheckWatch.stop();
                tvData.setState("lgChecking", false);
                tvData.setState("lgCheck", { returnValue: false });
            }
        }
        onResponse: {
            var response = JSON.parse(payload);
            if (method === "/getConfigs") {
                var features = (response.configs || {})["system.supportBluetoothFeatures"];
                tvData.bluetoothFeatures = Array.isArray(features) ? features : [];
            } else if (method === "/listApps") {
                tvData.applyApps(response.apps || []);
            } else if (method === "/deviceid/getIDs") {
                var ids = response.idList || [];
                for (var i = 0; i < ids.length; i++) {
                    if (ids[i].idType === "IFAID") tvData.setState("adId", ids[i].idValue || "");
                }
            } else if (method === "/deviceInfo/query") {
                tvData.setState("modelCode", response.product_id || "");
                // Only shown on screen, never stored or logged.
                tvData.setState("serialNumber", response.serial_number || "");
            } else if (method === "/osInfo/query") {
                tvData.setState("webOS", response.core_os_release || "");
            } else if (method === "/getProperties") {
                var info = response.deviceInfo || response;
                if (info.freeSpace !== undefined) tvData.setState("storageFree", Number(info.freeSpace));
                if (info.totalSpace !== undefined) tvData.setState("storageTotal", Number(info.totalSpace));
            } else if (method === "/getinfo") {
                var wired = response.wiredInfo || {};
                var wifi = response.wifiInfo || {};
                tvData.setState("wiredMac", wired.macAddress || "");
                tvData.setState("wifiMac", wifi.macAddress || "");
            } else if (method === "/getstatus") {
                var network = response.networkInfo;
                tvData.setState("wifiProfile", network ? (network.profileId || 0) : 0);
            } else if (method === "/getSupportedLanguages") {
                tvData.setState("voiceAvailable", tvData.voiceSupported(response));
            } else if (method === "/getRemainTime") {
                tvData.setState("sleepMinutes", Math.ceil((response.sleepTimeSecond || 0) / 60));
            } else if (method === "/checkSeStore") {
                // Only shown on screen, never stored or logged.
                var keys = response.keyStatusList || [];
                for (var k = 0; k < keys.length; k++) {
                    if (keys[k].isOk && keys[k].identifier !== undefined) tvData.setState(keys[k].id, keys[k].identifier);
                }
            } else if (method === "/createPincodePrompt") {
                if (response.matched === true && tvData.pinCallback) {
                    var callback = tvData.pinCallback;
                    tvData.pinCallback = null;
                    callback();
                }
            } else if (method === "/getSystemSettings") {
                var eula = (response.settings || {}).eulaStatus;
                if (eula && typeof eula.generalTermsAllowed === "boolean") {
                    tvData.setState("generalTermsAllowed", eula.generalTermsAllowed);
                }
            } else if (method === "/getVersionChecked") {
                tvData.setState("lgVersionChecked", response.returnValue === true ? response : null);
            } else if (method === "/checkUpdate") {
                lgCheckWatch.stop();
                tvData.setState("lgChecking", false);
                tvData.setState("lgCheck", response);
            } else if (method === "/getStatus") {
                if (response.status !== undefined) tvData.applyLgStatus(response);
            } else if (method === "/getProgress") {
                if (typeof response.progress === "number") tvData.setState("lgProgress", response.progress);
            } else if (method === "/resetIFA") {
                tvData.luna("luna://com.webos.service.sm", "/deviceid/getIDs", { idType: ["IFAID"], origin: "read" });
            }
        }
    }

    // LG shows voice settings only where an engine serves at least one language.
    // Answer: { voiceEngines: { nlp: { thinQtv: { "de-DE": "de-DE" | "notSupported" } } } }.
    function voiceSupported(response) {
        var nlp = response.voiceEngines && response.voiceEngines.nlp ? response.voiceEngines.nlp : {};
        var engines = ["thinQtv", "dangbeiVoice"];
        for (var i = 0; i < engines.length; i++) {
            var languages = nlp[engines[i]] || {};
            for (var code in languages) {
                if (languages[code] !== "notSupported") return true;
            }
        }
        return false;
    }
}
