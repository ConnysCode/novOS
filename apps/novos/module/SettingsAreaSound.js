.pragma library
.import "DeviceList.js" as DeviceList

// Area 02 "Ton" of the settings modal. Keys, values and conditions follow LG's own settings
// app (com.palm.app.settings, webOS 10.3.2), see docs/lg-settings/alle-einstellungen.md,
// section "Ton". Values follow the running source (dimension audioInput/soundOutput).

// Outputs in which the TV speaker plays, as LG groups them for the sound mode and AV sync.
var tvSpeakerOutputs = ["tv_speaker", "tv_speaker_headphone", "tv_external_speaker",
                        "tv_speaker_external_arc", "tv_speaker_wow_cast", "tv_speaker_bluetooth"];
// Outputs for which LG offers the five-band equalizer (i6() in LG's main.js); with
// Bluetooth and the TV speaker together it stays greyed out.
var equalizerOutputs = ["tv_speaker", "tv_external_speaker", "tv_speaker_external_arc", "tv_speaker_headphone",
                        "tv_speaker_bluetooth", "tv_speaker_wow_cast", "tv_speaker_optical_arc", "external_arc"];
// Outputs with a digital stream, as LG's "Digital Sound Output" lists them.
var digitalOutputs = ["external_arc", "external_optical", "tv_speaker_external_arc", "wow_cast",
                      "tv_speaker_wow_cast"];

function output(ctx) {
    return ctx.val("sound.soundOutput") || "";
}

function outputIs(ctx, list) {
    return list.indexOf(output(ctx)) >= 0;
}

// LG's gB(): everything counts except false, "false", 0, null, undefined and "".
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

// LG: supportArc = system.arcPort !== 0, only when the config exists.
function hasArc(ctx) {
    var port = ctx.cfg("system.arcPort");
    return port !== undefined && port !== null && port !== 0;
}

function hasOptical(ctx) {
    return ctx.cfg("tv.model.supportOpticalJack") === "On";
}

function hasWowCast(ctx) {
    return truthy(ctx.cfg("com.webos.service.wowplay.supportWowCast"));
}

function hasBluetoothSound(ctx) {
    return bluetoothFeature(ctx, "btsound");
}

// Headphones and speakers over Bluetooth (TON-B) in the shared device list (TON-A). The host
// is BluetoothDevices.qml; "Aktuelle Ausgabe" replaces the state of the device that plays.
var audioDevices = {
    source: "bluetooth", found: "bluetoothFound", page: "bluetoothDevice",
    connect: "btAudioConnect", disconnect: "btAudioDisconnect", remove: "btAudioRemove", search: "btAudioSearch",
    searching: "btAudioSearching", ready: "btAudioReady", disconnectText: "confirm.disconnect_audio_text",
    note: function (ctx, entry) { return entry.output ? ctx.t("detail.current_output") : ""; }
};

// ---- Bluetooth und Fernsehlautsprecher (TON-D, K3-Einst-BT-und-TV) ----
// The speakers come from BluetoothDevices.qml (list btSurround, with position and positions);
// connect, disconnect and remove are the ones of TON-B. Setting up with a measurement stays
// LG's app btsurroundautotuning, which comes back here through its appReturn.
var surroundDevices = {
    source: "btSurround", connect: "btAudioConnect", disconnect: "btAudioDisconnect", remove: "btAudioRemove",
    disconnectText: "confirm.disconnect_audio_text", footer: true
};

function surroundItem(ctx) {
    return DeviceList.item(ctx, "btSurround", ctx.param);
}

function surroundConnected(ctx) {
    return ctx.list("btSurround").filter(function (entry) { return entry.state === "connected"; });
}

function hasSurroundSpeaker(ctx) {
    return surroundConnected(ctx).length > 0;
}

function hearingAidBluetooth(ctx) {
    return ctx.val("sound.hearingAid") === "bluetooth";
}

// ---- Hörgerät gleichzeitig (BF-1, K3-Einst-Hoergeraet-16/17) ----
// The shared output stands among the outputs with the volume of the second device; another
// output first asks to switch the hearing aid off (SettingsData.hearingAidOffTo).
function hearingAid(ctx) {
    return ctx.val("sound.hearingAid") || "off";
}

function hearingName(ctx) {
    var speakers = ctx.list("btSurround");
    for (var i = 0; i < speakers.length; i++) {
        if (speakers[i].state === "connected") return speakers[i].title;
    }
    return "";
}

function hearingSpeaker(ctx) {
    var speakers = ctx.list("btSurround");
    for (var i = 0; i < speakers.length; i++) {
        if (speakers[i].state === "connected") return speakers[i];
    }
    return null;
}

var hearingAsk = {
    action: "hearingAidOffTo",
    icon: "hearing-44",
    when: function (ctx) { return hearingAid(ctx) !== "off"; },
    safe: function (ctx) { return hearingAid(ctx) !== "bluetooth"; },
    title: "confirm.hearing_output_title",
    text: function (ctx, option) {
        return ctx.t(hearingAid(ctx) === "bluetooth" ? "confirm.hearing_output_bt_text" : "confirm.hearing_output_text",
                     { output: option.title });
    },
    confirm: "confirm.hearing_output_button"
};

// An option of the output list; with the hearing aid on, choosing it asks first.
function outputOption(id, value, extra) {
    var row = { id: id, type: "option", key: "sound.soundOutput", option: value,
                title: "value.sound_output." + value, ask: hearingAsk };
    for (var name in extra || {}) row[name] = extra[name];
    return row;
}

// LG's wte(): the balance shows with two speakers of the same model, the first connected one
// with AVRCP; it works once the first two connected ones both have AVRCP connected.
function baseName(name) {
    var text = String(name || "");
    return (text.indexOf("(") >= 0 ? text.split("(")[0] : text.split("_")[0]).trim();
}

function balanceShown(ctx) {
    var connected = surroundConnected(ctx);
    if (connected.length === 0 || !connected[0].avrcpSupported) return false;
    var name = baseName(connected[0].title);
    return ctx.list("btSurround").filter(function (entry) {
        return entry.avrcpSupported && baseName(entry.title) === name;
    }).length > 1;
}

function balanceWorks(ctx) {
    var connected = surroundConnected(ctx);
    return connected.length > 1 && connected[0].avrcpConnected && connected[1].avrcpConnected;
}

function positionText(ctx, position) {
    return position ? ctx.t("value.position." + position) : "";
}

var surroundLocked = [{ when: function (ctx) { return !hasSurroundSpeaker(ctx); }, reason: "reason.connect_speaker_first" }];

// ---- WiSA and WOWCAST (TON-E, K3-Einst-WiSA-WOWCAST) ----
// The host is WirelessSpeakers.qml: wisa/*, pdm for the dongle, wowplay/*, wifi for WOWCAST.
var wisaPositions = ["left", "right", "center", "subwoofer", "surround_left", "surround_right"];

function wisaItem(ctx) {
    return DeviceList.item(ctx, "wisa", ctx.param);
}

function wisaSearching(ctx) {
    return ctx.state.wisaSearching === true;
}

function wisaTesting(ctx) {
    return !!ctx.state.wisaTesting;
}

function wisaMissing(ctx) {
    var item = wisaItem(ctx);
    return !item || item.missing === true;
}

// LG greys out a speaker's rows while it is missing or being removed; volume also while a
// test tone plays.
var wisaLocked = [{ when: wisaMissing, reason: "reason.unreachable" },
                  { when: function (ctx) { var item = wisaItem(ctx); return !!item && item.removing; },
                    reason: "reason.not_available_now" }];

function wisaSection(position) {
    return {
        title: function (ctx) {
            return ctx.t("section.wisa_position", { position: ctx.t("value.position." + position),
                                                    count: ctx.list("wisa_" + position).length });
        },
        rows: [{ id: "wisa_" + position, type: "list", source: "wisa_" + position, page: "wisaSpeaker", dialog: true,
                 decorate: function (ctx, entry) {
                     return { title: entry.title, icon: "speaker",
                              subtitle: ctx.t(entry.missing ? "detail.unreachable" : "device.connected"),
                              tone: entry.missing ? "warning" : "" };
                 } }]
    };
}

// WOWCAST: no Wi-Fi, a frequency it cannot use or LG's WOWCAST dongle at HDMI (ARC) replace the
// list with a hint (LG's _7()).
function wowBlock(ctx) {
    if (ctx.state.wowDongle === true) return "dongle";
    if (ctx.state.wowWifi === false) return "wifi";
    if (ctx.state.wowWifi === true && ctx.state.wowFrequency === false) return "frequency";
    return "";
}

var wowcastDevices = {
    source: "wowcast", found: "wowcastFound", page: "wowcastDevice",
    connect: "wowConnect", disconnect: "wowDisconnect", remove: "wowRemove", search: "wowSearch",
    searching: "wowSearching", ready: "wowReady", footer: true, searchingHint: true,
    emptyHint: { icon: "soundbar-32", title: "device.none_found", text: "detail.wowcast_empty" },
    noneMore: "detail.wowcast_none_more",
    unavailableHint: { icon: "soundbar-32", title: "detail.wowcast_unavailable", text: "device.unavailable_hint" },
    when: function (ctx) { return wowBlock(ctx) === ""; },
    // LG: connecting a registered device needs Wi-Fi.
    locked: [{ when: function (ctx) { return ctx.state.wowWifi !== true; }, reason: "reason.needs_wifi" }]
};

function bluetoothItem(ctx) {
    return DeviceList.item(ctx, "bluetooth", ctx.param);
}

function deviceParams(ctx) {
    return { id: ctx.param };
}

// The sound mode only shapes the TV speaker. LG greys it out for other outputs.
function soundModeLocked(ctx) {
    var desc = ctx.desc("sound.soundMode");
    return desc && desc.ui && desc.ui.active === false && !outputIs(ctx, tvSpeakerOutputs);
}

var area = {
    id: "sound",
    icon: "sound",
    title: "area.sound",
    perSource: true,
    configs: ["profile.list", "system.arcPort", "system.supportBluetoothFeatures",
              "tv.model.supportOpticalJack", "tv.model.supportAudioLineOut", "tv.model.supportHeadPhone",
              "tv.model.supportWiSA", "tv.model.soundModeType", "audio.supportPSW",
              "com.webos.service.wowplay.supportWowCast", "com.webos.service.arccontroller.supportEARC",
              "com.palm.app.settings.enableMagicSoundTuning"],
    // Read only for requires/disabled, no row of their own.
    watch: ["sound.blegattSoundbar", "sound.auracast", "sound.userEqualizer", "sound.hearingAid"],

    page: {
        id: "sound",
        title: "area.sound",
        sections: [
            { rows: [
                { id: "soundMode", type: "choice", key: "sound.soundMode", title: "row.sound_mode",
                  search: "search.sound_mode",
                  disabled: [{ when: soundModeLocked, reason: "reason.tv_speaker_only" }] },
                { id: "output", type: "page", page: "output", title: "row.output", search: "search.output",
                  subtitle: function (ctx) { return ctx.label("sound.soundOutput", output(ctx)); },
                  disabled: [{ when: function (ctx) {
                      var desc = ctx.desc("sound.soundOutput");
                      return desc && desc.ui && desc.ui.active === false;
                  }, reason: "reason.not_available_now" }] }
            ] },
            { title: "section.adjust", rows: [
                { id: "tone", type: "page", page: "tone", title: "page.tone",
                  summary: ["sound.audioBalance", "sound.autoVolume"] },
                { id: "room", type: "page", page: "room", title: "page.room",
                  summary: ["sound.tvSetupConfiguration", "sound.wooferLevel"] },
                { id: "sync", type: "page", page: "sync", title: "page.sync", search: "search.sync",
                  watch: ["sound.avSyncSpeaker", "sound.avSyncSpdif", "sound.avSyncWisa", "sound.avSyncBtSurround"],
                  subtitle: function (ctx) {
                      if (bypassOn(ctx)) return ctx.t("summary.bypass_on");
                      var delay = ctx.val(delayKey(ctx));
                      return delay === undefined ? "" : ctx.t("summary.delay", { value: delay });
                  },
                  disabled: [{ when: function (ctx) {
                      return outputIs(ctx, ["mobile_phone", "bt_soundbar", "flex_connector"]);
                  }, reason: "reason.sync_not_for_output" }] },
                { id: "formats", type: "page", page: "formats", title: "page.formats",
                  summary: ["sound.soundOutputDigital", "sound.digitalAudioPriority"], search: "search.formats" },
                // Not in any LG menu: step of the volume keys.
                { id: "volumeStep", type: "slider", key: "sound.volumeStep", title: "row.volume_step",
                  subtitle: "detail.volume_step", search: "search.volume_step" }
            ] },
            { title: "section.lg_app", rows: [
                { id: "soundWizard", type: "lgApp", title: "row.sound_wizard",
                  app: { id: "com.webos.app.soundwizard", params: {} },
                  requires: function (ctx) { return truthy(ctx.cfg("audio.supportPSW")); },
                  disabled: [{ when: function (ctx) { return !outputIs(ctx, tvSpeakerOutputs); },
                               reason: "reason.tv_speaker_only" }] },
                { id: "soundbarApp", type: "lgApp", title: "row.soundbar_app",
                  app: { id: "com.webos.app.soundbar-setting", params: {} },
                  requires: function (ctx) { return ctx.has("sound.blegattSoundbar"); },
                  disabled: [{ when: function (ctx) {
                      var desc = ctx.desc("sound.blegattSoundbar");
                      return desc && desc.ui && desc.ui.active === false;
                  }, reason: "reason.soundbar_not_connected" }] }
            ] },
            { rows: [
                { id: "applyAll", type: "action", action: "applySoundToAll", title: "row.apply_all",
                  confirm: { title: "confirm.apply_all_title", text: "confirm.apply_all_text",
                             confirm: "confirm.apply_all_button", safe: true },
                  disabled: [{ when: soundModeLocked, reason: "reason.tv_speaker_only" }] },
                { id: "reset", type: "action", action: "resetSound", title: "row.reset",
                  confirm: { title: "confirm.reset_title", text: "confirm.reset_text",
                             confirm: "confirm.reset_button" },
                  disabled: [{ when: soundModeLocked, reason: "reason.tv_speaker_only" },
                             { when: function (ctx) {
                                 var mode = ctx.val("sound.soundMode");
                                 return truthy(ctx.cfg("audio.supportPSW")) ? mode === "personalized"
                                                                            : mode !== "standard";
                             }, reason: "reason.reset_standard_only" }] }
            ] }
        ]
    },

    pages: {
        // Every output on one page instead of LG's six levels (K3-Struktur-Audioausgabe).
        output: {
            id: "output",
            title: "page.output",
            // The paired devices stay current while the page is open (BluetoothDevices.qml).
            session: "btAudio",
            sections: [
                { title: "section.output", rows: [
                    outputOption("tvSpeaker", "tv_speaker"),
                    outputOption("arc", "external_arc", {
                        requires: hasArc,
                        subtitle: function (ctx) {
                            return ctx.val("sound.eArcSupport") === "on" ? ctx.t("detail.earc") : "";
                        } }),
                    // As LG: only while the hearing aid is the sender on HDMI (ARC).
                    outputOption("arcAndTv", "tv_speaker_external_arc", {
                        requires: function (ctx) { return hasArc(ctx) && hearingAid(ctx) === "external_arc"; } }),
                    outputOption("optical", "external_optical", { requires: hasOptical }),
                    outputOption("opticalAndTv", "tv_external_speaker", { requires: hasOptical }),
                    outputOption("lineOut", "lineout", {
                        requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportAudioLineOut")); } }),
                    outputOption("headphone", "headphone", {
                        requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportHeadPhone")); } }),
                    outputOption("headphoneAndTv", "tv_speaker_headphone", {
                        requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportHeadPhone")); } }),
                    // The hearing aid over Bluetooth plays with the TV speaker.
                    { id: "hearingBt", type: "option", key: "sound.soundOutput", option: "tv_speaker_bluetooth",
                      title: "value.sound_output.tv_speaker_bluetooth",
                      subtitle: function (ctx) {
                          var name = hearingName(ctx);
                          return name ? ctx.t("detail.with_hearing_aid", { name: name }) : "";
                      },
                      requires: function (ctx) { return hearingAid(ctx) === "bluetooth"; } },
                    // btaudiosrc setDeviceVolume, only with AVRCP; LG greys it without.
                    { id: "hearingBtVolume", type: "slider", min: 0, max: 100, action: "btSurroundHearing",
                      title: function (ctx) {
                          var name = hearingName(ctx);
                          return name ? ctx.t("row.device_volume", { name: name }) : ctx.t("row.hearing_aid_volume");
                      },
                      read: function (ctx) { return (ctx.state.btAudioVolume || {})[ctx.state.btSurroundDevice]; },
                      value: function (ctx) { var item = hearingSpeaker(ctx); return item && !item.avrcpConnected ? "–" : ""; },
                      requires: function (ctx) { return hearingAid(ctx) === "bluetooth" && hearingSpeaker(ctx) !== null; },
                      disabled: [{ when: function (ctx) { var item = hearingSpeaker(ctx); return !item || !item.avrcpConnected; },
                                   reason: "reason.volume_on_hearing_aid" }] },
                    // A sender on HDMI (ARC): LG's steps, audio/master volumeUp/volumeDown.
                    { id: "hearingArcVolume", type: "slider", min: 0, max: 100, action: "arcVolume",
                      title: "row.sender_volume",
                      read: function (ctx) { return ctx.state.arcVolume >= 0 ? ctx.state.arcVolume : 0; },
                      value: function (ctx) {
                          return output(ctx) !== "tv_speaker_external_arc" || !(ctx.state.arcVolume >= 0) ? "–" : "";
                      },
                      requires: function (ctx) { return hearingAid(ctx) === "external_arc"; },
                      disabled: [{ when: function (ctx) { return output(ctx) !== "tv_speaker_external_arc"; },
                                   reason: "reason.only_arc_and_tv" }] }
                ] },
                { title: "section.bluetooth",
                  rows: [
                    { id: "paired", type: "list", source: "bluetooth", page: "bluetoothDevice",
                      requires: hasBluetoothSound,
                      decorate: function (ctx, entry) { return DeviceList.pairedRow(ctx, entry, audioDevices.note); } },
                    // LG warns before pairing while Bluetooth plays with the TV speaker: the
                    // connection ends.
                    { id: "pair", type: "page", page: "bluetoothPair", title: "row.pair_bluetooth",
                      search: "search.bluetooth", requires: hasBluetoothSound,
                      ask: { when: function (ctx) { return output(ctx) === "tv_speaker_bluetooth"; },
                             title: "confirm.bt_tv_title", text: "confirm.bt_tv_text", confirm: "confirm.bt_tv_button" } },
                    // LG: "Einstellungen der Lautsprecherverbindung", locked while a device pairs,
                    // connects or disconnects.
                    { id: "deviceCount", type: "choice", key: "sound.deviceCntOfBtGeneral", title: "row.bt_device_count",
                      search: "search.bt_device_count", requires: hasBluetoothSound,
                      values: ["singleConnection", "dualConnection"],
                      details: { dualConnection: "detail.dual_connection" },
                      disabled: [{ when: function (ctx) { return DeviceList.anyBusy(ctx, audioDevices); },
                                   reason: "reason.device_busy" }] },
                    // TON-D: novOS' own page; only the setup with a measurement is LG's.
                    { id: "bluetoothAndTv", type: "page", page: "bluetoothAndTv", title: "row.bluetooth_and_tv",
                      search: "search.bluetooth_and_tv",
                      requires: function (ctx) { return bluetoothFeature(ctx, "bluetoothPlusTvSpeaker"); },
                      subtitle: function (ctx) {
                          return output(ctx) === "tv_speaker_bluetooth" ? ctx.t("value.on") : "";
                      } }
                ] },
                { title: "section.more", rows: [
                    // TON-E: WiSA only with LG's WiSA dongle in a USB port.
                    { id: "wisa", type: "page", page: "wisa", title: "row.wisa", search: "search.wisa",
                      requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportWiSA")); },
                      subtitle: function (ctx) {
                          var count = ctx.list("wisa").length;
                          return count > 0 ? ctx.t(count === 1 ? "detail.speaker_one" : "detail.speakers",
                                                   { count: count }) : "";
                      },
                      disabled: [{ when: function (ctx) { return ctx.state.wisaDongle !== true; },
                                   reason: "reason.no_wisa_dongle" }] },
                    { id: "wowcast", type: "page", page: "wowcast", title: "row.wowcast", search: "search.wowcast",
                      requires: hasWowCast },
                    { id: "auracast", type: "lgApp", title: "row.auracast",
                      app: { id: "com.webos.app.leaudio", params: {} },
                      requires: function (ctx) { return ctx.has("sound.auracast"); },
                      disabled: [{ when: function (ctx) {
                          var desc = ctx.desc("sound.auracast");
                          return desc && desc.ui && desc.ui.active === false;
                      }, reason: "reason.auracast_output" }] }
                ] }
            ]
        },

        // "Neues Gerät koppeln": the search starts as the page opens, found devices connect in
        // their row. The paired ones stand on the page above.
        bluetoothPair: {
            id: "bluetoothPair",
            title: "page.bluetooth_pair",
            session: "btAudioPair",
            sections: [
                DeviceList.headSection(function (ctx) { return { icon: "bluetooth-26", text: ctx.t("block.pair_hint") }; }),
                DeviceList.availableSection(audioDevices)
            ]
        },

        // One paired device, opened from the list on Audioausgabe (ctx.param is its address).
        bluetoothDevice: {
            id: "bluetoothDevice",
            session: "btAudioDevice",
            title: function (ctx) { var item = bluetoothItem(ctx); return item ? item.title : ""; },
            subtitle: function (ctx) { return DeviceList.deviceSubtitle(ctx, bluetoothItem(ctx), false); },
            badge: function (ctx) { var item = bluetoothItem(ctx); return item && item.atmos ? ctx.t("badge.dolby_atmos") : ""; },
            busy: function (ctx) { return DeviceList.isBusy(bluetoothItem(ctx)); },
            sections: [
                { rows: [
                    // As LG's output "Bluetooth-Gerät": sound.soundOutput = bt_soundbar; a device
                    // that is not connected connects first.
                    { id: "use", type: "action", action: "btAudioUse", title: "row.bluetooth_use", paramsOf: deviceParams,
                      selected: function (ctx) { var item = bluetoothItem(ctx); return !!item && item.output; } },
                    // btaudiosrc get/setDeviceVolume, only for devices with AVRCP.
                    { id: "volume", type: "slider", title: "row.bluetooth_volume", min: 0, max: 100,
                      action: "btAudioVolume",
                      read: function (ctx) {
                          var volumes = ctx.state.btAudioVolume || {};
                          return volumes[ctx.param];
                      },
                      value: function (ctx) { var item = bluetoothItem(ctx); return item && !item.avrcpConnected ? "–" : ""; },
                      requires: function (ctx) { var item = bluetoothItem(ctx); return !!item && item.avrcpSupported; },
                      disabled: [{ when: function (ctx) { var item = bluetoothItem(ctx); return !item || !item.avrcpConnected; },
                                   reason: "reason.volume_on_device" }] },
                    { id: "delay", type: "slider", key: "sound.avSyncBtSurround", title: "row.bluetooth_delay",
                      requires: function (ctx) { return output(ctx) === "tv_speaker_bluetooth"; } }
                ].concat(DeviceList.deviceRows(audioDevices)) }
            ]
        },

        // Bluetooth und Fernsehlautsprecher (K3-Einst-BT-und-TV-01 … 12). Back from LG's setup
        // app the modal opens here with the focus on "Einrichten mit Messung" and a notice.
        bluetoothAndTv: {
            id: "bluetoothAndTv",
            title: "row.bluetooth_and_tv",
            session: "btSurround",
            arrive: { focus: "setup", notice: "toast.setup_done", icon: "notice-speaker" },
            sections: [
                DeviceList.headSection(function (ctx) { return { icon: "speaker-26", text: ctx.t("block.bt_tv") }; }),
                { rows: [
                    // descOptional: LG's own page shows it whether or not the service describes it.
                    { id: "playback", type: "choice", key: "sound.bluetoothMode", title: "row.playback_option",
                      search: "search.playback_option", values: ["surroundMode", "speakerMode"], descOptional: true,
                      details: { surroundMode: "detail.surround_mode", speakerMode: "detail.speaker_mode" },
                      disabled: surroundLocked.concat([{ when: hearingAidBluetooth, reason: "reason.not_with_hearing_aid" }]) }
                ] },
                { title: function (ctx) { return ctx.t("section.speakers", { count: ctx.list("btSurround").length }); },
                  rows: [
                    { id: "speakers", type: "list", source: "btSurround", page: "btSurroundDevice", dialog: true,
                      decorate: function (ctx, entry) {
                          var row = DeviceList.pairedRow(ctx, entry);
                          row.value = positionText(ctx, entry.position);
                          return row;
                      } },
                    { id: "noSpeakers", type: "info", title: "detail.no_speakers", focusable: false,
                      requires: function (ctx) { return ctx.list("btSurround").length === 0; } }
                ] },
                { title: "section.adjust", rows: [
                    { id: "surroundDelay", type: "slider", key: "sound.avSyncBtSurround", title: "row.sound_delay",
                      min: 0, max: 60, descOptional: true,
                      requires: function (ctx) { return hasSurroundSpeaker(ctx) && !hearingAidBluetooth(ctx); } },
                    // surround/setVolumeBalancing, no descriptor: the value LG reads back.
                    { id: "surroundLevel", type: "slider", title: "row.bt_speaker_volume", min: 0, max: 10,
                      action: "btSurroundLevel",
                      read: function (ctx) { return ctx.state.btSurroundLevel; },
                      requires: function (ctx) { return hasSurroundSpeaker(ctx) && !hearingAidBluetooth(ctx); } },
                    { id: "surroundBalance", type: "slider", title: "row.balance", min: 0, max: 10, center: 5,
                      format: "balance", ends: ["value.left_short", "value.right_short"], action: "btSurroundBalance",
                      read: function (ctx) {
                          return ctx.state.btSurroundBalance === undefined ? 5 : ctx.state.btSurroundBalance;
                      },
                      requires: balanceShown,
                      disabled: [{ when: function (ctx) { return !balanceWorks(ctx); }, reason: "reason.connect_both" }] },
                    // Hearing aid over Bluetooth (BF-1): the device volume of the first speaker.
                    { id: "hearingVolume", type: "slider", title: "row.hearing_aid_volume", min: 0, max: 100,
                      action: "btSurroundHearing",
                      read: function (ctx) { return (ctx.state.btAudioVolume || {})[ctx.state.btSurroundDevice]; },
                      requires: function (ctx) {
                          var connected = surroundConnected(ctx);
                          return hearingAidBluetooth(ctx) && connected.length > 0 && connected[0].avrcpSupported;
                      },
                      disabled: [{ when: function (ctx) { return !surroundConnected(ctx)[0].avrcpConnected; },
                                   reason: "reason.volume_on_device" }] }
                ] },
                { title: "section.setup", rows: [
                    // LG's app; its appReturn goes to LG's settings app, which hands over to this
                    // page (settings-redirect.inc, novosPage). With a speaker connected it asks
                    // first, as LG does: setting up again ends the connections.
                    { id: "setup", type: "lgApp", title: "row.setup_measure", subtitle: "detail.setup_measure",
                      icon: "microphone", search: "search.setup_measure",
                      app: { id: "com.webos.app.btsurroundautotuning",
                             params: { appReturn: { appId: "com.palm.app.settings",
                                                    params: { novosPage: "settings:sound:bluetoothAndTv:arrive" } } } },
                      confirm: { when: hasSurroundSpeaker, title: "confirm.setup_title", text: "confirm.setup_text",
                                 confirm: "confirm.setup_button" } },
                    { id: "surroundReset", type: "action", action: "btSurroundReset", title: "row.reset",
                      disabled: surroundLocked,
                      confirm: { title: "confirm.reset_bt_tv_title", text: "confirm.reset_bt_tv_text",
                                 confirm: "confirm.reset_button", danger: true } }
                ] }
            ]
        },

        // A speaker of Bluetooth und Fernsehlautsprecher as a dialog (K3-Einst-BT-und-TV-05 … 07).
        btSurroundDevice: {
            id: "btSurroundDevice",
            dialog: true,
            icon: "speaker",
            title: function (ctx) { var item = surroundItem(ctx); return item ? item.title : ""; },
            subtitle: function (ctx) { return DeviceList.stateText(ctx, surroundItem(ctx)); },
            busy: function (ctx) { return DeviceList.isBusy(surroundItem(ctx)); },
            sections: [
                { rows: [
                    // LG: only for a connected speaker, changeable with Bluetooth and the TV speaker
                    // as output. Two values: OK takes the other one.
                    { id: "position", type: "choice", title: "row.position", cycle: true,
                      requires: function (ctx) { var item = surroundItem(ctx); return !!item && item.state === "connected"; },
                      options: function (ctx) {
                          var item = surroundItem(ctx);
                          if (!item) return [];
                          return item.positions.map(function (position) {
                              return { id: position, label: positionText(ctx, position), selected: position === item.position,
                                       action: "btSurroundPosition", params: { id: item.id, to: position } };
                          });
                      },
                      disabled: [{ when: function (ctx) { return output(ctx) !== "tv_speaker_bluetooth"; },
                                   reason: "reason.bt_tv_output_only" },
                                 { when: function (ctx) { return DeviceList.isBusy(surroundItem(ctx)); },
                                   reason: "reason.not_available_now" }] }
                ].concat(DeviceList.deviceRows(surroundDevices)) }
            ]
        },

        // WiSA speakers by position (K3-Einst-WiSA-WOWCAST-03 … 06).
        wisa: {
            id: "wisa",
            title: "row.wisa",
            session: "wisa",
            sections: [
                { rows: [
                    { id: "channelType", type: "choice", key: "sound.wisaSpeakerChannelType", title: "row.channel_type",
                      search: "search.channel_type", values: ["2", "2.1"], descOptional: true,
                      details: { "2.1": "detail.with_subwoofer" },
                      disabled: [{ when: wisaSearching, reason: "reason.not_while_searching" }] }
                ] }
            ].concat(wisaPositions.map(wisaSection)).concat([
                { rows: [
                    { id: "wisaHint", type: "hint",
                      requires: function (ctx) {
                          return ctx.state.wisaReady === false || (ctx.list("wisa").length === 0 && !wisaSearching(ctx));
                      },
                      hint: function (ctx) {
                          if (ctx.state.wisaReady === false) {
                              return { icon: "speaker-32", title: ctx.t("detail.wisa_unavailable"),
                                       text: ctx.t("device.unavailable_hint") };
                          }
                          return { icon: "speaker-32", title: ctx.t("detail.wisa_none"), text: ctx.t("detail.wisa_none_hint") };
                      } },
                    DeviceList.searchRow({ search: "wisaSearch", searching: "wisaSearching", ready: "wisaReady", source: "wisa" })
                ] }
            ])
        },

        // One WiSA speaker (K3-Einst-WiSA-WOWCAST-07 … 11): position beside its row, volume
        // from -5 to 10 around 0, a test tone, and "Entfernen".
        wisaSpeaker: {
            id: "wisaSpeaker",
            dialog: true,
            // Closing the dialog stops a test tone that still plays.
            session: "wisaSpeaker",
            icon: "speaker",
            title: function (ctx) { var item = wisaItem(ctx); return item ? item.title : ""; },
            subtitle: function (ctx) {
                var item = wisaItem(ctx);
                return item ? ctx.t(item.missing ? "detail.unreachable" : "device.connected") : "";
            },
            sections: [
                { rows: [
                    { id: "position", type: "choice", title: "row.position",
                      options: function (ctx) {
                          var item = wisaItem(ctx);
                          if (!item) return [];
                          var taken = ctx.state.wisaTaken || {};
                          return wisaPositions.map(function (position) {
                              var holder = taken[position];
                              return { id: position, label: positionText(ctx, position), selected: position === item.position,
                                       detail: holder && holder !== item.id ? ctx.t("detail.taken") : "",
                                       action: "wisaPosition", params: { id: item.id, to: position } };
                          });
                      },
                      disabled: wisaLocked.concat([{ when: wisaTesting, reason: "reason.test_tone_running" }]) },
                    { id: "wisaVolume", type: "slider", title: "row.volume", min: -5, max: 10, center: 0,
                      format: "signed", ends: ["value.minus", "value.plus"], action: "wisaVolume",
                      read: function (ctx) { var item = wisaItem(ctx); return item ? item.volume : 0; },
                      disabled: wisaLocked.concat([{ when: wisaTesting, reason: "reason.test_tone_running" }]) },
                    // OK plays the tone, OK again stops it (LG's soundTestOneSpeaker play/stop).
                    { id: "testTone", type: "action", title: "row.test_tone", icon: "test-tone", action: "wisaTestTone",
                      paramsOf: function (ctx) { return { id: ctx.param }; },
                      value: function (ctx) { return ctx.state.wisaTesting === ctx.param ? ctx.t("value.running") : ""; },
                      busy: function (ctx) { return ctx.state.wisaTesting === ctx.param; },
                      disabled: wisaLocked },
                    { id: "remove", type: "action", action: "wisaRemove", title: "row.remove", danger: true, footer: true,
                      paramsOf: function (ctx) { return { id: ctx.param }; },
                      disabled: [{ when: wisaTesting, reason: "reason.test_tone_running" }],
                      confirm: { title: "confirm.remove_title", text: "confirm.remove_wisa_text",
                                 confirm: "confirm.remove_button", danger: true,
                                 params: function (ctx) { var item = wisaItem(ctx); return { name: item ? item.title : "" }; } } }
                ] }
            ]
        },

        // WOWCAST over Wi-Fi (K3-Einst-WiSA-WOWCAST-12 … 19). "WLAN einrichten" opens novOS'
        // own Wi-Fi setup over the modal (WifiSetup), not LG's firstuse-overlay.
        wowcast: {
            id: "wowcast",
            title: "row.wowcast",
            session: "wowcast",
            sections: [
                { rows: [
                    { id: "wowHint", type: "hint",
                      requires: function (ctx) { return wowBlock(ctx) !== ""; },
                      hint: function (ctx) {
                          var block = wowBlock(ctx);
                          return { icon: block === "wifi" ? "wifi-off-32" : (block === "dongle" ? "soundbar-32" : "wifi-32"),
                                   title: ctx.t("detail.wowcast_" + block + "_title"),
                                   text: ctx.t("detail.wowcast_" + block + "_text") };
                      } },
                    { id: "wowWifi", type: "action", action: "wifiSetup", title: "row.wifi_setup", icon: "network",
                      requires: function (ctx) { var block = wowBlock(ctx); return block === "wifi" || block === "frequency"; } }
                ] },
                { title: "section.registered_device", rows: [
                    { id: "wowRegistered", type: "list", source: "wowcast", page: "wowcastDevice", dialog: true,
                      requires: function (ctx) { return wowBlock(ctx) === ""; },
                      decorate: function (ctx, entry) { return DeviceList.pairedRow(ctx, entry); } }
                ] },
                DeviceList.availableSection(wowcastDevices)
            ]
        },

        // The registered WOWCAST device as a dialog: Verbinden or Trennen, Entfernen.
        wowcastDevice: {
            id: "wowcastDevice",
            dialog: true,
            icon: "soundbar",
            title: function (ctx) { var item = DeviceList.item(ctx, "wowcast", ctx.param); return item ? item.title : ""; },
            subtitle: function (ctx) { return DeviceList.stateText(ctx, DeviceList.item(ctx, "wowcast", ctx.param)); },
            busy: function (ctx) { return DeviceList.isBusy(DeviceList.item(ctx, "wowcast", ctx.param)); },
            sections: [{ rows: DeviceList.deviceRows(wowcastDevices) }]
        },

        tone: {
            id: "tone",
            title: "page.tone",
            sections: [
                { rows: [
                    // Five bands over the picture (BandEditor, K3-Einst-Equalizer). LG writes the
                    // whole array and marks the sound mode as changed with every step.
                    { id: "equalizer", type: "bands", key: "sound.userEqualizerValues", title: "row.equalizer",
                      icon: "equalizer", search: "search.equalizer",
                      bands: ["100 Hz", "300 Hz", "1 kHz", "3 kHz", "10 kHz"],
                      alsoWrite: { soundModeModified: "true" },
                      requires: function (ctx) { return ctx.has("sound.userEqualizer"); },
                      // LG: standard mode, userEqualizer active, an output of equalizerOutputs but not
                      // Bluetooth with the TV speaker. LG Harmony and the sound recommendation are
                      // not known here; LG reports them through userEqualizer as well.
                      disabled: [{ when: function (ctx) { return ctx.val("sound.soundMode") !== "standard"; },
                                   reason: "reason.equalizer_standard_only" },
                                 { when: function (ctx) { return output(ctx) === "tv_speaker_bluetooth"; },
                                   reason: "reason.equalizer_bluetooth_tv" },
                                 { when: function (ctx) { return !outputIs(ctx, equalizerOutputs); },
                                   reason: "reason.equalizer_output" },
                                 { when: function (ctx) {
                                     var desc = ctx.desc("sound.userEqualizer");
                                     return desc && desc.ui && desc.ui.active === false;
                                 }, reason: "reason.not_available_now" }] },
                    // The same look as the balance of Bluetooth und Fernsehlautsprecher: L/R around
                    // the middle (TON-D).
                    { id: "balance", type: "slider", key: "sound.audioBalance", title: "row.balance",
                      format: "balance", center: 0, ends: ["value.left_short", "value.right_short"],
                      search: "search.balance",
                      disabled: [{ when: function (ctx) { return output(ctx) === "external_arc"; },
                                   reason: "reason.not_for_arc" }] },
                    { id: "autoVolume", type: "toggle", key: "sound.autoVolume", title: "row.auto_volume",
                      subtitle: "detail.auto_volume", search: "search.auto_volume" },
                    { id: "ac4", type: "toggle", key: "sound.ac4DialogueEnhancer", title: "row.ac4",
                      subtitle: "detail.ac4" },
                    { id: "atmos", type: "toggle", key: "sound.supportATMOS", title: "row.dolby_atmos",
                      requires: function (ctx) { return ctx.cfg("tv.model.soundModeType") === "Dolby Atmos"; } }
                ] }
            ]
        },

        room: {
            id: "room",
            title: "page.room",
            sections: [
                { rows: [
                    { id: "installation", type: "choice", key: "sound.tvSetupConfiguration",
                      title: "row.installation", search: "search.installation",
                      disabled: [{ when: function (ctx) { return output(ctx) === "external_arc"; },
                                   reason: "reason.not_for_arc" }] },
                    { id: "acousticTuning", type: "lgApp", title: "row.acoustic_tuning",
                      search: "search.acoustic_tuning",
                      app: { id: "com.palm.app.settings", params: { target: "MagicSpaceSound" } },
                      requires: function (ctx) {
                          return truthy(ctx.cfg("com.palm.app.settings.enableMagicSoundTuning"));
                      },
                      disabled: [{ when: function (ctx) { return !outputIs(ctx, tvSpeakerOutputs); },
                                   reason: "reason.tv_speaker_only" }] },
                    // Not in any LG menu.
                    { id: "woofer", type: "slider", key: "sound.wooferLevel", title: "row.woofer",
                      subtitle: "detail.woofer", search: "search.woofer",
                      disabled: [{ when: function (ctx) { return !outputIs(ctx, tvSpeakerOutputs); },
                                   reason: "reason.tv_speaker_only" }] }
                ] }
            ]
        },

        // LG picks the delay key from the output (bre() in LG's main.js).
        sync: {
            id: "sync",
            title: "page.sync",
            sections: [
                { rows: [
                    { id: "delaySpeaker", type: "slider", key: "sound.avSyncSpeaker", title: "row.delay",
                      requires: function (ctx) {
                          return !outputIs(ctx, ["external_optical", "external_arc", "wow_cast", "wisa_speaker",
                                                 "tv_speaker_bluetooth"]);
                      },
                      disabled: [{ when: bypassOn, reason: "reason.bypass_on" }] },
                    { id: "delayDigital", type: "slider", key: "sound.avSyncSpdif", title: "row.delay",
                      requires: function (ctx) { return outputIs(ctx, ["external_optical", "external_arc", "wow_cast"]); },
                      disabled: [{ when: bypassOn, reason: "reason.bypass_on" }] },
                    { id: "delayWisa", type: "slider", key: "sound.avSyncWisa", title: "row.delay",
                      requires: function (ctx) { return output(ctx) === "wisa_speaker"; },
                      disabled: [{ when: bypassOn, reason: "reason.bypass_on" }] },
                    { id: "delayBluetooth", type: "slider", key: "sound.avSyncBtSurround", title: "row.delay",
                      requires: function (ctx) { return output(ctx) === "tv_speaker_bluetooth"; },
                      disabled: [{ when: bypassOn, reason: "reason.bypass_on" }] },
                    { id: "bypass", type: "toggle", key: "sound.avSyncBypassInput", title: "row.bypass",
                      subtitle: "detail.bypass" }
                ] }
            ]
        },

        formats: {
            id: "formats",
            title: "page.formats",
            sections: [
                { rows: [
                    { id: "digitalOut", type: "choice", key: "sound.soundOutputDigital", title: "row.digital_out",
                      search: "search.digital_out",
                      requires: function (ctx) { return hasOptical(ctx) || hasArc(ctx) || hasWowCast(ctx); },
                      disabled: [{ when: function (ctx) {
                          if (!outputIs(ctx, digitalOutputs)) return true;
                          // LG also locks it for Optical with LG Sound Sync and for ARC plus TV speaker
                          // without an LG Harmony device; that state is not known here.
                          return (output(ctx) === "external_optical" && ctx.val("sound.lgSoundSync") === "on") ||
                                 output(ctx) === "tv_speaker_external_arc";
                      }, reason: "reason.digital_output_only" }] },
                    { id: "earc", type: "toggle", key: "sound.eArcSupport", title: "row.earc",
                      subtitle: "detail.earc_support",
                      requires: function (ctx) { return truthy(ctx.cfg("com.webos.service.arccontroller.supportEARC")); },
                      disabled: [{ when: function (ctx) {
                          return !outputIs(ctx, ["external_arc", "tv_speaker_external_arc"]);
                      }, reason: "reason.arc_only" }] },
                    { id: "dtvAudio", type: "choice", key: "sound.digitalAudioPriority", title: "row.dtv_audio",
                      requires: function (ctx) { return !profileHas(ctx, "tunerless"); } },
                    { id: "soundSync", type: "toggle", key: "sound.lgSoundSync", title: "row.lg_sound_sync",
                      requires: hasOptical,
                      disabled: [{ when: function (ctx) { return output(ctx) !== "external_optical"; },
                                   reason: "reason.optical_only" }] },
                    { id: "shareMode", type: "toggle", key: "sound.soundAlive", title: "row.share_sound_mode",
                      subtitle: "detail.share_sound_mode" }
                ] }
            ]
        }
    }
};

// The delay key LG uses for the current output.
function delayKey(ctx) {
    if (outputIs(ctx, ["external_optical", "external_arc", "wow_cast"])) return "sound.avSyncSpdif";
    if (output(ctx) === "wisa_speaker") return "sound.avSyncWisa";
    if (output(ctx) === "tv_speaker_bluetooth") return "sound.avSyncBtSurround";
    return "sound.avSyncSpeaker";
}

function bypassOn(ctx) {
    return ctx.val("sound.avSyncBypassInput") === "on";
}
