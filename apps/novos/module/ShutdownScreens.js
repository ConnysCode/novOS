.pragma library

// The pictures the TV can show when it switches off, chosen under Oberfläche ›
// Ausschalten and kept as NovosSettings.shutdownScreen. ShutdownScreen.qml plays them,
// the overlay of LG's MasterBrand.qml (shutdown-screen.inc) starts it at power off.
//
// Every entry knows how long it runs (duration, ms): LG's power service waits for the
// answer until the picture is done, and the settings show the length. Later entries the
// user adds bring their own: a video its running time, a picture the time the user sets.
//   id       stored value; its name is "value.shutdown_screen.<id>" in settings_interface
//   kind     "lg"     LG's logo; at power off LG's own MasterBrand.qml shows it unchanged
//            "glow"   the boot look on black, dimmed (K3-Shutdown-Schein)
//   source   who made it, the line under the tile: "detail.shutdown_video.<source>"
// The order is the order of the tiles (K3-Ausschalt-2-Auswahl).
var entries = [
    { id: "novos", kind: "glow", source: "novos", duration: 3000 },
    { id: "lg", kind: "lg", source: "lg", duration: 3000 }     // LG's own times
];

var fallback = "lg";

function entry(id) {
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === id) return entries[i];
    }
    return entry(fallback);
}

function ids() {
    var list = [];
    for (var i = 0; i < entries.length; i++) list.push(entries[i].id);
    return list;
}
