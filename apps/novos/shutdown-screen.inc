
    // novOS: the picture when the TV switches off. LG's power service opens this window
    // before the standby and waits for responseOffLogoRequest(true). The entry chosen
    // under Oberfläche › Ausschalten (NovosSettings.shutdownScreen) decides:
    //   "lg", the default, or anything unknown: LG's own animation above, unchanged.
    //   any other entry of ShutdownScreens.js, the user's own videos and pictures too:
    //   module/ShutdownScreen.qml plays it, with sound where the video has a sound track,
    //   and the answer goes out once it is black, so the length follows the entry (a video
    //   its running time). If our file does not load, LG's animation runs after all.
    // build-release.sh fills in the release folder and the settings file.
    property bool novosShutdownStarted: false
    property bool novosShutdownAnswered: false

    function novosSetting(name, fallback) {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", "file:///tmp/novos-debug.ini", false);
            request.send();
            var match = new RegExp("^" + name + "=([A-Za-z0-9_-]+)\\s*$", "m").exec(request.responseText);
            return match ? match[1] : fallback;
        } catch (error) {
            return fallback;
        }
    }

    function novosShutdownChoice() {
        return novosSetting("shutdownScreen", "lg");
    }

    function novosStartLogo() {
        if (novosShutdownStarted) return;
        var choice = novosShutdownChoice();
        if (choice === "lg") {
            logoAnimation.start();
            return;
        }
        novosShutdownStarted = true;
        novosShutdownChosen = choice;
        novosShutdown.active = true;
    }

    property string novosShutdownChosen: "lg"

    function novosShutdownFailed() {
        novosShutdownGuard.stop();
        novosShutdown.visible = false;
        logoAnimation.start();
    }

    function novosShutdownDone() {
        novosShutdownGuard.stop();
        if (novosShutdownAnswered) return;
        novosShutdownAnswered = true;
        if (root.isDevice) root.responseOffLogoRequest(true);
    }

    Loader {
        id: novosShutdown

        anchors.fill: parent
        active: false
        source: "file://@PANEL@/module/ShutdownScreen.qml"
        onStatusChanged: {
            if (status === Loader.Error) root.novosShutdownFailed();
        }
        onLoaded: {
            item.unit = root.width / 1920;
            item.screenId = root.novosShutdownChosen;
            // Own videos play their sound track unless the settings turned it off.
            item.sound = root.novosSetting("shutdownSound", "true") !== "false";
            // An id the release does not know falls back to LG's picture: LG's own file draws it.
            if (item.kind === "lg") {
                root.novosShutdownFailed();
                return;
            }
            item.finished.connect(root.novosShutdownDone);
            novosShutdownGuard.interval = item.duration + 2000;
            novosShutdownGuard.start();
            item.play();
        }
    }

    // Never keeps the power service waiting much longer than the entry runs.
    Timer {
        id: novosShutdownGuard
        onTriggered: root.novosShutdownDone()
    }
