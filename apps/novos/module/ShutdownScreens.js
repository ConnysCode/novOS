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
//            "video"   a video the user added, as frames with its sound (see ownEntries)
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
// A video is a folder of JPEG frames (fps a second, frames in all, full ms) with play.wav,
// the sound of the part that plays; QtMultimedia cannot play video files in surface-manager.
//   start, length  the part that plays, in ms
//   fade           fade to black at the end (else it cuts)
//   zoom, x, y     the framing: zoom 1 shows it whole, x and y (-1 … 1) move the part shown
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
            var entry = { id: String(item.id), kind: item.kind, own: true, name: String(item.name || item.id),
                          length: Number(item.length) || 3000, fade: item.fade !== false,
                          zoom: Number(item.zoom) || 1, x: Number(item.x) || 0, y: Number(item.y) || 0,
                          sound: item.kind === "video" && item.sound === true };
            if (item.kind === "video") {
                entry.folder = mediaFolder + item.folder + "/";
                entry.frames = Number(item.frames) || 1;
                entry.fps = Number(item.fps) || 15;
                entry.full = Number(item.full) || entry.length;
                entry.start = Number(item.start) || 0;
                entry.soundFile = entry.folder + "play.wav";
            } else {
                entry.file = mediaFolder + item.file;
            }
            list.push(entry);
        }
        return list;
    } catch (error) {
        return [];
    }
}

// The picture of frame n of a video entry, or the picture of an image entry.
function frameUrl(entry, n) {
    if (entry.kind === "image") return "file://" + entry.file;
    var number = Math.max(0, Math.min(entry.frames - 1, Math.round(n)));
    var text = "000" + number;
    return "file://" + entry.folder + text.substr(text.length - 4) + ".jpg";
}

// The frame at a time in ms.
function frameAt(entry, ms) {
    return Math.floor(ms * (entry.fps || 15) / 1000);
}

// The entry with changes that are not stored yet (the edit page and its preview).
function withChanges(entry, changes) {
    var copy = {};
    for (var key in entry) copy[key] = entry[key];
    for (var name in changes || {}) copy[name] = changes[name];
    return copy;
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
