.pragma library
.import "DeviceList.js" as DeviceList

// Area 03 "Quellen & Geräte". Everything about one input sits on its page (K3-Struktur-HDMI);
// LG spreads it over Game Optimizer, External Devices › HDMI Settings, Sound › HDMI Input
// Audio Format and Safety › Input Locks. Keys and calls follow LG's settings app, see
// docs/lg-settings/alle-einstellungen.md, sections "Externe Geräte" and "Sender".
//
// An input's page is opened from the host list "inputs" (eim/getAllInputStatus); ctx.param
// is the entry's id ("HDMI_1"), the entry brings port and appId.

function truthy(value) {
    return !(value === "false" || value === false || value === 0 || value === null ||
             value === undefined || value === "");
}

function profileHas(ctx, name) {
    var list = ctx.cfg("profile.list");
    return list !== undefined && list !== null && list.indexOf(name) >= 0;
}

function bluetoothFeature(ctx, name) {
    var list = ctx.cfg("system.supportBluetoothFeatures");
    return list !== undefined && list !== null && list.indexOf(name) >= 0;
}

function hasTuner(ctx) {
    return !profileHas(ctx, "tunerless");
}

function inputItem(ctx) {
    var items = ctx.list("inputs");
    for (var i = 0; i < items.length; i++) {
        if (items[i].id === ctx.param) return items[i];
    }
    return null;
}

function itemPort(ctx) {
    var item = inputItem(ctx);
    return item ? item.port : 0;
}

// "hdmi1": how LG names an input in other.gameMode and in the dimension gameInput.
function itemInput(ctx) {
    var port = itemPort(ctx);
    return port ? "hdmi" + port : "";
}

function runningInput(ctx) {
    if (ctx.state.input) return ctx.state.input;
    var match = /^com\.webos\.app\.hdmi(\d+)$/.exec(ctx.state.foreground || "");
    return match ? "hdmi" + match[1] : "";
}

// LG reads and writes Deep Color only for the running input (dimension gameInput).
function notRunning(ctx) {
    return runningInput(ctx) !== itemInput(ctx);
}

// lock.inputBlock has one bit per entry of LG's input list without MVPD entries.
function inputLocked(ctx) {
    var item = inputItem(ctx);
    var mask = Number(ctx.val("lock.inputBlock") || 0);
    return item && item.lockBit !== undefined ? (mask & (1 << item.lockBit)) !== 0 : false;
}

// Gamepads, keyboards and mice over Bluetooth (QG-1) in the shared device list (TON-A). The
// host is BluetoothDevices.qml (bthidmanager).
var inputDevices = {
    source: "bluetoothInput", found: "bluetoothInputFound", page: "bluetoothInputDevice",
    connect: "btInputConnect", disconnect: "btInputDisconnect", remove: "btInputRemove", search: "btInputSearch",
    searching: "btInputSearching", ready: "btInputReady",
    removeText: function (ctx) {
        var item = DeviceList.item(ctx, "bluetoothInput", ctx.param);
        var kind = item && ["gamepad", "keyboard", "mouse"].indexOf(item.kind) >= 0 ? item.kind : "device";
        return "confirm.remove_input_" + kind;
    }
};

function inputDevice(ctx) {
    return DeviceList.item(ctx, "bluetoothInput", ctx.param);
}

function hasInputDevices(ctx) {
    return bluetoothFeature(ctx, "gamepad") || bluetoothFeature(ctx, "wirelesskeyboard");
}

// Above the list: connected devices per kind and LG's limit (K3-Einst-BT-Eingabegeraete-02).
function inputCounters(ctx) {
    var counts = ctx.state.btInputCounts || { gamepad: 0, keyboard: 0, mouse: 0 };
    var kinds = ["gamepad", "keyboard", "mouse"];
    var counters = [];
    for (var i = 0; i < kinds.length; i++) {
        counters.push({ icon: "counter-" + kinds[i], count: counts[kinds[i]] || 0, label: ctx.t("counter." + kinds[i]) });
    }
    return { counters: counters, text: ctx.t("block.input_limit") };
}

var ports = [1, 2, 3, 4];

function portKeys(prefix) {
    var keys = [];
    for (var i = 0; i < ports.length; i++) keys.push(prefix + ports[i]);
    return keys;
}

var area = {
    id: "sources",
    icon: "sources",
    title: "area.sources",
    configs: ["profile.list", "system.supportBluetoothFeatures", "tv.conti.supportInputBlock",
              "tv.model.supportCiAp", "tv.hw.supportSatellite", "tv.model.sysType"],
    watch: ["lock.inputBlock", "lock.parentalControl", "other.gameMode"]
           .concat(portKeys("other.444BypassHDMI"), portKeys("sound.inputAudioFormatHDMI")),

    page: {
        id: "sources",
        title: "area.sources",
        sections: [
            { title: "section.input", rows: [
                { id: "inputs", type: "list", source: "inputs", page: "input",
                  requires: function (ctx) { return profileHas(ctx, "hdmi"); } }
            ] },
            { title: "section.live_tv", rows: [
                { id: "channelScan", type: "lgApp", title: "row.channel_scan", search: "search.channel_scan",
                  app: { id: "com.webos.app.channelsetting", params: {} }, requires: hasTuner },
                { id: "channelManager", type: "lgApp", title: "row.channel_manager",
                  search: "search.channel_manager",
                  app: { id: "com.webos.app.channeledit", params: {} }, requires: hasTuner },
                // LG only offers copying for satellite DVB models.
                { id: "copyChannels", type: "lgApp", title: "row.copy_channels",
                  app: { id: "com.palm.app.settings", params: { target: "CopyChannels" } },
                  requires: function (ctx) {
                      return hasTuner(ctx) && truthy(ctx.cfg("tv.hw.supportSatellite")) &&
                             ctx.cfg("tv.model.sysType") === "DVB";
                  } },
                { id: "ciInfo", type: "lgApp", title: "row.ci_info",
                  app: { id: "com.webos.app.livetv", params: { id: "startCiInfoMenu" } },
                  requires: function (ctx) { return hasTuner(ctx) && truthy(ctx.cfg("tv.model.supportCiAp")); } },
                // LG writes "onByUser"/"offByUser" and reads "on" as on as well.
                { id: "hbbtv", type: "toggle", key: "option.hbbTV", title: "row.hbbtv_start",
                  subtitle: "detail.hbbtv_start", on: "onByUser", off: "offByUser",
                  onValues: ["on", "onByUser"], requires: hasTuner },
                { id: "multiChannelAudio", type: "toggle", key: "option.multiChannelAudio",
                  title: "row.multi_channel_audio", requires: hasTuner }
            ] },
            { title: "section.cec", rows: [
                { id: "simplink", type: "toggle", key: "other.simplinkEnable", title: "row.simplink",
                  subtitle: "detail.simplink", search: "search.simplink" },
                { id: "autoPower", type: "toggle", key: "other.simplinkAutoPowerOn", title: "row.auto_power",
                  subtitle: "detail.auto_power",
                  disabled: [{ when: function (ctx) { return ctx.val("other.simplinkEnable") !== "on"; },
                               reason: "reason.simplink_off" }] }
            ] },
            { title: "section.devices", rows: [
                { id: "bluetoothControllers", type: "page", page: "bluetoothInput", title: "row.bluetooth_controllers",
                  subtitle: "detail.bluetooth_controllers", search: "search.bluetooth_controllers",
                  value: function (ctx) {
                      var count = ctx.state.btInputConnected || 0;
                      return count > 0 ? ctx.t("value.connected_count", { count: count }) : "";
                  },
                  requires: hasInputDevices },
                { id: "universalControl", type: "lgApp", title: "row.universal_control",
                  app: { id: "com.webos.app.connectionwizard", params: {} },
                  requires: function (ctx) {
                      return profileHas(ctx, "universalControl") && ctx.cfg("tv.model.sysType") !== "ARIB";
                  } },
                { id: "mobileOn", type: "page", page: "mobileOn", title: "page.mobile_on",
                  summary: ["network.wolwowlOnOff", "network.bleAdvertisingOnOff"], search: "search.mobile_on" },
                { id: "deleteHistory", type: "action", action: "deleteConnectionHistory",
                  title: "row.delete_history", subtitle: "detail.delete_history",
                  confirm: { title: "confirm.delete_history_title", text: "confirm.delete_history_text",
                             confirm: "confirm.delete_history_button" } }
            ] }
        ]
    },

    pages: {
        input: {
            id: "input",
            title: function (ctx) { var item = inputItem(ctx); return item ? item.title : ""; },
            subtitle: function (ctx) {
                var item = inputItem(ctx);
                if (!item) return "";
                var port = ctx.t("detail.input_port", { port: item.port });
                return item.title !== port ? port : "";
            },
            sections: [
                { rows: [
                    { id: "switch", type: "action", action: "switchInput", title: "row.switch_to_input",
                      requires: function (ctx) { return itemInput(ctx) !== "" && notRunning(ctx); } },
                    // The panel's existing flow: eim/setDeviceInfo, as LG's Home Hub does it.
                    { id: "name", type: "action", action: "deviceDetails", title: "row.name_icon",
                      value: function (ctx) { var item = inputItem(ctx); return item ? item.title : ""; } },
                    { id: "gameOptimizer", type: "toggle", key: "other.gameMode", member: itemInput,
                      title: "row.game_optimizer", subtitle: "detail.game_optimizer" }
                ] },
                { title: "section.signal", rows: [
                    { id: "deepColor", type: "choice", key: "other.uhdDeepColor", title: "row.deep_color",
                      search: "search.deep_color", onChange: "deepColorChanged",
                      value: function (ctx) {
                          return notRunning(ctx) ? "" : ctx.label("other.uhdDeepColor", ctx.val("other.uhdDeepColor"));
                      },
                      disabled: [{ when: notRunning, reason: "reason.only_running_input" }] },
                    // Not in any LG menu for a chosen input: 4:4:4 pass-through per HDMI. LG's
                    // descriptor shows it only for the running input.
                    { id: "passThrough", type: "toggle", title: "row.pass_through", subtitle: "detail.pass_through",
                      search: "search.pass_through",
                      keyOf: function (ctx) { var port = itemPort(ctx); return port ? "other.444BypassHDMI" + port : ""; } },
                    { id: "audioFormat", type: "choice", title: "row.audio_format", search: "search.audio_format",
                      keyOf: function (ctx) {
                          var port = itemPort(ctx);
                          return port ? "sound.inputAudioFormatHDMI" + port : "";
                      } }
                ] },
                { title: "section.parental", rows: [
                    { id: "lock", type: "action", action: "toggleInputLock", title: "row.input_lock", pin: "parental",
                      value: function (ctx) { return ctx.t(inputLocked(ctx) ? "value.on" : "value.off"); },
                      requires: function (ctx) {
                          var item = inputItem(ctx);
                          return truthy(ctx.cfg("tv.conti.supportInputBlock")) && item !== null &&
                                 item.lockBit !== undefined;
                      },
                      disabled: [{ when: function (ctx) { return ctx.val("lock.parentalControl") !== true; },
                                   reason: "reason.parental_off" }] }
                ] }
            ]
        },

        // Quellen › Bluetooth-Geräte: counters, the paired devices, found ones and "Suchen".
        bluetoothInput: {
            id: "bluetoothInput",
            title: "page.bluetooth_input",
            session: "btInput",
            sections: [
                DeviceList.headSection(inputCounters),
                DeviceList.registeredSection(inputDevices),
                DeviceList.availableSection(inputDevices)
            ]
        },

        // One paired input device: "Gamepad · Verbunden", Trennen or Verbinden, Gerät entfernen.
        bluetoothInputDevice: {
            id: "bluetoothInputDevice",
            session: "btInputDevice",
            title: function (ctx) { var item = inputDevice(ctx); return item ? item.title : ""; },
            subtitle: function (ctx) { return DeviceList.deviceSubtitle(ctx, inputDevice(ctx), true); },
            busy: function (ctx) { return DeviceList.isBusy(inputDevice(ctx)); },
            sections: [
                { rows: DeviceList.deviceRows(inputDevices) }
            ]
        },

        mobileOn: {
            id: "mobileOn",
            title: "page.mobile_on",
            subtitle: "detail.mobile_on",
            sections: [
                { rows: [
                    { id: "wifi", type: "toggle", key: "network.wolwowlOnOff", title: "row.on_via_wifi",
                      on: "true", off: "false" },
                    { id: "bluetooth", type: "toggle", key: "network.bleAdvertisingOnOff", title: "row.on_via_bluetooth" }
                ] }
            ]
        }
    }
};
