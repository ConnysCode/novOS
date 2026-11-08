import QtQuick 2.12
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
        deleteConnectionHistory: true, deepColorChanged: true, toggleInputLock: true
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
    }

    function writeNovos(name, value) {
        if (name === "hideInputBanner") NovosSettings.hideInputBanner = value === true || value === "on";
        else if (name === "keyboardMode") GlassStyle.keyboardMode = String(value);
        readNovos();
        settings.changed();
    }

    Component.onCompleted: readNovos()

    // LG's own PIN prompt; the PIN itself never reaches this window.
    function askPin(kind, callback) {
        pinCallback = callback;
        luna("luna://com.webos.notification", "/createPincodePrompt", { promptType: kind });
    }

    function run(name, params, ctx) {
        if (name === "pinPrompt") {
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
