.pragma library
// What lib/ui needs to know about novOS. Every app that uses lib/ui ships this file
// next to the lib's files; lib/ui has no copy of its own.

// Where GlassStyle and I18n keep their values. The release build replaces the path.
var settingsFile = "/tmp/novos-debug.ini";

// The app id I18n and AudioGuide call LG's services with.
var serviceAppId = "com.webos.app.quicksettings";

// Texts that load on first use, per group: I18n.t("settings", …) reads
// i18n/settings/common/<language>.json, I18n.t("settings_picture", …) reads
// i18n/settings/picture/<language>.json. Every opening of the panel builds its window
// anew and should not wait for them.
var lazyTexts = {
    settings: ["picture", "sound", "sources", "games", "network", "interface",
               "energy", "accessibility", "parental", "privacy", "profile", "system", "info"]
};
