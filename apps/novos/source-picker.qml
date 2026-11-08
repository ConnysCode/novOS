import QtQuick 2.12
import QtQml 2.12
import SystemUIComponent 1.0
import WebOS.Global 1.0
import WebOSServices 1.0
import "module"
import "module/SourceList.js" as SourceList
import "module/ListScroll.js" as ListScroll

// Source picker, built to the K3-Quellen hand-off. It replaces LG's input picker
// (com.webos.app.quickinputpicker), which the input key on the Magic Remote opens.
// It is a window of its own and shares no state with the settings panel.
StarfishSystemUIWindow {
    id: rootWindow
    objectName: "starfishSystemUIWindow"
    property bool opened: false

    Connections {
        target: rootWindow.lifeCycleStatus
        onLaunch: {
            var params = payload && payload.params || {};
            if (payload && payload.reason === "preload") {
                rootWindow.opened = false;
                rootWindow.exit();
            } else if (rootWindow.opened) {
                // A switch started here already ends in its own confirmation.
                if (params.banner) picker.openBanner(params.appId);
                else if (params.attributes) picker.addAttribute(params.label);
                else if (params.notice || params.alert) picker.addNotice(params);
                else if (params.alertClose !== undefined) picker.closeNotice(params.alertClose);
                else if (picker.bannerMode) picker.open();
                else picker.hotkeyPressed();
            } else if (params.alertClose !== undefined) {
                rootWindow.exit();
            } else if (!params.banner && !params.attributes && !params.notice && !params.alert &&
                       picker.launcherOpen()) {
                // Our launcher shows the sources itself; the source key adds no second row.
                rootWindow.exit();
            } else {
                webOSShell.setWindowProperty("delayCloseWindowTimeout", 1000);
                webOSShell.setWindowProperty("legacyWindowName", "quickInputPicker");
                webOSShell.setWindowProperty("_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
                rootWindow.show();
                rootWindow.opened = true;
                if (params.banner) picker.openBanner(params.appId);
                else if (params.attributes) picker.openAttributes(params.label);
                else if (params.notice || params.alert) picker.openNotice(params);
                else picker.open();
            }
        }
        onClose: {
            rootWindow.opened = false;
            rootWindow.exit();
        }
    }

    FocusScope {
        id: picker
        anchors.fill: parent
        focus: true

        // Our launcher is open below on the home layer. novos-start.sh, novos-stop.sh and
        // the supervisor clear the note whenever surface-manager restarts.
        function launcherOpen() {
            try {
                var request = new XMLHttpRequest();
                request.open("GET", "file:///tmp/novos-launcher-open.ini", false);
                request.send();
                return request.responseText.indexOf("open=true") >= 0;
            } catch (error) {
                return false;
            }
        }

        readonly property real unit: Math.min(width / 1920, height / 1080)
        readonly property var standardCurve: GlassStyle.curve
        readonly property int tilePitch: 236
        readonly property int maxTiles: 12
        readonly property real barHeight: 274 * unit
        readonly property real barBottom: 56 * unit
        readonly property real barWidth: Math.min(sources.length * tilePitch - 12 + 48, 1808) * unit
        readonly property real barX: (width - barWidth) / 2
        readonly property real barY: height - barHeight - barBottom
        readonly property int fade: 72
        readonly property int scrollLimit: Math.max(0, sources.length * tilePitch - 12 + 48 - 1808)
        readonly property rect barArea: Qt.rect(56 * unit, barY, 1808 * unit, barHeight)
        readonly property rect pillArea: Qt.rect(56 * unit, 56 * unit, 1808 * unit, 968 * unit)
        readonly property int signalTimeout: 26     // checks of 300 ms

        property var devices: []
        property string foregroundApp: ""
        readonly property var sources: SourceList.build(devices, foregroundApp, true, function (key, params) {
            return I18n.t("source", key, params);
        }).slice(0, maxTiles)
        // A running source is on screen anyway, a device that is off has no picture.
        readonly property var stillPaths: sources.map(function (source) {
            var hasPicture = source.appId && !source.running && !source.off && !source.disabled;
            return hasPicture ? liveGlass.stillPath(source.appId) : "";
        })
        property int focusIndex: 0
        property int scroll: 0
        property bool barShown: false
        property bool pillShown: false
        property bool closing: false
        property bool shown: false
        property string switchingApp: ""
        property var switched: null
        property int switchChecks: 0
        property int startFocus: -1            // preview only
        // The pill alone, for a source change that did not start in this window.
        property bool bannerMode: false
        property string bannerApp: ""
        property string bannerState: ""        // connecting, waking, arrived, noSignal
        property int signalChecks: 0
        property var attributes: []            // the texts of LG's toasts, for the pill top right
        property string signalFormat: ""       // "4K · 24 Hz"
        property bool attributesShown: false
        property var notice: ({ title: "", detail: "", icon: "notice-info", buttons: [] })
        property bool noticeShown: false
        property bool noticeOpen: false
        property var noticeQueue: []
        property int noticeFocus: 0

        // ---- Audio-Guidance: what the focus says ----------------------------
        readonly property var focusSpeech: currentSpeech()
        onFocusSpeechChanged: guide.follow(focusSpeech)

        function tileSpeech(source) {
            if (!source) return "";
            var state = source.running ? I18n.t("picker", "speech.running") : "";
            if (switchingApp !== "" && source.appId === switchingApp) {
                state = source.off === true ? I18n.t("picker", "speech.turning_on") :
                                              I18n.t("picker", "speech.switching");
            }
            return guide.sentence([source.title, source.detail, state]);
        }

        // The banner reads the source once it is known and each new state of the
        // signal. The picture format arriving later is not read again.
        function bannerSpeech() {
            if (noticeOpen) {
                var button = notice.buttons[noticeFocus];
                return { context: "banner", intro: "", layer: "notice:" + notice.timestamp + notice.title,
                         layerIntro: guide.sentence([notice.title, notice.detail], ". "),
                         subject: "button:" + noticeFocus, text: button ? button.label : "" };
            }
            var said = "";
            if (switched && bannerState !== "") {
                var port = switched.port || "";
                said = bannerState === "noSignal" ? guide.sentence([switched.title, I18n.t("picker", "speech.no_signal")]) :
                       bannerState === "waking" ? guide.sentence([switched.title, port, I18n.t("picker", "speech.turning_on")]) :
                       bannerState === "connecting" ? guide.sentence([switched.title, port, I18n.t("picker", "speech.connecting")]) :
                       switched.title;
            }
            return { context: "banner", intro: "", layer: "pill:" + bannerApp, layerIntro: "",
                     subject: bannerState, text: said, change: "" };
        }

        function currentSpeech() {
            if (bannerMode) return bannerSpeech();
            var source = sources[focusIndex];
            return { context: "picker", intro: I18n.t("picker", "speech.change_source"), layer: "", layerIntro: "",
                     subject: focusIndex + ":" + (source ? source.appId || source.title : ""),
                     text: tileSpeech(source), change: tileSpeech(source) };
        }

        function deviceName(device) { return SourceList.deviceName(device); }
        function deviceIsOff(device) { return SourceList.deviceIsOff(device); }
        function deviceIcon(device) { return SourceList.deviceIcon(device); }

        function open() {
            bannerMode = false;
            bannerState = "";
            signalCheck.stop();
            pillTimer.stop();
            liveGlass.area = barArea;
            closing = false;
            shown = false;
            barShown = false;
            pillShown = false;
            switchingApp = "";
            switched = null;
            scroll = 0;
            focusIndex = 0;
            guide.reset();
            bar.opacity = 0;
            barOffset.y = 24 * unit;
            forceActiveFocus();
            openTimer.restart();
            service.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
            service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
            if (liveGlass.pictureReady) startOpenAnimation();
        }

        // LG's input app calls this instead of showing its banner.
        function openBanner(appId) {
            bar.opacity = 0;
            bannerMode = true;
            bannerApp = appId || "";
            bannerState = "";
            guide.reset();
            signalChecks = 0;
            closing = false;
            shown = true;
            pillShown = false;
            pillTimer.stop();
            liveGlass.area = pillArea;
            forceActiveFocus();
            service.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
            service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
            openTimer.restart();
            signalCheck.restart();
        }

        // Shows exactly what LG's toasts say, so a format nobody listed here still appears.
        // They arrive on their own, even during playback.
        function enterBanner() {
            bar.opacity = 0;
            bannerMode = true;
            closing = false;
            shown = true;
            liveGlass.area = pillArea;
            forceActiveFocus();
            service.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
            openTimer.restart();
        }

        function openAttributes(label) {
            enterBanner();
            addAttribute(label);
        }

        function openNotice(params) {
            enterBanner();
            addNotice(params);
        }

        function stayOpen() {
            if (!closing) return;
            closeAnimation.stop();
            closing = false;
        }

        // LG's toasts, in LG's words. Only the icon comes from the text.
        function noticeIcon(text) {
            var words = text.toLowerCase();
            // LG writes its toasts in the TV's language, so the words cover all four.
            var has = function (list) {
                return list.some(function (word) { return words.indexOf(word) >= 0; });
            };
            if (has(["kopfh", "bluetooth", "headphone", "auricular", "casque", "écouteur"])) return "notice-headphones";
            if (has(["usb"])) return "notice-usb";
            if (has(["update", "actualiza", "mise à jour"])) return "notice-update";
            if (has(["hdmi", "gerät", "device", "dispositivo", "appareil"])) return "notice-device";
            if (has(["signal", "señal", "ausschalt", "turn off", "apaga", "éteindre", "extinction"])) return "notice-moon";
            return "notice-info";
        }

        // A toast disappears by itself. A dialog waits for its button unless LG gave it a timeout.
        function noticeOf(params) {
            var alert = params.alert;
            var info = alert || params;
            var title = info.title || info.message || "";
            var detail = info.title ? info.message || "" : "";
            var buttons = alert ? (alert.buttons || []) : [];
            if (!alert && params.action) {
                buttons = [{ label: I18n.t("global", "open"), focus: true, toastAction: params.action },
                           { label: I18n.t("global", "close") }];
            }
            return { title: title, detail: detail, icon: noticeIcon(title + " " + detail), buttons: buttons,
                     dialog: !!alert, modal: !!(alert && alert.modal), sourceId: alert ? alert.sourceId : "",
                     closeAction: alert ? alert.onCloseAction : null, timestamp: params.timestamp || "",
                     timeout: alert ? (alert.timeout || 0) * 1000 : 5000 };
        }

        function addNotice(params) {
            var next = noticeOf(params);
            if (next.title === "") return;
            stayOpen();
            // A dialog on screen waits for its answer, what comes later waits behind it.
            if (noticeOpen && notice.dialog) noticeQueue = noticeQueue.concat([next]);
            else showNotice(next);
        }

        function showNotice(next) {
            var focus = 0;
            for (var i = 0; i < next.buttons.length; i++) {
                if (next.buttons[i].focus) focus = i;
            }
            noticeFocus = focus;
            notice = next;
            noticeOpen = true;
            noticeShown = liveGlass.pictureReady;
            noticeTimer.stop();
            if (next.timeout > 0) {
                noticeTimer.interval = next.timeout;
                noticeTimer.start();
            }
        }

        function finishNotice(runCloseAction) {
            var action = notice.closeAction;
            if (runCloseAction && action && action.serviceURI) {
                alertService.callForApplication(notice.sourceId, action.serviceURI, action.serviceMethod,
                                                JSON.stringify(action.launchParams || {}));
            }
            noticeTimer.stop();
            noticeOpen = false;
            if (noticeQueue.length > 0) {
                var next = noticeQueue[0];
                noticeQueue = noticeQueue.slice(1);
                showNotice(next);
            } else {
                noticeShown = false;
                closeWhenIdle();
            }
        }

        function activateNotice(index) {
            var button = notice.buttons[index];
            if (!button) return;
            if (button.toastAction) {
                service.call(button.toastAction.serviceURI, button.toastAction.serviceMethod,
                             JSON.stringify(button.toastAction.launchParams || {}));
            } else if (button.action) {
                alertService.callForApplication(notice.sourceId, button.action.serviceURI, button.action.serviceMethod,
                                                JSON.stringify(button.action.launchParams || {}));
            }
            finishNotice(false);
        }

        // LG took a dialog back.
        function closeNotice(timestamp) {
            if (timestamp === "all") {
                noticeQueue = [];
                if (noticeOpen) finishNotice(false);
                return;
            }
            noticeQueue = noticeQueue.filter(function (entry) { return entry.timestamp !== timestamp; });
            if (noticeOpen && notice.timestamp === timestamp) finishNotice(false);
        }

        function noticeKey(event) {
            var count = notice.buttons.length;
            if (event.key === Qt.Key_Left) {
                noticeFocus = Math.max(0, noticeFocus - 1);
            } else if (event.key === Qt.Key_Right) {
                noticeFocus = Math.min(count - 1, noticeFocus + 1);
            } else if (Remote.isOk(event.key)) {
                if (!event.isAutoRepeat) activateNotice(noticeFocus);
            } else if (!isBackKey(event.key)) {
                return false;
            }
            return true;
        }

        function addAttribute(label) {
            if (!label) return;
            stayOpen();
            var current = attributeTimer.running ? attributes : [];
            attributes = current.indexOf(label) < 0 ? current.concat([label]) : current;
            attributesShown = liveGlass.pictureReady;
            attributeTimer.restart();
        }

        function resolutionName(height) {
            if (height >= 4000) return "8K";
            if (height >= 2000) return "4K";
            return height > 0 ? height + "p" : "";
        }

        function updateFormat(video) {
            if (!video || !video.connected) return;
            var resolution = resolutionName(video.height);
            signalFormat = resolution !== "" && video.frameRate > 0 ?
                           resolution + " · " + Math.round(video.frameRate) + " Hz" : "";
            if (bannerState === "arrived") updateBanner();
        }

        function closeWhenIdle() {
            if (!bannerMode) return;
            if (!pillTimer.running && !attributeTimer.running && !noticeOpen &&
                    !signalCheck.running) close();
        }

        function updateBanner() {
            var device = null;
            for (var i = 0; i < devices.length; i++) {
                if (devices[i].appId === bannerApp) device = devices[i];
            }
            // Sources without a port have no signal to wait for.
            if (!device) {
                signalCheck.stop();
                bannerState = "arrived";
                for (var j = 0; j < sources.length; j++) {
                    if (sources[j].appId === bannerApp) switched = sources[j];
                }
                pillTimer.interval = 2200;
                pillTimer.restart();
                if (liveGlass.pictureReady) pillShown = true;
                return;
            }
            var port = "HDMI " + device.port;
            var state = device.hdmiSignalExist ? "arrived" : "connecting";
            if (state === "connecting" && deviceIsOff(device)) state = "waking";
            if (state !== "arrived" && signalChecks >= signalTimeout) state = "noSignal";
            bannerState = state;
            var plugged = device.hdmiPlugIn;
            switched = {
                title: plugged && state !== "noSignal" ? deviceName(device) : port,
                detail: state === "noSignal" ? I18n.t("picker", "detail.no_signal") :
                        state === "waking" ? I18n.t("picker", "detail.port_waking", { port: port }) :
                        state === "connecting" ? I18n.t("picker", "detail.port_connecting", { port: port }) :
                        signalFormat !== "" ? I18n.t("picker", "detail.port_format",
                                                     { port: port, format: signalFormat }) : port,
                port: port,
                icon: state === "noSignal" ? "source-alert" : deviceIcon(device)
            };
            if ((state === "arrived" || state === "noSignal") && signalCheck.running) {
                signalCheck.stop();
                pillTimer.interval = state === "noSignal" ? 5000 : 2200;
                pillTimer.restart();
                if (state === "arrived") {
                    service.call("luna://com.webos.service.videooutput", "/getStatus", "{}");
                }
            }
            if (liveGlass.pictureReady) pillShown = true;
        }

        function close() {
            if (closing) return;
            closing = true;
            openTimer.stop();
            switchCheck.stop();
            signalCheck.stop();
            pillTimer.stop();
            liveGlass.stop();
            closeAnimation.restart();
        }

        function startOpenAnimation() {
            if (bannerMode) {
                openTimer.stop();
                if (bannerState !== "") pillShown = true;
                if (attributes.length > 0) attributesShown = true;
                if (noticeOpen) noticeShown = true;
                return;
            }
            if (closing || barShown) return;
            openTimer.stop();
            barShown = true;
            openAnimation.restart();
        }

        // Starts on the next source: the one that runs is rarely the goal.
        function placeFocus() {
            var first = -1;
            for (var i = 0; i < sources.length; i++) {
                if (first < 0 && !sources[i].running && !sources[i].disabled && !sources[i].manage) first = i;
            }
            focusIndex = startFocus >= 0 ? startFocus : Math.max(0, first);
            keepInView();
        }

        function keepInView() {
            scroll = ListScroll.centred(24 + focusIndex * tilePitch, 224, 1808, scrollLimit + 1808);
        }

        function moveFocus(step) {
            var next = focusIndex + step;
            while (next >= 0 && next < sources.length && sources[next].disabled) next += step;
            if (next < 0 || next >= sources.length) return;
            focusIndex = next;
            keepInView();
        }

        // The input key pressed again steps through the sources, as on LG's menu.
        function hotkeyPressed() {
            if (switchingApp !== "") return;
            var next = focusIndex;
            for (var i = 0; i < sources.length; i++) {
                next = (next + 1) % sources.length;
                if (!sources[next].disabled) break;
            }
            focusIndex = next;
            keepInView();
        }

        function activate(index) {
            var source = sources[index];
            if (!source || source.disabled || switchingApp !== "") return;
            if (source.manage) {
                service.call("luna://com.webos.service.systemUIManager", "/launch",
                             JSON.stringify({ appId: "com.webos.app.quicksettings",
                                              params: { page: "sources" } }));
                close();
            } else if (source.running) {
                close();
            } else {
                switchingApp = source.appId;
                switched = source;
                switchChecks = 0;
                service.call("luna://com.webos.applicationManager", "/launch",
                             GlassStyle.launchRequest(source.appId));
                switchCheck.restart();
            }
        }

        function switchDone() {
            switchCheck.stop();
            switchingApp = "";
            barShown = false;
            barFade.restart();
            hideBar.restart();
        }

        function showPill() {
            liveGlass.area = pillArea;
            liveGlass.snap();
            pillShown = true;
            pillTimer.restart();
        }

        function isBackKey(key) {
            return Remote.isBack(key);
        }

        Keys.onPressed: {
            // The pill must not swallow the remote: the key goes on to the source.
            if (bannerMode && noticeOpen && notice.buttons.length > 0) {
                if (noticeKey(event)) {
                    event.accepted = true;
                    return;
                }
            }
            if (bannerMode) {
                rootWindow.webOSXInput.invokeFullKeyToAppAction(event.key, event.nativeScanCode, foregroundApp);
                close();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Left) {
                if (switchingApp === "") moveFocus(-1);
            } else if (event.key === Qt.Key_Right) {
                if (switchingApp === "") moveFocus(1);
            } else if (Remote.isOk(event.key)) {
                if (!event.isAutoRepeat) activate(focusIndex);
            } else if (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down && !isBackKey(event.key)) {
                return;
            }
            event.accepted = true;
        }

        Keys.onReleased: {
            if (bannerMode) {
                if (isBackKey(event.key) && noticeOpen && notice.buttons.length > 0 && !notice.modal) {
                    finishNotice(true);
                }
                event.accepted = true;
            } else if (isBackKey(event.key)) {
                close();
                event.accepted = true;
            }
        }

        AudioGuide {
            id: guide
            quiet: picker.closing
        }

        Service {
            id: service
            appId: "com.webos.app.quicksettings"
            onResponse: {
                var response = JSON.parse(payload);
                if (method === "/getAllInputStatus") {
                    picker.devices = response.devices || [];
                    if (picker.bannerMode) picker.updateBanner();
                    else picker.placeFocus();
                } else if (method === "/getStatus") {
                    picker.updateFormat(response.video && response.video[0]);
                } else if (method === "/getForegroundAppInfo") {
                    if (picker.switchingApp === "") {
                        picker.foregroundApp = response.appId || "";
                        liveGlass.setForeground(picker.foregroundApp);
                        if (!picker.bannerMode) picker.placeFocus();
                    } else if (response.appId === picker.switchingApp) {
                        picker.switchDone();
                    }
                }
            }
            onError: if (method === "/launch") picker.switchDone()
        }

        // Dialog actions run as the app that asked for them, as in LG's view.
        Service {
            id: alertService
            appId: "com.webos.surfacemanager"
        }

        // The window never waits long for a picture.
        Timer {
            id: openTimer
            interval: 900
            onTriggered: picker.startOpenAnimation()
        }

        // HDMI needs a moment, a device that wakes up can take seconds.
        Timer {
            id: switchCheck
            interval: 300
            repeat: true
            onTriggered: {
                picker.switchChecks++;
                if (picker.switchChecks > 30) picker.switchDone();
                else service.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
            }
        }

        Timer {
            id: signalCheck
            interval: 300
            repeat: true
            onTriggered: {
                picker.signalChecks++;
                service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
            }
        }

        NumberAnimation {
            id: barFade
            target: bar
            property: "opacity"
            to: 0
            duration: 160
        }

        Timer {
            id: hideBar
            interval: 220
            onTriggered: picker.showPill()
        }

        Timer {
            id: pillTimer
            interval: 2200
            onTriggered: {
                if (!picker.bannerMode) {
                    picker.close();
                } else {
                    picker.pillShown = false;
                    picker.closeWhenIdle();
                }
            }
        }

        Timer {
            id: attributeTimer
            interval: 4000
            onTriggered: {
                picker.attributesShown = false;
                picker.closeWhenIdle();
            }
        }

        Timer {
            id: noticeTimer
            interval: 5000
            onTriggered: picker.finishNotice(true)
        }

        readonly property string titleFamily: GlassStyle.titleFont
        readonly property string rowFamily: GlassStyle.rowFont
        readonly property string valueFamily: GlassStyle.valueFont

        LiveBackdrop {
            id: liveGlass
            anchors.fill: parent
            unit: picker.unit
            framePrefix: "/tmp/novos-inputpicker-frame-"
            keepStill: !picker.bannerMode
            stillsOnly: picker.bannerMode
            area: picker.barArea
            opened: rootWindow.opened
            shown: picker.shown
            closing: picker.closing
            onReady: if (rootWindow.opened) picker.startOpenAnimation()
        }

        GlassCard {
            id: bar
            x: picker.barX
            y: picker.barY
            width: picker.barWidth
            height: picker.barHeight
            opacity: 0
            visible: opacity > 0
            unit: picker.unit
            backdrop: liveGlass.texture
            glassShader: liveGlass.glassShader
            backdropMargin: liveGlass.margin
            backdropArea: picker.barArea
            hasBackdrop: liveGlass.hasFrame ? 1 : 0
            shadow: "shadow-panel"
            transform: Translate { id: barOffset }

            Text {
                x: 32 * picker.unit
                y: 20 * picker.unit
                height: 20 * picker.unit
                verticalAlignment: Text.AlignVCenter
                text: I18n.t("picker", "label.change_source")
                color: GlassStyle.textMuted
                font.family: picker.rowFamily
                font.pixelSize: 16 * picker.unit
                font.letterSpacing: 1 * picker.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            // Taller than the tiles: the layer cuts off whatever leaves it, and the
            // shadow of the focused tile reaches past the end of the panel.
            Item {
                y: 14 * picker.unit
                width: parent.width
                height: 290 * picker.unit

                layer.enabled: picker.scrollLimit > 0
                layer.effect: EdgeFade {
                    horizontal: 1
                    topFade: picker.fade * picker.unit / picker.barWidth
                    bottomFade: picker.fade * picker.unit / picker.barWidth
                    topAmount: picker.scroll > 0 ? 1 : 0
                    bottomAmount: picker.scroll < picker.scrollLimit ? 1 : 0
                }

                Item {
                    x: -picker.scroll * picker.unit
                    y: 42 * picker.unit
                    height: 184 * picker.unit

                    Behavior on x {
                        NumberAnimation {
                            duration: GlassStyle.focusDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: picker.standardCurve
                        }
                    }

                    // The single focus surface. It slides between the tiles.
                    FocusSurface {
                        id: focusSurface
                        x: (24 + picker.focusIndex * picker.tilePitch) * picker.unit
                        width: 224 * picker.unit
                        height: 184 * picker.unit
                        unit: picker.unit
                        focusScale: GlassStyle.focusScale
                        radius: 32
                    }

                    Repeater {
                        model: picker.maxTiles

                        SourceTile {
                            readonly property var entry: picker.sources[index] || ({ title: "", detail: "", icon: "source-box" })
                            x: (24 + index * picker.tilePitch) * picker.unit
                            width: 224 * picker.unit
                            height: 184 * picker.unit
                            visible: index < picker.sources.length
                            unit: picker.unit
                            titleFont: picker.titleFamily
                            valueFont: picker.valueFamily
                            source: entry
                            focused: index === picker.focusIndex
                            busy: picker.switchingApp !== "" && entry.appId === picker.switchingApp
                            busyText: entry.off === true ? I18n.t("picker", "state.turning_on") : I18n.t("picker", "state.switching")

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    picker.focusIndex = index;
                                    picker.activate(index);
                                }
                            }
                        }
                    }
                }
            }
        }

        // What the signal carries, top right.
        Item {
            id: attributePill
            x: picker.width - width - 56 * picker.unit
            y: 56 * picker.unit
            width: attributeRow.width + 44 * picker.unit
            height: 52 * picker.unit
            opacity: picker.attributesShown ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

            SoftShadow {
                unit: picker.unit
                radius: 26
                softness: 24
                drop: 20
                strength: 0.32
                pad: 72
            }

            GlassCard {
                anchors.fill: parent
                unit: picker.unit
                cornerRadius: 26 * picker.unit
                backdrop: liveGlass.texture
                glassShader: liveGlass.glassShader
                backdropMargin: liveGlass.margin
                backdropArea: Qt.rect(picker.pillArea.x - attributePill.x, picker.pillArea.y - attributePill.y,
                                      picker.pillArea.width, picker.pillArea.height)
                hasBackdrop: liveGlass.hasFrame ? 1 : 0
                shadow: ""
            }

            Row {
                id: attributeRow
                x: 22 * picker.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * picker.unit

                Repeater {
                    model: picker.attributes

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12 * picker.unit

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: index > 0
                            width: 4 * picker.unit
                            height: width
                            radius: width / 2
                            color: "#8cffffff"
                        }

                        Text {
                            text: modelData
                            color: "#ffffff"
                            font.family: picker.titleFamily
                            font.pixelSize: 17 * picker.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }
        }

        NoticeBar {
            id: noticeBar
            x: (picker.width - width) / 2
            y: picker.height - height - 56 * picker.unit
            unit: picker.unit
            titleFont: picker.titleFamily
            valueFont: picker.valueFamily
            shadowShader: liveGlass.shadowShader
            glassShader: liveGlass.glassShader
            backdrop: liveGlass.texture
            backdropMargin: liveGlass.margin
            backdropArea: Qt.rect(picker.pillArea.x - x, picker.pillArea.y - y,
                                  picker.pillArea.width, picker.pillArea.height)
            hasBackdrop: liveGlass.hasFrame ? 1 : 0
            notice: picker.notice
            focusIndex: picker.noticeFocus
            shown: picker.noticeShown
            onButtonClicked: picker.activateNotice(index)
        }

        SourcePreview {
            readonly property real tileCentre: picker.barX + (24 + picker.focusIndex * picker.tilePitch +
                                                              112 - picker.scroll) * picker.unit
            x: Math.max(56 * picker.unit, Math.min(picker.width - width - 56 * picker.unit, tileCentre - width / 2))
            y: picker.barY - height - 16 * picker.unit
            unit: picker.unit
            shadowShader: liveGlass.shadowShader
            paths: picker.stillPaths
            tiles: picker.maxTiles
            index: picker.focusIndex
            wanted: picker.barShown && !picker.closing && picker.switchingApp === ""
            glideCurve: picker.standardCurve
        }

        // Small confirmation after the switch, the picture behind it is already new.
        Item {
            x: 56 * picker.unit
            y: 56 * picker.unit
            width: pillContent.width + 48 * picker.unit
            height: 88 * picker.unit
            opacity: picker.pillShown ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

            SoftShadow {
                unit: picker.unit
                radius: 44
                softness: 40
                drop: 30
                strength: 0.35
                pad: 110
            }

            GlassCard {
                anchors.fill: parent
                unit: picker.unit
                cornerRadius: 44 * picker.unit
                backdrop: liveGlass.texture
                glassShader: liveGlass.glassShader
                backdropMargin: liveGlass.margin
                backdropArea: Qt.rect(0, 0, picker.pillArea.width, picker.pillArea.height)
                hasBackdrop: liveGlass.hasFrame ? 1 : 0
                shadow: ""
            }

            Row {
                id: pillContent
                x: 20 * picker.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16 * picker.unit

                Item {
                    readonly property bool waiting: picker.bannerState === "connecting" ||
                                                    picker.bannerState === "waking"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36 * picker.unit
                    height: 36 * picker.unit

                    Image {
                        anchors.fill: parent
                        visible: !parent.waiting
                        smooth: true
                        source: picker.switched ? Qt.resolvedUrl("module/icons/" + picker.switched.icon + ".png") : ""
                    }

                    Spinner {
                        anchors.centerIn: parent
                        size: 32 * picker.unit
                        lineWidth: 3.5 * picker.unit
                        visible: parent.waiting
                        running: parent.waiting
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * picker.unit

                    Text {
                        text: picker.switched ? picker.switched.title : ""
                        color: "#ffffff"
                        font.family: picker.titleFamily
                        font.pixelSize: 22 * picker.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        // A device that is off shows only its port: the pill confirms the switch.
                        text: picker.switched ? (picker.switched.off === true ? picker.switched.port :
                                                                                picker.switched.detail) : ""
                        color: GlassStyle.textSecondary
                        font.family: picker.valueFamily
                        font.pixelSize: 17 * picker.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }
        }

        ParallelAnimation {
            id: openAnimation
            onStopped: picker.shown = !picker.closing
            NumberAnimation {
                target: bar
                property: "opacity"
                to: 1
                duration: 130
                easing.type: Easing.Bezier
                easing.bezierCurve: picker.standardCurve
            }
            NumberAnimation {
                target: barOffset
                property: "y"
                to: 0
                duration: 130
                easing.type: Easing.Bezier
                easing.bezierCurve: picker.standardCurve
            }
        }

        SequentialAnimation {
            id: closeAnimation
            ParallelAnimation {
                NumberAnimation { target: bar; property: "opacity"; to: 0; duration: 160 }
                NumberAnimation { target: barOffset; property: "y"; to: 24 * picker.unit; duration: 160 }
                ScriptAction { script: picker.pillShown = false }
            }
            ScriptAction {
                script: {
                    rootWindow.opened = false;
                    rootWindow.exit();
                }
            }
        }
    }
}
