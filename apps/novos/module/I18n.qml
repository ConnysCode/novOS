pragma Singleton
import QtQuick 2.12
import Qt.labs.settings 1.0
import WebOSServices 1.0

// Texts of every window in the language of the TV. English is the fallback for a
// language or a key that is missing. Keys follow the team convention: a namespace per
// area, then category.content in snake_case, categories in the singular.
//
//     I18n.t("panel", "row.picture")
//     I18n.t("picker", "detail.port_connecting", { port: "HDMI 3" })  // "{port}" in the text
//
// Bindings that call t() follow a change of language by themselves.
QtObject {
    id: i18n

    readonly property var supported: ["en", "de", "es", "fr"]
    property string systemLocale: "en-GB"          // locales.UI of the TV
    // For tests: a language here wins over the TV, "" follows the TV.
    property alias forcedLanguage: values.language
    readonly property string language: {
        var wanted = (forcedLanguage || systemLocale).slice(0, 2).toLowerCase();
        return supported.indexOf(wanted) >= 0 ? wanted : "en";
    }
    // The voice for Audio-Guidance has to match the language of the texts.
    readonly property string speechLocale: {
        if (systemLocale.slice(0, 2).toLowerCase() === language && !forcedLanguage) return systemLocale;
        return { en: "en-GB", de: "de-DE", es: "es-ES", fr: "fr-FR" }[language];
    }
    // For Qt.locale(), which knows names of days and months.
    readonly property string qtLocale: speechLocale.replace("-", "_")

    property var strings: ({})
    property var fallback: ({})

    // Areas of the settings modal, one file per area and language in i18n/settings/<area>/.
    readonly property var settingsAreas: ["picture", "sound", "sources", "games", "network", "interface",
                                          "energy", "accessibility", "parental", "privacy", "system", "info"]

    function loadFile(path) {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl(path), false);
            request.send();
            return JSON.parse(request.responseText);
        } catch (error) {
            return {};
        }
    }

    function load(language) {
        return loadFile("i18n/" + language + ".json");
    }

    // The texts of the settings modal load on their first use: every opening of the panel
    // builds this window anew and should not wait for them. The common texts go to
    // "settings", an area's to "settings_<area>".
    function ensure(table, language, namespace) {
        if (table[namespace] !== undefined || namespace.indexOf("settings") !== 0) return;
        var area = namespace === "settings" ? "common" : namespace.slice(9);
        if (area !== "common" && settingsAreas.indexOf(area) < 0) return;
        table[namespace] = loadFile("i18n/settings/" + area + "/" + language + ".json");
    }

    function t(namespace, key, params) {
        ensure(strings, language, namespace);
        ensure(fallback, "en", namespace);
        var table = strings[namespace];
        var text = table && table[key] !== undefined ? table[key] : undefined;
        if (text === undefined) {
            table = fallback[namespace];
            text = table && table[key] !== undefined ? table[key] : namespace + "/" + key;
        }
        if (params) {
            for (var name in params) text = text.split("{" + name + "}").join(String(params[name]));
        }
        return text;
    }

    onLanguageChanged: strings = load(language)

    Component.onCompleted: {
        fallback = load("en");
        strings = load(language);
        service.call("luna://com.webos.settingsservice", "/getSystemSettings",
                     JSON.stringify({ keys: ["localeInfo"], subscribe: true }));
    }

    property Service service: Service {
        id: service
        appId: "com.webos.app.quicksettings"
        onResponse: {
            var response = JSON.parse(payload);
            var info = response.settings && response.settings.localeInfo;
            if (info && info.locales && info.locales.UI) i18n.systemLocale = info.locales.UI;
        }
    }

    property Settings values: Settings {
        id: values
        fileName: "/tmp/novos-debug.ini"
        property string language: ""
    }
}
