
// novOS: the home key opens our launcher while a test mount runs. Without its marker LG's
// Home comes back, even in a surface-manager that outlives the mount.
// While the interface starts, early in a boot or during our restart, the relay and its
// marker are not there yet; /tmp/novos-booting ("on <seconds>", under three minutes old)
// stands in, as it does for the hidden Home in the compositor.
function novosReadTmp(path) {
    try {
        var request = new XMLHttpRequest();
        request.open("GET", "file://" + path, false);
        request.send();
        return request.responseText;
    } catch (error) {
        return "";
    }
}

function novosLauncherActive() {
    if (novosReadTmp("/tmp/novos-banner-active").indexOf("on") === 0) return true;
    var booting = novosReadTmp("/tmp/novos-booting").split(" ");
    return booting[0] === "on" && Date.now() / 1000 - Number(booting[1]) < 180;
}

// novOS: the home key on our launcher, which lives on the home layer, closes a menu over
// it and the launcher in one go, back to the source. The launcher is asked again, as
// before the home layer: it leaves with its own animation, the source's picture grows
// back to full screen. On LG's Home below there is no source to go back to, and the
// launcher stays. LG's own path would close the launcher on the press and open it
// again on the release; the release is swallowed.
// LG's Home in front, hidden by us, with our launcher closed: LG would hand the key
// to its invisible Home and the screen would stay black. The key opens our launcher.
var novosHomeKeySwallow = false;

function novosHomeKeyOnLauncher(pressed) {
    if (!novosLauncherActive()) return false;
    if (pressed) {
        if (!homeView.visible && !global.isHomeApp(fullscreenView.appId)) return false;
        novosHomeKeySwallow = true;
        if (overlayView.visible) overlayView.close();
        lunaCall.send("com.webos.service.systemUIManager", "/launch", JSON.stringify({"appId": "com.webos.app.store-streamer"}));
        return true;
    }
    if (novosHomeKeySwallow) {
        novosHomeKeySwallow = false;
        return true;
    }
    return false;
}
