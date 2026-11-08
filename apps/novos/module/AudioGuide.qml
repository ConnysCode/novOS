import QtQuick 2.12
import WebOSServices 1.0
import "."

// Reads aloud what has the focus while LG's Audio-Guidance is on. webOS does not do
// this for a window by itself: LG's own quick menu calls the TTS service for every
// focus change, with the parameters used here (docs/live-glass.md, "Audio-Guidance").
//
// The owner hands over the focus as { context, intro, layer, layerIntro, subject, text, change }:
//   context     key of the page; a new one reads intro, then layerIntro and text
//   layer       key of a popover or modal on top, "" for none; a new one reads
//               layerIntro and text. Leaving it reads only text, not the page again.
//   subject     key of the focused element; a new one reads text
//   change      read instead of text when only the value of the same element changed
// Changes inside the short delay are read together, so that a value arriving right
// after the panel opens does not cut off the page title.
Item {
    id: guide

    property string appId: "com.webos.app.quicksettings"
    property string setting: ""          // option.audioGuidance, read by the guide itself
    readonly property bool speaking: setting === "on"
    property int delay: 200              // LG's value
    // The voice follows the language of the texts, which follow the TV.
    property string language: I18n.speechLocale
    // Closing: nothing new is read. What is being read goes on unless the owner calls
    // stop(), so that the source banner can finish its sentence as it fades.
    property bool quiet: false

    property var current: null
    property string spokenContext: ""
    property string spokenLayer: ""
    property string spokenSubject: ""
    property string spokenText: ""

    function clean(text) {
        return String(text || "").replace(/[„“"«»]/g, "").replace(/ · /g, ", ").replace(/ – /g, ", ")
                                 .replace(/ ?…/g, "").replace(/\s+/g, " ").trim();
    }

    // Parts that are empty fall away.
    function sentence(parts, separator) {
        return parts.map(clean).filter(function (part) { return part !== ""; }).join(separator || ", ");
    }

    function same(a, b) {
        return a.context === b.context && (a.layer || "") === (b.layer || "") && a.subject === b.subject &&
               a.text === b.text && a.intro === b.intro && a.layerIntro === b.layerIntro &&
               a.change === b.change;
    }

    function follow(focus) {
        if (!focus || quiet || (current && same(current, focus))) return;
        current = focus;
        timer.restart();
    }

    // Opening reads the page title again, even when the focus is where it was.
    function reset() {
        spokenContext = "";
        spokenLayer = "";
        spokenSubject = "";
        spokenText = "";
    }

    function stop() {
        timer.stop();
        current = null;
        if (speaking) {
            service.call("luna://com.webos.service.tts", "/stop", JSON.stringify({ appID: appId }));
        }
    }

    function utterance(focus) {
        var text = clean(focus.text);
        var layer = focus.layer || "";
        var layerIntro = layer !== "" ? focus.layerIntro : "";
        if (focus.context !== spokenContext) return sentence([focus.intro, layerIntro, text], ". ");
        if (layer !== spokenLayer) return sentence([layerIntro, text], ". ");
        if (focus.subject !== spokenSubject) return text;
        if (text !== spokenText) return focus.change !== undefined ? clean(focus.change) : text;
        return "";
    }

    function speakNow() {
        var focus = current;
        if (!focus) return;
        var said = utterance(focus);
        spokenContext = focus.context;
        spokenLayer = focus.layer || "";
        spokenSubject = focus.subject;
        spokenText = clean(focus.text);
        if (said === "" || !speaking) return;
        service.call("luna://com.webos.service.tts", "/speak",
                     JSON.stringify({ text: said, clear: true, language: language, appID: appId }));
    }

    function readSetting() {
        service.call("luna://com.webos.settingsservice", "/getSystemSettings",
                     JSON.stringify({ category: "option", keys: ["audioGuidance"], subscribe: true }));
    }

    Component.onCompleted: readSetting()

    Timer {
        id: timer
        interval: guide.delay
        onTriggered: guide.speakNow()
    }

    Service {
        id: service
        appId: guide.appId
        onResponse: {
            if (method !== "/getSystemSettings") return;
            var response = JSON.parse(payload);
            if (response.settings && response.settings.audioGuidance !== undefined) {
                guide.setting = response.settings.audioGuidance;
            }
        }
    }
}
