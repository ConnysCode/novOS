.pragma library

// The pictures the TV can show when it switches off, chosen under Oberfläche ›
// Ausschalt-Video and kept as NovosSettings.shutdownScreen. ShutdownScreen.qml plays them,
// the overlay of LG's MasterBrand.qml (shutdown-screen.inc) starts it at power off.
//
// Every entry knows how long it runs: LG's power service waits for the answer until the
// picture is done, and the tiles show the length.
//   id       stored value
//   kind     "lg"      LG's logo; at power off LG's own MasterBrand.qml shows it unchanged
//            "glow"    the boot look on black, dimmed (K3-Shutdown-Schein)
//            "video"   a video the user added, sound only where it has a sound track
//            "image"   a picture the user added
//   duration the whole run in ms (built-in entries)
//   length   how long a video or picture stays, in ms, without the fades (own entries)
// The built-in ones come first, in the order of the tiles (K3-Ausschalt-2); the user's own
// follow from mediaFolder/index.json, which bin/novos-upload.py writes. The release build
// maps the folder to state/media/.
var entries = [
    { id: "novos", kind: "glow", duration: 3000 },
    { id: "lg", kind: "lg", duration: 3000 }     // LG's own times
];

var fallback = "lg";
var mediaFolder = "/tmp/novos-media/";

// The user's own entries, read anew on every call. Windows can read files, not list them.
function ownEntries() {
    try {
        var request = new XMLHttpRequest();
        request.open("GET", "file://" + mediaFolder + "index.json", false);
        request.send();
        var index = JSON.parse(String(request.responseText || "{}"));
        var list = [];
        for (var i = 0; i < (index.entries || []).length; i++) {
            var item = index.entries[i];
            if (!item || !item.id || (item.kind !== "video" && item.kind !== "image")) continue;
            list.push({ id: String(item.id), kind: item.kind, own: true, name: String(item.name || item.id),
                        file: mediaFolder + item.file, still: item.still ? mediaFolder + item.still : "",
                        length: Number(item.length) || 3000, sound: item.sound === true });
        }
        return list;
    } catch (error) {
        return [];
    }
}

// own: the list from ownEntries(), so that callers read the file once.
function entry(id, own) {
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === id) return entries[i];
    }
    var list = own || [];
    for (var j = 0; j < list.length; j++) {
        if (list[j].id === id) return list[j];
    }
    return id === fallback ? entries[1] : entry(fallback, []);
}
