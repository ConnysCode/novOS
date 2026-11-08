
    // novOS: LG's grey splash for inputs stays out of sight while our interface runs, that
    // is while banner-relay.py's marker is on, and while novos-start.sh restarts the
    // interface (/tmp/novos-booting says "on" and is less than three minutes old). Our
    // pill shows the switch instead. Splash pictures of apps stay as they are.
    function novosRead(path) {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", "file://" + path, false);
            request.send();
            return request.responseText;
        } catch (error) {
            return "";
        }
    }

    function novosBooting() {
        var parts = novosRead("/tmp/novos-booting").split(" ");
        return parts[0] === "on" && Date.now() / 1000 - Number(parts[1]) < 180;
    }

    function novosHideSplash(appId) {
        if (!/^com\.webos\.app\.(hdmi\d|dp\d|usbc\d|externalinput\.|livetv$)/.test(appId || "")) return false;
        return novosRead("/tmp/novos-banner-active").indexOf("on") === 0 || novosBooting();
    }
