
    // novOS: LG's Home stays out of sight while our launcher stands in for it, that is
    // while banner-relay.py runs and its marker is on. While novos-start.sh restarts the
    // interface (/tmp/novos-booting says "on", less than three minutes old, and only in
    // the first 90 s of this container) it stays hidden as well: LG's Home comes up by
    // itself after our restart of surface-manager. Without marker and flag LG's Home
    // shows as always, within a second of the relay ending.
    // During the restart the input apps' own layer is hidden too: LG draws its input
    // banner there. Their picture lies on the video plane and stays visible.
    property bool novosHideHome: false
    property bool novosEarly: true

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

    function novosInput(item) {
        return !!item && /^com\.webos\.app\.(hdmi\d|dp\d|usbc\d|externalinput\.|livetv$)/.test(item.appId || "");
    }

    // LG's Home Hub stays out of sight as well while the relay runs: the relay closes it
    // and opens our hub instead, however it was started.
    function novosLgHub(item) {
        return !!item && item.appId === "com.webos.app.homeconnect";
    }

    function novosUpdateHide() {
        var home = !!root.__surfaceItem && root.__surfaceItem.appId === "com.webos.app.home";
        var booting = root.novosEarly && novosBooting();
        var relay = novosRead("/tmp/novos-banner-active").indexOf("on") === 0;
        root.novosHideHome = (home && (relay || booting)) ||
                            (novosLgHub(root.__surfaceItem) && relay) ||
                            (novosInput(root.__surfaceItem) && booting);
    }

    onSurfaceItemChanged: novosUpdateHide()

    Timer {
        interval: 90000
        running: true
        onTriggered: {
            root.novosEarly = false;
            root.novosUpdateHide();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: !!root.__surfaceItem && (root.__surfaceItem.appId === "com.webos.app.home" ||
                                          root.novosLgHub(root.__surfaceItem) ||
                                          (root.novosEarly && root.novosInput(root.__surfaceItem)))
        onTriggered: root.novosUpdateHide()
    }
