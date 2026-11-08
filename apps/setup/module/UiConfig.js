.pragma library
// What lib/ui needs to know about the setup app, see lib/ui/qmldir.

// Where GlassStyle and I18n keep their values.
var settingsFile = "/tmp/novos-setup.ini";

// The app id I18n and AudioGuide call LG's services with. The preview runs in the
// quick settings window; the packaged app brings its own id.
var serviceAppId = "com.webos.app.quicksettings";

// No texts load on first use.
var lazyTexts = {};
