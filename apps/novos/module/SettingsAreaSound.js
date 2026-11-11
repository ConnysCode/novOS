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
    watch: ["sound.blegattSoundbar", "sound.auracast", "sound.userEqualizer"],

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
                    { id: "tvSpeaker", type: "option", key: "sound.soundOutput", option: "tv_speaker",
                      title: "value.sound_output.tv_speaker" },
                    { id: "arc", type: "option", key: "sound.soundOutput", option: "external_arc",
                      title: "value.sound_output.external_arc", requires: hasArc,
                      subtitle: function (ctx) {
                          return ctx.val("sound.eArcSupport") === "on" ? ctx.t("detail.earc") : "";
                      } },
                    { id: "arcAndTv", type: "option", key: "sound.soundOutput", option: "tv_speaker_external_arc",
                      title: "value.sound_output.tv_speaker_external_arc", requires: hasArc },
                    { id: "optical", type: "option", key: "sound.soundOutput", option: "external_optical",
                      title: "value.sound_output.external_optical", requires: hasOptical },
                    { id: "opticalAndTv", type: "option", key: "sound.soundOutput", option: "tv_external_speaker",
                      title: "value.sound_output.tv_external_speaker", requires: hasOptical },
                    { id: "lineOut", type: "option", key: "sound.soundOutput", option: "lineout",
                      title: "value.sound_output.lineout",
                      requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportAudioLineOut")); } },
                    { id: "headphone", type: "option", key: "sound.soundOutput", option: "headphone",
                      title: "value.sound_output.headphone",
                      requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportHeadPhone")); } },
                    { id: "headphoneAndTv", type: "option", key: "sound.soundOutput", option: "tv_speaker_headphone",
                      title: "value.sound_output.tv_speaker_headphone",
                      requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportHeadPhone")); } }
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
                    { id: "bluetoothAndTv", type: "lgApp", title: "row.bluetooth_and_tv",
                      app: { id: "com.palm.app.settings", params: { target: "BluetoothSurround" } },
                      requires: function (ctx) { return bluetoothFeature(ctx, "bluetoothPlusTvSpeaker"); } }
                ] },
                { title: "section.more", rows: [
                    { id: "wisa", type: "lgApp", title: "row.wisa",
                      app: { id: "com.palm.app.settings", params: { target: "WiSASoundSync" } },
                      requires: function (ctx) { return truthy(ctx.cfg("tv.model.supportWiSA")); } },
                    { id: "wowcast", type: "lgApp", title: "row.wowcast",
                      app: { id: "com.palm.app.settings", params: { target: "Wowcast" } },
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
                    { id: "balance", type: "slider", key: "sound.audioBalance", title: "row.balance",
                      format: "signed", search: "search.balance",
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
