import QtQuick 2.12
import QtQml 2.12
import Qt.labs.settings 1.0
import SystemUIComponent 1.0
import WebOS.Global 1.0
import WebOSServices 1.0
import "module"
import "module/SourceList.js" as SourceList

// Start screen, built to K3-Launcher1b. It replaces LG's Home on the home key. It is an
// overlay above the running source, so that source keeps playing with its sound.
StarfishSystemUIWindow {
    id: rootWindow
    objectName: "starfishSystemUIWindow"
    property bool opened: false
    // The smart home hub shares this window: same home layer, same keys above it.
    property bool hubOpen: false
    property bool hubFromLauncher: false

    function openHub(fromLauncher) {
        if (launcher.backgrounds.length === 0) launcher.loadBackgrounds();
        hubFromLauncher = fromLauncher;
        hubOpen = true;
        hub.open();
    }

    // Back from the hub: to the launcher if it came from there, else out.
    function hubBack() {
        if (hubFromLauncher) {
            hub.stop();
            hubOpen = false;
            launcher.forceActiveFocus();
        } else {
            closeAll();
        }
    }

    // Home, or the hub's last back: everything goes, the launcher with its animation.
    function closeAll() {
        hub.stop();
        hubOpen = false;
        if (hubFromLauncher) {
            launcher.forceActiveFocus();
            launcher.leave();
        } else {
            hubExit.restart();
        }
    }

    Timer {
        id: hubExit
        interval: 260
        onTriggered: {
            launcher.restoreVideo();
            rootWindow.opened = false;
            rootWindow.exit();
        }
    }

    // Menus that open on top of the launcher read this: their glass then shows the
    // launcher's picture, not the video behind it.
    onOpenedChanged: launcherState.open = opened

    Settings {
        id: launcherState
        fileName: "/tmp/novos-launcher-open.ini"
        property bool open: false
    }

    Connections {
        target: rootWindow.lifeCycleStatus
        onLaunch: {
            var params = payload && payload.params || {};
            if (payload && payload.reason === "preload") {
                rootWindow.opened = false;
                rootWindow.exit();
            } else if (rootWindow.opened) {
                if (params.page === "hub" && !rootWindow.hubOpen) rootWindow.openHub(true);
                else if (rootWindow.hubOpen) rootWindow.closeAll();
                else launcher.leave();
            } else {
                webOSShell.setWindowProperty("delayCloseWindowTimeout", 1000);
                webOSShell.setWindowProperty("_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
                rootWindow.show();
                rootWindow.opened = true;
                if (params.page === "hub") rootWindow.openHub(false);
                else launcher.open();
            }
        }
        // Closed from outside, by the system for example: the same animation as leaving
        // by itself. The window may stay up to a second for it.
        onClose: {
            if (rootWindow.hubOpen && !rootWindow.hubFromLauncher) {
                rootWindow.closeAll();
            } else if (rootWindow.opened) {
                rootWindow.hubOpen = false;
                launcher.closeWindow(true);
            } else {
                launcher.restoreVideo();
                rootWindow.exit();
            }
        }
    }

    FocusScope {
        id: launcher
        anchors.fill: parent
        focus: true
        opacity: 0

        readonly property real unit: Math.min(width / 1920, height / 1080)
        readonly property var standardCurve: GlassStyle.curve
        readonly property int tilePitch: 236
        readonly property int appPitch: 168
        readonly property int glideDuration: 240

        property var devices: []
        property string foregroundApp: ""
        readonly property var baseSources: SourceList.build(devices, foregroundApp, false, function (key, params) {
            return I18n.t("source", key, params);
        })
        // The first tile is what ran last: the source or app below, or with Home below
        // the one used before.
        readonly property string leadKey: homeBelow ? store.lastSource : foregroundApp
        readonly property var sources: leadWith(baseSources, leadKey, apps)
        property var apps: []
        readonly property var appTiles: apps.concat([{ all: true, title: I18n.t("launcher", "title.all_apps"), icon: "row-apps" }])
        // Position to tile. The tiles stay where the Repeater made them while one moves,
        // only their places change, so nothing reloads and every step can glide.
        property var appSlots: []
        readonly property var appPositions: {
            var result = [];
            for (var i = 0; i < appSlots.length; i++) result[appSlots[i]] = i;
            return result;
        }
        property bool moving: false
        property bool okDown: false
        property real wiggle: 0
        SequentialAnimation on wiggle {
            running: launcher.moving
            loops: Animation.Infinite
            // One swing in 180 ms, quicker than the jiggle on iOS.
            NumberAnimation { to: 2.2; duration: 45; easing.type: Easing.InOutSine }
            NumberAnimation { to: -2.2; duration: 90; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 45; easing.type: Easing.InOutSine }
        }
        onMovingChanged: if (!moving) wiggle = 0
        property int row: 0
        property int sourceIndex: 0
        property int appIndex: 0
        property int sourceScroll: 0
        property int appScroll: 0
        property string signalFormat: ""
        property var backgrounds: []
        property int backgroundIndex: -1
        property int activeBackground: 0
        property date now: new Date()
        property string videoContext: ""
        property bool videoShrunk: false
        property bool videoInPreview: false
        property bool closingVideo: false
        property bool opening: false
        property bool foregroundKnown: false
        property real morph: 0                 // 0 is full screen, 1 is the preview
        property real frameAlpha: 0
        Behavior on frameAlpha { NumberAnimation { duration: 120 } }
        property real heroProgress: 0
        property int heroStage: 0              // 0 at rest, 1 leaving, 2 arriving
        property int heroSide: -1
        property int pendingSide: 1
        // Along the row the hero moves sideways, between the rows up and down.
        property bool heroVertical: false
        property bool pendingVertical: false
        readonly property real heroStagger: 0.11
        readonly property real heroExitTravel: 44 * unit
        readonly property real heroEntryTravel: 90 * unit
        property var shownHero: ({ label: "", title: "", detail: "", action: "", live: false, still: "" })
        readonly property bool appsOpen: row === 1
        readonly property var focusedSource: sources[sourceIndex] || ({ title: "", detail: "", icon: "source-box" })
        readonly property var focusedApp: appTiles[appSlots[appIndex]] || ({ title: "" })
        // The running source whose picture can shrink into the preview. An app only
        // counts with a video of its own.
        readonly property var running: {
            for (var i = 0; i < sources.length; i++) {
                if (sources[i].running && (!sources[i].isApp || videoContext !== "")) return sources[i];
            }
            return null;
        }
        property bool videoKnown: false
        readonly property bool homeBelow: foregroundApp === "" || foregroundApp === "com.webos.app.home"

        readonly property string heroLabel: moving ? I18n.t("launcher", "label.moving") :
                                            appsOpen ? I18n.t("launcher", "label.app") :
                                            focusedSource.running ? I18n.t("launcher", "label.running_now") :
                                            I18n.t("launcher", "label.source")
        readonly property string heroTitle: appsOpen ? focusedApp.title : focusedSource.title
        readonly property string heroDetail: {
            if (moving) return I18n.t("launcher", "detail.moving");
            if (appsOpen) return focusedApp.all ? I18n.t("launcher", "detail.all_apps") : "";
            if (focusedSource.running && signalFormat !== "" && focusedSource.port) {
                return I18n.t("launcher", "detail.port_format", { port: focusedSource.port, format: signalFormat });
            }
            return focusedSource.detail;
        }
        readonly property string heroAction: moving ? I18n.t("global", "done") :
                                             appsOpen || focusedSource.isApp && !focusedSource.running ? I18n.t("global", "open") :
                                             focusedSource.running && focusedSource.isApp ? I18n.t("launcher", "action.back_to_app") :
                                             focusedSource.running ? I18n.t("launcher", "action.back_to_source") :
                                             focusedSource.off ? I18n.t("launcher", "action.turn_on_and_switch") :
                                             I18n.t("launcher", "action.switch")
        readonly property string previewStill: !appsOpen && !focusedSource.running && !focusedSource.off &&
                                               focusedSource.appId ? liveStillPath(focusedSource.appId) : ""
        readonly property bool previewLive: !appsOpen && focusedSource.running === true && running !== null

        function leadWith(list, key, appList) {
            if (key === "") return list;
            for (var i = 0; i < list.length; i++) {
                if (list[i].appId === key) return [list[i]].concat(list.slice(0, i), list.slice(i + 1));
            }
            for (var j = 0; j < appList.length; j++) {
                if (appList[j].id !== key) continue;
                return [{ appId: key, isApp: true, title: appList[j].title, iconPath: appList[j].iconPath,
                          detail: I18n.t("source", "detail.app"), running: key === foregroundApp }].concat(list);
            }
            return list;
        }

        function liveStillPath(appId) {
            return "/tmp/novos-still-" + appId + ".jpg";
        }

        function open() {
            opacity = 0;
            moving = false;
            okDown = false;
            row = 0;
            sourceIndex = 0;
            appIndex = 0;
            sourceScroll = 0;
            appScroll = 0;
            videoKnown = false;
            openTimeout.restart();
            forceActiveFocus();
            loadBackgrounds();
            service.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
            service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
            service.call("luna://com.webos.applicationManager", "/listLaunchPoints", "{}");
            service.call("luna://com.webos.service.videooutput", "/getStatus", "{}");
        }

        // LG's Home lies below when nothing else runs, so there is nothing to return to.
        function leave() {
            if (homeBelow) return;
            closeWindow(true);
        }

        // The window waits for a sharp frame of the source, then that frame shrinks into the
        // preview on the GPU. The video plane jumps behind it and only shows once it stands.
        function startOpening() {
            if (opening) return;
            opening = true;
            openTimeout.stop();
            frameAlpha = 1;
            fadeIn.restart();
            if (running && preview.hasFrame) {
                morph = 0;
                runMorph(1, 620);
            } else {
                morph = 1;
                settleVideo();
            }
        }

        function runMorph(target, duration) {
            morphAnimation.stop();
            morphAnimation.to = target;
            morphAnimation.duration = duration;
            morphAnimation.start();
        }

        function settleVideo() {
            if (videoContext === "" || !running || !rootWindow.opened || closingVideo) return;
            if (!videoShrunk) {
                videoShrunk = true;
                setVideoWindow(false);
            }
            revealTimer.restart();
        }

        function setVideoWindow(full) {
            service.call("luna://com.webos.service.videooutput", "/display/setDisplayWindow", JSON.stringify({
                context: videoContext, fullScreen: full,
                displayOutput: full ? { x: 0, y: 0, width: 1920, height: 1080 } :
                                      { x: 1248, y: 203, width: 576, height: 324 } }));
        }

        function revealVideo() {
            videoInPreview = videoShrunk && shownHero.live && heroStage === 0 && morph >= 1 && !closingVideo;
        }

        function restoreVideo() {
            revealTimer.stop();
            videoInPreview = false;
            if (!videoShrunk) return;
            videoShrunk = false;
            setVideoWindow(true);
        }

        // Going back to the running source grows its frame to full screen. The plane is
        // there already. Everything else simply fades, the picture is about to change anyway.
        function closeWindow(growVideo) {
            if (fadeOut.running) return;
            if (growVideo && preview.hasFrame && running) {
                closingVideo = true;
                restoreVideo();
                runMorph(0, 480);
            } else {
                restoreVideo();
                frameAlpha = 0;
            }
            fadeOut.restart();
        }

        function loadBackgrounds() {
            var request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("launcher/backgrounds/index.json"), false);
            request.send();
            backgrounds = shuffled(JSON.parse(request.responseText));
            backgroundIndex = 0;
            showBackground();
        }

        function shuffled(list) {
            var result = list.slice();
            for (var i = result.length - 1; i > 0; i--) {
                var other = Math.floor(Math.random() * (i + 1));
                var entry = result[i];
                result[i] = result[other];
                result[other] = entry;
            }
            return result;
        }

        function backgroundUrl(index) {
            return Qt.resolvedUrl("launcher/backgrounds/" + backgrounds[index % backgrounds.length].file);
        }

        // Each picture names its author and licence, as CC BY asks.
        function backgroundCredit(index) {
            if (backgrounds.length === 0) return "";
            return backgrounds[Math.max(0, index) % backgrounds.length].credit || "";
        }

        function showBackground() {
            var next = 1 - activeBackground;
            var image = next === 0 ? backgroundA : backgroundB;
            image.source = backgroundUrl(backgroundIndex);
            if (image.status === Image.Ready) activeBackground = next;
        }

        // The focus always starts on the first tile, the source that ran last.
        function placeFocus() {
            if (sources.length === 0) return;
            sourceIndex = 0;
            keepInView();
        }

        function remember(appId) {
            if (appId && appId !== "com.webos.app.home") store.lastSource = appId;
        }

        function keepInView() {
            var width = 1808;
            var left = 28 + sourceIndex * tilePitch;
            if (left + 224 - sourceScroll > width - 28) sourceScroll = left + 224 + 28 - width;
            else if (left - sourceScroll < 28) sourceScroll = left - 28;
            var appLeft = 28 + appIndex * appPitch;
            if (appLeft + 156 - appScroll > width - 120) appScroll = appLeft + 156 + 120 - width;
            else if (appLeft - appScroll < 28) appScroll = appLeft - 28;
        }

        function move(step) {
            if (moving) {
                shiftApp(step);
                return;
            }
            if (appsOpen) appIndex = Math.max(0, Math.min(appTiles.length - 1, appIndex + step));
            else sourceIndex = Math.max(0, Math.min(sources.length - 1, sourceIndex + step));
            keepInView();
            changeHero(step);
        }

        // Holding OK on an app picks it up. It then trades places with its neighbours,
        // All apps stays at the end. OK or Back puts it down and keeps the order.
        function startMoving() {
            if (!appsOpen || focusedApp.all) return;
            moving = true;
            refreshHero();
        }

        function shiftApp(step) {
            var target = appIndex + step;
            if (target < 0 || target >= apps.length) return;
            var slots = appSlots.slice();
            var tile = slots[appIndex];
            slots[appIndex] = slots[target];
            slots[target] = tile;
            appSlots = slots;
            appIndex = target;
            keepInView();
        }

        function finishMoving() {
            moving = false;
            var order = [];
            for (var i = 0; i < appSlots.length; i++) {
                var app = appTiles[appSlots[i]];
                if (app && !app.all) order.push(app.id);
            }
            store.appOrder = JSON.stringify(order);
            refreshHero();
        }

        function isOkKey(key) {
            return Remote.isOk(key);
        }

        function moveRow(next) {
            if (next === row) return;
            var step = next - row;
            row = next;
            changeHero(step, true);
        }

        // The text and the preview leave against the direction of travel, one after the
        // other, and the new ones follow from the other side. New content only appears
        // once the old has left.
        function changeHero(step, vertical) {
            pendingSide = step > 0 ? 1 : -1;
            pendingVertical = vertical === true;
            revealTimer.stop();
            videoInPreview = false;
            if (heroStage === 1) return;
            heroEntry.stop();
            if (heroStage === 2 && heroProgress < 0.3) {
                // Barely on its way in: nothing has to leave first.
                showHero();
                heroSide = pendingSide;
                heroVertical = pendingVertical;
                startEntry();
            } else {
                heroSide = -pendingSide;
                heroVertical = pendingVertical;
                heroStage = 1;
                heroProgress = 0;
                heroExit.start();
            }
        }

        function startEntry() {
            heroStage = 2;
            heroProgress = 0;
            heroEntry.start();
        }

        // With nothing running there is no frame to wait for.
        function dataCheck() {
            if (foregroundKnown && videoKnown && devices.length > 0 && !running) startOpening();
        }

        function showHero() {
            shownHero = { label: heroLabel, title: heroTitle, detail: heroDetail, action: heroAction,
                          live: previewLive, still: previewStill };
        }

        // Late details such as the format need no transition.
        function refreshHero() {
            if (heroStage === 0) showHero();
        }

        // Each piece runs its own curve, a little later than the one before.
        function heroTime(index) {
            return Math.max(0, Math.min(1, heroProgress * (1 + heroStagger * 4) - heroStagger * index));
        }

        // Accelerates away, then arrives like a damped spring with a slight overshoot.
        function heroOffset(index) {
            var time = heroTime(index);
            if (heroStage === 1) return heroSide * Math.pow(time, 2.4) * heroExitTravel;
            if (heroStage === 2) return heroSide * Math.exp(-7 * time) * Math.cos(7 * time) * heroEntryTravel;
            return 0;
        }

        function heroShiftX(index) {
            return heroVertical ? 0 : heroOffset(index);
        }

        function heroShiftY(index) {
            return heroVertical ? heroOffset(index) : 0;
        }

        function heroAlpha(index) {
            var time = heroTime(index);
            if (heroStage === 1) return 1 - Math.pow(time, 1.6);
            if (heroStage === 2) return Math.min(1, time * 2.4);
            return 1;
        }

        function activate() {
            // LG's Home Hub tile opens our hub instead.
            if (appsOpen && focusedApp.id === "com.webos.app.homeconnect") {
                rootWindow.openHub(true);
                return;
            }
            remember(appsOpen ? focusedApp.id : focusedSource.appId);
            if (appsOpen) {
                if (focusedApp.all) {
                    service.call("luna://com.webos.service.systemUIManager", "/launch",
                                 JSON.stringify({ appId: "com.webos.app.quicksettings", params: { page: "apps" } }));
                } else {
                    service.call("luna://com.webos.applicationManager", "/launch",
                                 JSON.stringify({ id: focusedApp.id }));
                }
                closeWindow(false);
            } else if (focusedSource.running) {
                closeWindow(true);
            } else if (focusedSource.appId) {
                service.call("luna://com.webos.applicationManager", "/launch",
                             NovosSettings.launchRequest(focusedSource.appId));
                closeWindow(false);
            }
        }

        function isBackKey(key) {
            return Remote.isBack(key);
        }

        function updateFormat(video) {
            if (!video || !video.connected) return;
            if (video.appId === foregroundApp || foregroundApp === "") videoContext = video.context || "";
            var height = video.height;
            var name = height >= 4000 ? "8K" : height >= 2000 ? "4K" : height > 0 ? height + "p" : "";
            signalFormat = name !== "" && video.frameRate > 0 ? name + " · " + Math.round(video.frameRate) + " Hz" : "";
        }

        // The saved order first, apps it does not know yet behind in LG's order.
        function updateApps(points) {
            var result = [];
            (points || []).forEach(function (point) {
                if (point.id === "com.webos.app.home" || point.id === "com.webos.app.discovery" || !point.title) return;
                if (point.id.indexOf("com.webos.app.hdmi") === 0) return;
                result.push({ id: point.id, lgIndex: result.length,
                              title: point.id === "com.webos.app.homeconnect" ? I18n.t("hub", "title.smart_home") : point.title,
                              iconPath: point.largeIcon || point.icon || "" });
            });
            var order = [];
            try {
                order = JSON.parse(store.appOrder || "[]");
            } catch (error) {
                order = [];
            }
            function rank(app) {
                var place = order.indexOf(app.id);
                return place >= 0 ? place : order.length + app.lgIndex;
            }
            result.sort(function (a, b) { return rank(a) - rank(b); });
            var slots = [];
            for (var i = 0; i <= result.length; i++) slots.push(i);
            apps = result;
            appSlots = slots;
        }

        // Names from the locale, word order from the texts. The line starts with a capital.
        function dateLabel(date) {
            var locale = Qt.locale(I18n.qtLocale);
            var text = I18n.t("launcher", "label.date", {
                weekday: locale.dayName(date.getDay(), Locale.LongFormat),
                day: date.getDate(),
                month: locale.monthName(date.getMonth(), Locale.LongFormat)
            });
            return text.charAt(0).toUpperCase() + text.slice(1);
        }

        // On an app OK acts on release, a hold picks the app up instead.
        Keys.onPressed: {
            if (isOkKey(event.key)) {
                if (!event.isAutoRepeat && !okDown) {
                    okDown = true;
                    if (moving) finishMoving();
                    else if (appsOpen && !focusedApp.all) holdTimer.restart();
                    else activate();
                }
            } else if (event.key === Qt.Key_Left) move(-1);
            else if (event.key === Qt.Key_Right) move(1);
            else if (moving && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                // The app stays in its row while it moves.
            } else if (event.key === Qt.Key_Down) moveRow(1);
            else if (event.key === Qt.Key_Up) moveRow(0);
            else if (!isBackKey(event.key)) {
                return;
            }
            event.accepted = true;
        }

        Keys.onReleased: {
            if (isOkKey(event.key)) {
                if (!event.isAutoRepeat) {
                    okDown = false;
                    if (holdTimer.running) {
                        holdTimer.stop();
                        activate();
                    }
                }
                event.accepted = true;
            } else if (isBackKey(event.key)) {
                if (moving) finishMoving();
                else leave();
                event.accepted = true;
            }
        }

        Timer {
            id: holdTimer
            interval: 600
            onTriggered: if (launcher.okDown) launcher.startMoving()
        }

        // /tmp for previews and test mounts; the install's build moves it to state/.
        Settings {
            id: store
            fileName: "/tmp/novos-launcher.ini"
            property string lastSource: ""
            property string appOrder: ""
        }

        // While the video plane is small a beat goes out every second. Should this
        // window die meanwhile, the install's supervisor grows the plane back after 5 s.
        Settings {
            id: videoBeat
            fileName: "/tmp/novos-launcher-video.ini"
            property bool shrunk: false
            property string context: ""
            property real beat: 0
        }

        Timer {
            interval: 1000
            repeat: true
            triggeredOnStart: true
            running: launcher.videoShrunk
            onRunningChanged: if (!running) videoBeat.shrunk = false
            onTriggered: {
                videoBeat.context = launcher.videoContext;
                videoBeat.beat = Date.now();
                videoBeat.shrunk = true;
            }
        }

        NumberAnimation {
            id: fadeIn
            target: launcher
            property: "opacity"
            to: 1
            duration: 360
        }

        NumberAnimation {
            id: morphAnimation
            target: launcher
            property: "morph"
            easing.type: Easing.Bezier
            easing.bezierCurve: launcher.standardCurve
            onStopped: {
                // The curve ends a hair below its target.
                if (to !== 1 || launcher.morph < 0.99) return;
                launcher.morph = 1;
                launcher.settleVideo();
            }
        }

        // The plane needs a moment after its jump before it can show.
        Timer {
            id: revealTimer
            interval: 170
            onTriggered: launcher.revealVideo()
        }

        // The window never waits long for its first frame.
        Timer {
            id: openTimeout
            interval: 800
            onTriggered: launcher.startOpening()
        }

        SequentialAnimation {
            id: fadeOut
            NumberAnimation { target: launcher; property: "opacity"; to: 0; duration: 480 }
            // Only now the plane beneath shows, the frame has grown to its size.
            NumberAnimation { target: launcher; property: "frameAlpha"; to: 0; duration: 140 }
            ScriptAction {
                script: {
                    launcher.restoreVideo();
                    rootWindow.opened = false;
                    rootWindow.exit();
                }
            }
        }

        Service {
            id: service
            appId: "com.webos.app.quicksettings"
            onResponse: {
                var response = JSON.parse(payload);
                if (method === "/getAllInputStatus") {
                    launcher.devices = response.devices || [];
                    launcher.placeFocus();
                    launcher.refreshHero();
                } else if (method === "/getForegroundAppInfo") {
                    launcher.foregroundApp = response.appId || "";
                    launcher.foregroundKnown = true;
                    if (!launcher.homeBelow) launcher.remember(launcher.foregroundApp);
                    launcher.placeFocus();
                    launcher.refreshHero();
                    launcher.dataCheck();
                } else if (method === "/getStatus") {
                    launcher.updateFormat(response.video && response.video[0]);
                    launcher.videoKnown = true;
                    launcher.refreshHero();
                    launcher.dataCheck();
                } else if (method === "/listLaunchPoints") {
                    launcher.updateApps(response.launchPoints);
                    launcher.refreshHero();
                }
            }
        }

        Timer {
            interval: 10000
            repeat: true
            running: rootWindow.opened
            onTriggered: launcher.now = new Date()
        }

        // The pictures run through on their own, whatever has the focus.
        Timer {
            interval: 30000
            repeat: true
            running: rootWindow.opened && launcher.backgrounds.length > 1
            onTriggered: {
                launcher.backgroundIndex++;
                launcher.showBackground();
            }
        }

        NumberAnimation {
            id: heroExit
            target: launcher
            property: "heroProgress"
            from: 0
            to: 1
            duration: 210
            onStopped: {
                if (launcher.heroStage !== 1 || launcher.heroProgress < 1) return;
                launcher.showHero();
                launcher.heroSide = launcher.pendingSide;
                launcher.heroVertical = launcher.pendingVertical;
                launcher.startEntry();
            }
        }

        NumberAnimation {
            id: heroEntry
            target: launcher
            property: "heroProgress"
            from: 0
            to: 1
            duration: 760
            onStopped: {
                if (launcher.heroProgress < 1) return;
                launcher.heroStage = 0;
                if (launcher.shownHero.live) revealTimer.restart();
            }
        }

        // The picture is fully opaque, so nothing of the source shines through.
        Item {
            id: backdrop
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#02040a"
            }

            Image {
                id: backgroundA
                anchors.fill: parent
                asynchronous: true
                cache: false
                sourceSize: Qt.size(1920, 1080)
                fillMode: Image.PreserveAspectCrop
                opacity: launcher.activeBackground === 0 ? 1 : 0
                onStatusChanged: if (status === Image.Ready && source == launcher.backgroundUrl(launcher.backgroundIndex)) launcher.activeBackground = 0
                Behavior on opacity { NumberAnimation { duration: 1600 } }
            }

            Image {
                id: backgroundB
                anchors.fill: parent
                asynchronous: true
                cache: false
                sourceSize: Qt.size(1920, 1080)
                fillMode: Image.PreserveAspectCrop
                opacity: launcher.activeBackground === 1 ? 1 : 0
                onStatusChanged: if (status === Image.Ready && source == launcher.backgroundUrl(launcher.backgroundIndex)) launcher.activeBackground = 1
                Behavior on opacity { NumberAnimation { duration: 1600 } }
            }

            // The nav lies on the dimmed picture, so its glass samples the scrims too.
            BackdropScrim {
                anchors.fill: parent
                unit: launcher.unit
            }
        }

        // The glass hides the backdrop it blurs, so the pictures are drawn again here,
        // straight from their textures, as they are.
        Rectangle {
            anchors.fill: parent
            color: "#02040a"
        }

        ShaderEffect {
            anchors.fill: parent
            property variant source: backgroundA
            opacity: backgroundA.opacity
            visible: opacity > 0
        }

        ShaderEffect {
            anchors.fill: parent
            property variant source: backgroundB
            opacity: backgroundB.opacity
            visible: opacity > 0
        }

        ImageGlass {
            id: navGlass
            sourceItem: backdrop
            unit: launcher.unit
            area: Qt.rect(56 * launcher.unit, 680 * launcher.unit, 1808 * launcher.unit, 344 * launcher.unit)
            visible: false
        }

        BackdropScrim {
            anchors.fill: parent
            unit: launcher.unit
        }

        Column {
            anchors.right: parent.right
            anchors.rightMargin: 96 * launcher.unit
            y: 64 * launcher.unit
            spacing: 2 * launcher.unit

            Text {
                anchors.right: parent.right
                text: Qt.formatTime(launcher.now, "hh:mm")
                color: "#ffffff"
                font.family: GlassStyle.titleFont
                font.pixelSize: 32 * launcher.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                anchors.right: parent.right
                text: launcher.dateLabel(launcher.now)
                color: "#c7ffffff"
                font.family: GlassStyle.valueFont
                font.pixelSize: 18 * launcher.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        Item {
            x: 96 * launcher.unit
            width: (launcher.appsOpen ? 1400 : 980) * launcher.unit
            height: (launcher.appsOpen ? 680 : 730) * launcher.unit

            Behavior on height {
                NumberAnimation {
                    duration: launcher.glideDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: launcher.standardCurve
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width

                Text {
                    text: launcher.shownHero.label.toUpperCase()
                    opacity: launcher.heroAlpha(0)
                    transform: Translate { x: launcher.heroShiftX(0); y: launcher.heroShiftY(0) }
                    color: GlassStyle.textSecondary
                    font.family: GlassStyle.titleFont
                    font.pixelSize: 18 * launcher.unit
                    font.letterSpacing: 1.08 * launcher.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item { width: 1; height: 10 * launcher.unit }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: launcher.shownHero.title
                    opacity: launcher.heroAlpha(1)
                    transform: Translate { x: launcher.heroShiftX(1); y: launcher.heroShiftY(1) }
                    color: "#ffffff"
                    font.family: GlassStyle.titleFont
                    font.pixelSize: 72 * launcher.unit
                    font.letterSpacing: -1.8 * launcher.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item { width: 1; height: 10 * launcher.unit; visible: launcher.shownHero.detail !== "" }

                Text {
                    width: parent.width
                    visible: launcher.shownHero.detail !== ""
                    elide: Text.ElideRight
                    text: launcher.shownHero.detail
                    opacity: launcher.heroAlpha(2)
                    transform: Translate { x: launcher.heroShiftX(2); y: launcher.heroShiftY(2) }
                    color: "#d1ffffff"
                    font.family: GlassStyle.valueFont
                    font.pixelSize: 26 * launcher.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item { width: 1; height: 24 * launcher.unit }

                Row {
                    spacing: 12 * launcher.unit
                    opacity: launcher.heroAlpha(3)
                    transform: Translate { x: launcher.heroShiftX(3); y: launcher.heroShiftY(3) }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: okLabel.width + 20 * launcher.unit
                        height: 30 * launcher.unit
                        radius: 9 * launcher.unit
                        color: "transparent"
                        border.width: 1.5 * launcher.unit
                        border.color: "#8cffffff"

                        Text {
                            id: okLabel
                            anchors.centerIn: parent
                            text: "OK"     // the label printed on the remote's key
                            color: "#ffffff"
                            font.family: GlassStyle.titleFont
                            font.pixelSize: 16 * launcher.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: launcher.shownHero.action
                        color: "#d1ffffff"
                        font.family: GlassStyle.rowFont
                        font.pixelSize: 20 * launcher.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 96 * launcher.unit
            y: (launcher.appsOpen ? 634 : 684) * launcher.unit
            text: I18n.t("launcher", "label.image_credit", { credit: launcher.backgroundCredit(launcher.backgroundIndex) })
            color: "#9effffff"
            font.family: GlassStyle.rowFont
            font.pixelSize: 16 * launcher.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        GlassCard {
            id: nav
            x: 56 * launcher.unit
            y: launcher.height - height - 56 * launcher.unit
            width: 1808 * launcher.unit
            height: (launcher.appsOpen ? 344 : 294) * launcher.unit
            unit: launcher.unit
            backdrop: navGlass.texture
            glassShader: GlassStyle.glassShader
            backdropMargin: navGlass.margin
            backdropArea: navGlass.area
            hasBackdrop: 1
            shadow: "shadow-panel"

            Text {
                x: 36 * launcher.unit
                y: 24 * launcher.unit
                height: 20 * launcher.unit
                verticalAlignment: Text.AlignVCenter
                text: I18n.t("launcher", "label.sources")
                color: GlassStyle.textMuted
                font.family: GlassStyle.titleFont
                font.pixelSize: 16 * launcher.unit
                font.letterSpacing: 1 * launcher.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            // Large source tiles.
            Item {
                y: 60 * launcher.unit
                width: parent.width
                height: 184 * launcher.unit
                opacity: launcher.appsOpen ? 0 : 1
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Item {
                    x: -launcher.sourceScroll * launcher.unit

                    Behavior on x {
                        NumberAnimation {
                            duration: GlassStyle.focusDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: launcher.standardCurve
                        }
                    }

                    Rectangle {
                        x: (28 + launcher.sourceIndex * launcher.tilePitch) * launcher.unit
                        width: 224 * launcher.unit
                        height: 184 * launcher.unit
                        radius: 32 * launcher.unit
                        scale: GlassStyle.focusScale
                        color: GlassStyle.focusFill
                        antialiasing: true

                        Behavior on x {
                            NumberAnimation {
                                duration: GlassStyle.focusDuration
                                easing.type: Easing.Bezier
                                easing.bezierCurve: launcher.standardCurve
                            }
                        }
                    }

                    Repeater {
                        model: launcher.sources

                        SourceTile {
                            x: (28 + index * launcher.tilePitch) * launcher.unit
                            width: 224 * launcher.unit
                            height: 184 * launcher.unit
                            unit: launcher.unit
                            titleFont: GlassStyle.titleFont
                            valueFont: GlassStyle.valueFont
                            source: modelData
                            focused: index === launcher.sourceIndex
                        }
                    }
                }
            }

            // The sources step back to a row of chips while the apps are open.
            Row {
                x: 36 * launcher.unit
                y: 54 * launcher.unit
                spacing: 10 * launcher.unit
                opacity: launcher.appsOpen ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Repeater {
                    model: launcher.sources

                    GlassControl {
                        width: chipRow.width + 36 * launcher.unit
                        height: 56 * launcher.unit
                        unit: launcher.unit
                        radius: 28
                        fill: "#1affffff"

                        Row {
                            id: chipRow
                            x: 16 * launcher.unit
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10 * launcher.unit

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28 * launcher.unit
                                height: 28 * launcher.unit
                                smooth: true
                                visible: modelData.isApp !== true
                                opacity: modelData.off === true ? 0.55 : 1
                                source: modelData.isApp ? "" : Qt.resolvedUrl("module/icons/" + modelData.icon + ".png")
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28 * launcher.unit
                                height: 28 * launcher.unit
                                cornerRadius: 8 * launcher.unit
                                visible: modelData.isApp === true
                                source: modelData.isApp ? modelData.iconPath : ""
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.title
                                color: "#ffffff"
                                font.family: GlassStyle.titleFont
                                font.pixelSize: 18 * launcher.unit
                                font.hintingPreference: Font.PreferNoHinting
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.running === true
                                width: 8 * launcher.unit
                                height: width
                                radius: width / 2
                                color: GlassStyle.accent
                            }
                        }
                    }
                }
            }

            Text {
                x: 36 * launcher.unit
                y: 132 * launcher.unit
                height: 20 * launcher.unit
                verticalAlignment: Text.AlignVCenter
                visible: launcher.appsOpen
                text: I18n.t("launcher", "label.apps")
                color: GlassStyle.textMuted
                font.family: GlassStyle.titleFont
                font.pixelSize: 16 * launcher.unit
                font.letterSpacing: 1 * launcher.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            // Hint below the source tiles.
            Row {
                x: 36 * launcher.unit
                y: 256 * launcher.unit
                height: 24 * launcher.unit
                spacing: 8 * launcher.unit
                opacity: launcher.appsOpen ? 0 : 1
                visible: opacity > 0

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18 * launcher.unit
                    height: 18 * launcher.unit
                    rotation: 90
                    opacity: 0.6
                    smooth: true
                    source: Qt.resolvedUrl("module/icons/chevron-18.png")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.t("launcher", "hint.apps")
                    color: GlassStyle.textMuted
                    font.family: GlassStyle.titleFont
                    font.pixelSize: 16 * launcher.unit
                    font.letterSpacing: 1 * launcher.unit
                    font.hintingPreference: Font.PreferNoHinting
                }
            }

            // Room above and below, so a lifted, wiggling app is not cut off. While the
            // card glides to its new height, the row ends with the card, never below it.
            Item {
                y: 152 * launcher.unit
                width: parent.width
                height: Math.max(0, Math.min(180 * launcher.unit, nav.height - y))
                opacity: launcher.appsOpen ? 1 : 0
                visible: opacity > 0
                clip: true

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Item {
                    x: -launcher.appScroll * launcher.unit
                    y: 12 * launcher.unit

                    Behavior on x {
                        NumberAnimation {
                            duration: GlassStyle.focusDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: launcher.standardCurve
                        }
                    }

                    Rectangle {
                        x: (28 + launcher.appIndex * launcher.appPitch) * launcher.unit
                        width: 156 * launcher.unit
                        height: 156 * launcher.unit
                        radius: 28 * launcher.unit
                        color: GlassStyle.focusFill
                        antialiasing: true
                        rotation: launcher.wiggle
                        scale: launcher.moving ? 1.06 : 1

                        Behavior on scale { NumberAnimation { duration: 160 } }

                        Behavior on x {
                            NumberAnimation {
                                duration: GlassStyle.focusDuration
                                easing.type: Easing.Bezier
                                easing.bezierCurve: launcher.standardCurve
                            }
                        }
                    }

                    Repeater {
                        model: launcher.appTiles

                        Item {
                            readonly property int position: launcher.appPositions[index] !== undefined ?
                                                            launcher.appPositions[index] : index
                            readonly property bool focused: launcher.appsOpen && position === launcher.appIndex
                            x: (28 + position * launcher.appPitch) * launcher.unit
                            width: 156 * launcher.unit
                            height: 156 * launcher.unit
                            rotation: focused ? launcher.wiggle : 0
                            scale: focused && launcher.moving ? 1.06 : 1

                            Behavior on x {
                                NumberAnimation {
                                    duration: GlassStyle.focusDuration
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: launcher.standardCurve
                                }
                            }
                            Behavior on scale { NumberAnimation { duration: 160 } }

                            AppIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 12 * launcher.unit
                                width: 96 * launcher.unit
                                height: 96 * launcher.unit
                                cornerRadius: 24 * launcher.unit
                                visible: !modelData.all
                                source: modelData.iconPath ? modelData.iconPath : ""
                            }

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 42 * launcher.unit
                                visible: modelData.all === true
                                source: modelData.all ? Qt.resolvedUrl("module/icons/row-apps" +
                                                                       (parent.focused ? "-dark.png" : ".png")) : ""
                            }

                            Text {
                                x: 8 * launcher.unit
                                y: 118 * launcher.unit
                                width: parent.width - 16 * launcher.unit
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modelData.title
                                color: parent.focused ? GlassStyle.focusText : "#ffffff"
                                font.family: GlassStyle.titleFont
                                font.pixelSize: 17 * launcher.unit
                                font.hintingPreference: Font.PreferNoHinting
                            }
                        }
                    }
                }
            }
        }

    }

    // Above the fading launcher: while it zooms, the picture has to stay opaque.
    LivePreview {
        id: preview
        x: 1248 * launcher.morph * launcher.unit
        y: 203 * launcher.morph * launcher.unit
        width: (1920 - 1344 * launcher.morph) * launcher.unit
        height: (1080 - 756 * launcher.morph) * launcher.unit
        unit: launcher.unit
        live: launcher.shownHero.live || launcher.morph < 1
        capturing: rootWindow.opened && !rootWindow.hubOpen && launcher.running !== null && !launcher.closingVideo
        holeOpen: launcher.videoInPreview
        still: launcher.shownHero.still
        shadowShader: GlassStyle.shadowShader
        planeSmall: launcher.videoShrunk
        motion: launcher.frameAlpha * (launcher.morph < 1 ? 1 : launcher.heroAlpha(4))
        roundness: launcher.morph
        onFrameReady: launcher.startOpening()
        transform: Translate { x: launcher.morph < 1 ? 0 : launcher.heroShiftX(4); y: launcher.morph < 1 ? 0 : launcher.heroShiftY(4) }
    }

    // Above everything: the hub is opaque, and the preview's hole must not show.
    HubPage {
        id: hub
        anchors.fill: parent
        opacity: rootWindow.hubOpen ? 1 : 0
        visible: opacity > 0
        unit: launcher.unit
        titleFamily: GlassStyle.titleFont
        rowFamily: GlassStyle.rowFont
        valueFamily: GlassStyle.valueFont
        timeText: Qt.formatTime(launcher.now, "hh:mm")
        dateText: launcher.dateLabel(launcher.now)
        backgroundSource: launcher.backgrounds.length > 0 ? launcher.backgroundUrl(Math.max(0, launcher.backgroundIndex)) : ""
        backgroundCredit: launcher.backgroundCredit(launcher.backgroundIndex)
        onBackRequested: rootWindow.hubBack()

        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: launcher.standardCurve }
        }
    }
}
