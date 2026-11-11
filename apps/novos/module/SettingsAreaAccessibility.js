.pragma library
.import "DeviceList.js" as DeviceList

// Area 08 "Barrierefreiheit" of the settings modal. Keys, locks and their order as in
// LG's "Allgemein › Barrierefreiheit" (docs/lg-settings/alle-einstellungen.md). The
// locks are LG's own: grayscale and inverted colors exclude the contrast and zoom aids.

function adjustment(ctx, name) {
    var value = ctx.val("option.adjustments");
    return value ? value[name] : undefined;
}

function isOn(ctx, key) {
    return ctx.val(key) === "on";
}

// LG learns this from profile.list of getConfigs.
function tunerless(ctx) {
    var list = ctx.cfg("profile.list");
    return !!list && list.indexOf("tunerless") >= 0;
}

var grayscaleOn = { when: function (ctx) { return adjustment(ctx, "blackAndWhite") === "on"; },
                    reason: "reason.grayscale_on" };
var invertOn = { when: function (ctx) { return adjustment(ctx, "colorInversion") === "on"; },
                 reason: "reason.invert_on" };
var guidanceOff = { when: function (ctx) { return !isOn(ctx, "option.audioGuidance"); },
                    reason: "reason.audio_guidance_off" };
var slowInputOff = { when: function (ctx) { return !isOn(ctx, "option.remoteSlowInput"); },
                     reason: "reason.slow_input_off" };

// The shortcut list holds LG's feature names. A name only makes sense where the
// feature itself is on this TV.
function shortcut(name, title, key) {
    return { id: "shortcut_" + name, type: "toggle", key: "option.a11yQuickList", member: name, title: title,
             requires: key ? function (ctx) { return ctx.has(key); } : undefined,
             // LG refuses an empty list: "Please select at least one item."
             disabled: [{ when: function (ctx) {
                              var list = ctx.val("option.a11yQuickList") || [];
                              return list.length === 1 && list[0] === name;
                          },
                          reason: "reason.shortcut_last" }] };
}

// Hearing aid at the same time (BF-1, K3-Einst-Hoergeraet), as LG's MultiOutputItemPanel:
// Bluetooth needs Bluetooth with the TV speaker (bluetoothPlusTvSpeaker), HDMI (ARC) an ARC
// port. Every change asks first and then writes the sound output along (SettingsData).
function hearingValues(ctx) {
    var values = ["off"];
    var features = ctx.cfg("system.supportBluetoothFeatures");
    if (features && features.indexOf("bluetoothPlusTvSpeaker") >= 0) values.push("bluetooth");
    var port = ctx.cfg("system.arcPort");
    if (port !== undefined && port !== null && port !== 0) values.push("external_arc");
    return values;
}

var hearingDetails = { bluetooth: "detail.hearing_bluetooth", external_arc: "detail.hearing_arc" };

// The pairing after "Bluetooth-Gerät", with TON-B's list and search.
var hearingDevices = {
    source: "bluetooth", found: "bluetoothFound", page: "",
    connect: "btAudioConnect", disconnect: "btAudioDisconnect", remove: "btAudioRemove", search: "btAudioSearch",
    searching: "btAudioSearching", ready: "btAudioReady", disconnectText: "confirm.disconnect_audio_text"
};

var area = {
    id: "accessibility",
    icon: "accessibility",
    title: "area.accessibility",
    configs: ["profile.list", "tv.conti.supportVideoDescription", "tv.conti.supportAddAudioDescription",
              "system.supportBluetoothFeatures", "system.arcPort"],
    reads: ["option.adjustments", "option.audioGuidance", "option.remoteSlowInput"],
    page: {
        id: "accessibility",
        title: "area.accessibility",
        sections: [
            {
                title: "section.vision",
                rows: [
                    { id: "audioGuidance", type: "page", page: "audioGuidance", title: "row.audio_guidance",
                      summary: ["option.audioGuidance"], search: "search.audio_guidance" },
                    { id: "highContrast", type: "toggle", key: "option.highContrast", title: "row.high_contrast",
                      subtitle: "detail.high_contrast", search: "search.high_contrast",
                      disabled: [grayscaleOn, invertOn] },
                    { id: "focusEmphasis", type: "toggle", key: "option.focusEmphasis", title: "row.focus_emphasis",
                      subtitle: "detail.focus_emphasis", search: "search.high_contrast",
                      disabled: [grayscaleOn, invertOn] },
                    { id: "grayscale", type: "toggle", key: "option.adjustments", field: "blackAndWhite",
                      title: "row.grayscale", search: "search.grayscale",
                      disabled: [{ when: function (ctx) { return isOn(ctx, "option.highContrast"); }, reason: "reason.high_contrast_on" },
                                 { when: function (ctx) { return isOn(ctx, "option.focusEmphasis"); }, reason: "reason.focus_emphasis_on" },
                                 invertOn,
                                 { when: function (ctx) { return isOn(ctx, "option.screenMagnification"); }, reason: "reason.zoom_on" }] },
                    { id: "invertColors", type: "toggle", key: "option.adjustments", field: "colorInversion",
                      title: "row.invert_colors", search: "search.invert_colors",
                      disabled: [{ when: function (ctx) { return isOn(ctx, "option.highContrast"); }, reason: "reason.high_contrast_on" },
                                 { when: function (ctx) { return isOn(ctx, "option.focusEmphasis"); }, reason: "reason.focus_emphasis_on" },
                                 grayscaleOn,
                                 { when: function (ctx) { return isOn(ctx, "option.screenMagnification"); }, reason: "reason.zoom_on" },
                                 { when: function (ctx) { return isOn(ctx, "other.autoSLZoomWithObjectDetection"); }, reason: "reason.sign_zoom_on" }] },
                    { id: "screenMagnification", type: "toggle", key: "option.screenMagnification",
                      title: "row.screen_zoom", subtitle: "detail.screen_zoom", search: "search.screen_zoom",
                      disabled: [grayscaleOn, invertOn] },
                    { id: "audioDescription", type: "toggle", key: "sound.audioDescription",
                      title: "row.audio_description", subtitle: "detail.audio_description",
                      search: "search.audio_description" },
                    { id: "audioDescriptionVolume", type: "slider", key: "sound.audioDescriptionVolume",
                      format: "signed", title: "row.audio_description_volume",
                      disabled: [{ when: function (ctx) { return !isOn(ctx, "sound.audioDescription"); },
                                   reason: "reason.audio_description_off" }] },
                    { id: "videoDescription", type: "toggle", key: "sound.visualImpaired",
                      title: "row.video_description", search: "search.audio_description",
                      requires: function (ctx) {
                          return !tunerless(ctx) && ctx.cfg("tv.conti.supportVideoDescription") === true;
                      } },
                    { id: "additionalAudio", type: "choice", key: "option.additionalAudioSelection",
                      title: "row.additional_audio", search: "search.audio_description",
                      requires: function (ctx) {
                          return !tunerless(ctx) && ctx.cfg("tv.conti.supportAddAudioDescription") === true;
                      } }
                ]
            },
            {
                title: "section.hearing",
                rows: [
                    { id: "subtitles", type: "page", page: "subtitles", title: "row.subtitles",
                      summary: ["caption.captionEnable", "option.subtitleLanguageFirst"], search: "search.subtitles" },
                    { id: "hardOfHearing", type: "toggle", key: "caption.hardOfHearing", title: "row.hard_of_hearing",
                      subtitle: "detail.hard_of_hearing", search: "search.subtitles" },
                    // Each value asks first: it switches the sound output along (SettingsData,
                    // hearingAidAsk). Auracast is left out.
                    { id: "hearingAid", type: "choice", key: "sound.hearingAid", title: "row.hearing_aid",
                      subtitle: "detail.hearing_aid", search: "search.hearing_aid", note: "note.hearing_aid",
                      requires: function (ctx) { return hearingValues(ctx).length > 1; },
                      value: function (ctx) { return ctx.label("sound.hearingAid", ctx.val("sound.hearingAid")); },
                      options: function (ctx) {
                          var values = hearingValues(ctx);
                          var current = ctx.val("sound.hearingAid");
                          return values.map(function (value) {
                              return { id: value, label: ctx.t("value.hearing_aid." + value),
                                       detail: hearingDetails[value] ? ctx.t(hearingDetails[value]) : "",
                                       selected: value === current,
                                       action: "hearingAidAsk", params: { value: value } };
                          });
                      } },
                    { id: "signLanguageZoom", type: "toggle", key: "other.autoSLZoomWithObjectDetection",
                      title: "row.sign_language_zoom", subtitle: "detail.sign_language_zoom",
                      search: "search.sign_language", disabled: [invertOn] }
                ]
            },
            {
                title: "section.operation",
                rows: [
                    { id: "tvPowerSound", type: "toggle", key: "sound.tvPowerSound", title: "row.power_sound",
                      subtitle: "detail.power_sound", search: "search.power_sound" },
                    { id: "remoteSlowInput", type: "page", page: "remoteSlowInput", title: "row.slow_input",
                      summary: ["option.remoteSlowInput"], search: "search.slow_input" },
                    // Explains what each key does under novOS (RemoteGuide.qml, BF-2).
                    { id: "remoteGuide", type: "action", action: "remoteGuide", title: "row.remote_guide",
                      subtitle: "detail.remote_guide", search: "search.remote_guide" }
                ]
            },
            {
                title: "section.shortcut",
                rows: [
                    { id: "shortcut", type: "page", page: "shortcut", title: "row.shortcut",
                      subtitle: "detail.shortcut", search: "search.shortcut",
                      requires: function (ctx) { return ctx.has("option.a11yQuickList"); } }
                ]
            }
        ]
    },
    pages: {
        // Right after "Bluetooth-Gerät" was confirmed: the hearing aid pairs here.
        hearingPair: {
            id: "hearingPair",
            title: "page.hearing_pair",
            subtitle: "detail.hearing_pair",
            session: "btAudioPair",
            sections: [DeviceList.availableSection(hearingDevices)]
        },

        audioGuidance: {
            id: "audioGuidance",
            title: "page.audio_guidance",
            subtitle: "detail.audio_guidance",
            sections: [
                {
                    rows: [
                        { id: "audioGuidanceEnable", type: "toggle", key: "option.audioGuidance",
                          title: "row.audio_guidance_enable" },
                        { id: "audioGuidanceSpeed", type: "choice", key: "option.audioGuidanceSpeed",
                          title: "row.speech_speed",
                          values: ["verySlow", "slow", "medium", "fast", "veryFast"], disabled: [guidanceOff] },
                        { id: "audioGuidanceVolume", type: "choice", key: "option.audioGuidanceVolume",
                          title: "row.speech_volume",
                          values: ["veryLow", "low", "medium", "high", "veryHigh"], disabled: [guidanceOff] },
                        { id: "audioGuidancePitch", type: "choice", key: "option.audioGuidancePitch",
                          title: "row.speech_pitch",
                          values: ["veryLow", "low", "medium", "high", "veryHigh"], disabled: [guidanceOff] }
                    ]
                }
            ]
        },
        subtitles: {
            id: "subtitles",
            title: "page.subtitles",
            sections: [
                {
                    rows: [
                        { id: "captionEnable", type: "toggle", key: "caption.captionEnable", title: "row.subtitles_enable" },
                        { id: "subtitleLanguageFirst", type: "choice", key: "option.subtitleLanguageFirst",
                          title: "row.subtitle_language_first" },
                        { id: "subtitleLanguageSecond", type: "choice", key: "option.subtitleLanguageSecond",
                          title: "row.subtitle_language_second" }
                    ]
                }
            ]
        },
        remoteSlowInput: {
            id: "remoteSlowInput",
            title: "page.slow_input",
            subtitle: "detail.slow_input",
            sections: [
                {
                    rows: [
                        { id: "remoteSlowInputEnable", type: "toggle", key: "option.remoteSlowInput",
                          title: "row.slow_input_enable" },
                        { id: "longPressInterval", type: "choice", key: "option.longPressInterval",
                          title: "row.long_press_time", disabled: [slowInputOff] },
                        { id: "repeatInterval", type: "choice", key: "option.repeatInterval",
                          title: "row.repeat_interval", disabled: [slowInputOff] }
                    ]
                }
            ]
        },
        shortcut: {
            id: "shortcut",
            title: "page.shortcut",
            subtitle: "detail.shortcut_page",
            sections: [
                {
                    rows: [
                        shortcut("AudioGuidance", "row.audio_guidance", "option.audioGuidance"),
                        shortcut("TvPowerSound", "row.power_sound", "sound.tvPowerSound"),
                        shortcut("HighContrast", "row.high_contrast", "option.highContrast"),
                        shortcut("FocusEmphasis", "row.focus_emphasis", "option.focusEmphasis"),
                        shortcut("Magnification", "row.screen_zoom", "option.screenMagnification"),
                        shortcut("GreyScale", "row.grayscale", "option.adjustments"),
                        shortcut("InvertColors", "row.invert_colors", "option.adjustments"),
                        shortcut("AudioDescription", "row.audio_description", "sound.audioDescription"),
                        shortcut("Subtitles", "row.subtitles", "caption.captionEnable"),
                        shortcut("HardOfHearing", "row.hard_of_hearing", "caption.hardOfHearing"),
                        shortcut("SignLanguageZoom", "row.sign_language_zoom", "other.autoSLZoomWithObjectDetection"),
                        shortcut("RemoteSlowInput", "row.slow_input", "option.remoteSlowInput")
                    ]
                }
            ]
        }
    }
};
