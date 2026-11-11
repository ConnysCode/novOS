.pragma library

// What each key of the remote does under novOS, short and long, for "Fernbedienung erlernen"
// (BF-2, K3-Einst-Fernbedienung). The assignment is not settled yet: entries with placeholder
// show their texts in brackets with the mark "Platzhalter". Starting point, as of
// 11 November 2026: lib/ui/Remote.qml, the overlays of install/tv/make-overlays.sh
// (systemUi.js, appLaunch.js, QuickSettings.qml, InputPicker.qml, StarfishVolumeView.qml),
// launcher-home-key.inc and launcher.qml. This file is meant to become the one place that
// names the assignment.
//
// A key is found by its Qt key (qt) or by the name of a webOS key (webos), which the window
// resolves through WebOS.Global, so that names this TV does not know are simply skipped.
// icon: a PNG in icons/ (80 px); label: text on the key instead; dot: a colour token.

var keys = [
    { id: "settings", webos: ["Key_webOS_Settings", "Key_webOS_QuickSettings", "Key_webOS_Setting"], icon: "remote-gear-80",
      short: "guide.settings_short", long: "guide.settings_long", placeholder: true },
    { id: "home", qt: ["Key_Home"], webos: ["Key_webOS_Home"], icon: "remote-home-80",
      short: "guide.home_short", long: "guide.home_long", placeholder: true },
    { id: "input", webos: ["Key_webOS_Input", "Key_webOS_InputHub"], icon: "remote-input-80",
      short: "guide.input_short", long: "guide.input_long", placeholder: true },
    { id: "volumeUp", qt: ["Key_VolumeUp"], label: "+",
      short: "guide.volume_up_short", long: "guide.repeats", placeholder: true },
    { id: "volumeDown", qt: ["Key_VolumeDown"], label: "−",
      short: "guide.volume_down_short", long: "guide.repeats", placeholder: true },
    { id: "mute", qt: ["Key_VolumeMute"], icon: "remote-mute-80",
      short: "guide.mute_short", placeholder: true },
    { id: "up", qt: ["Key_Up"], icon: "remote-up-80", short: "guide.arrow_short", long: "guide.repeats", placeholder: true },
    { id: "down", qt: ["Key_Down"], icon: "remote-down-80", short: "guide.arrow_short", long: "guide.repeats", placeholder: true },
    { id: "left", qt: ["Key_Left"], icon: "remote-left-80", short: "guide.arrow_short", long: "guide.repeats", placeholder: true },
    { id: "right", qt: ["Key_Right"], icon: "remote-right-80", short: "guide.arrow_short", long: "guide.repeats", placeholder: true },
    { id: "ok", qt: ["Key_Return", "Key_Enter", "Key_Select"], label: "OK",
      short: "guide.ok_short", long: "guide.ok_long", placeholder: true },
    { id: "back", qt: ["Key_Back", "Key_Escape", "Key_Backspace"], webos: ["Key_webOS_Back"], icon: "remote-back-80",
      short: "guide.back_short", placeholder: true },
    { id: "red", webos: ["Key_webOS_Red"], codes: [0x01200011], dot: "channelRed",
      short: "guide.red_short", placeholder: true },
    { id: "green", webos: ["Key_webOS_Green"], codes: [0x01200012], dot: "channelGreen" },
    { id: "yellow", webos: ["Key_webOS_Yellow"], codes: [0x01200013], dot: "keyYellow" },
    { id: "blue", webos: ["Key_webOS_Blue"], codes: [0x01200014], dot: "channelBlue" },
    { id: "channelUp", qt: ["Key_ChannelUp", "Key_PageUp"], label: "CH+" },
    { id: "channelDown", qt: ["Key_ChannelDown", "Key_PageDown"], label: "CH−" }
];

// Number keys share one entry; the window puts the digit on the key.
var digit = { id: "digit", short: "guide.digit_short", long: "guide.digit_long", placeholder: true };

// Any other key: its own name is unknown, the running app decides.
var other = { id: "other", icon: "remote-80" };

// The entry for a key code. qtKeys and webosKeys resolve names to codes (undefined when this
// TV has no such key).
function find(code, qtKeys, webosKeys) {
    if (code >= 0x30 && code <= 0x39) return { entry: digit, digit: code - 0x30 };
    for (var i = 0; i < keys.length; i++) {
        var entry = keys[i];
        for (var n = 0; n < (entry.qt || []).length; n++) {
            if (qtKeys(entry.qt[n]) === code) return { entry: entry, digit: -1 };
        }
        for (var w = 0; w < (entry.webos || []).length; w++) {
            if (webosKeys(entry.webos[w]) === code) return { entry: entry, digit: -1 };
        }
        if ((entry.codes || []).indexOf(code) >= 0) return { entry: entry, digit: -1 };
    }
    return { entry: other, digit: -1 };
}

// The keys LG's own guide asks the surface manager for (com.webos.app.remotecontrolguide,
// registerAllowedKey with whitelist false), so that the system keys reach the guide.
var allowedKeys = [18874448, 18874452, 18878465, 18878466, 18878467, 18878468, 18878480, 18878481, 18878482,
                   18878483, 18878484, 18878485, 18878486, 18878487, 18878488, 18878489, 18878499, 18878500,
                   18878502, 18878503, 18878504, 18878505, 18878512, 18878514, 18878515, 18878516, 18878517,
                   18878518, 18878519, 18878520, 18878528, 18878529,
                   18874882, 18882627, 18882628, 18882629, 18882630,
                   18874368, 18874469, 18874470, 18874471, 18874480, 18874481];
