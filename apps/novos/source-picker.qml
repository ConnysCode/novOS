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
                else if (params.noSignal) picker.showNoSignal(params.noSignal);
                else if (params.attributes) picker.addAttribute(params.label);
                else if (params.notice || params.alert) picker.addNotice(params);
                else if (params.novosProgress) picker.openUpdatePill();
                else if (params.novosWhatsNew) picker.openWhatsNew(params);
                else if (params.alertClose !== undefined) picker.closeNotice(params.alertClose);
                else if (picker.bannerMode) picker.open();
                else picker.hotkeyPressed();
            } else if (params.alertClose !== undefined) {
                rootWindow.exit();
            } else if (!params.banner && !params.attributes && !params.notice && !params.alert &&
                       !params.novosProgress && !params.novosWhatsNew && !params.noSignal && picker.launcherOpen()) {
                // Our launcher shows the sources itself; the source key adds no second row.
                rootWindow.exit();
            } else {
                webOSShell.setWindowProperty("delayCloseWindowTimeout", 1000);
                webOSShell.setWindowProperty("legacyWindowName", "quickInputPicker");
                webOSShell.setWindowProperty("_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
                rootWindow.show();
                rootWindow.opened = true;
                if (params.banner) picker.openBanner(params.appId);
                else if (params.noSignal) picker.showNoSignal(params.noSignal);
                else if (params.attributes) picker.openAttributes(params.label);
                else if (params.notice || params.alert) picker.openNotice(params);
                else if (params.novosProgress) { picker.enterBanner(); picker.openUpdatePill(); }
                else if (params.novosWhatsNew) { picker.enterBanner(); picker.openWhatsNew(params); }
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
        // novOS' own update in the background (board Update-3); the supervisor opens it.
        property bool updatePillOpen: false
        property bool updatePillShown: false
        // The install runs over our launcher, with LG's Home in front: nothing but LG's Home
        // would show while novOS stops for the update (novos-stop.sh --keep-hidden keeps it
        // hidden). Then the black restart screen of the setup stands in for the pill, so that
        // nobody takes the TV for broken.
        property bool updateOverHome: false
        readonly property bool updateScreenShown: updatePillOpen && updateOverHome
        readonly property var installCommands: ["update", "restore", "rollback"]
        readonly property string updateLabel: I18n.t("picker",
            updateInfo.stage === "download" || updateInfo.stage === "manifest" ? "update.loading" : "update.installing",
            { version: updateVersion(updateInfo) }).replace(/\s+/g, " ").trim()
        // "Neu in novOS" after a minor or major update (WhatsNew); the supervisor opens it.
        property bool whatsNewOpen: false
        readonly property var updateInfo: updates.info || ({})
        property var noticeQueue: []
        property int noticeFocus: 0
        // The screen while the source sends no picture (NoSignalScreen, K3-KeinSignal-E). It
        // takes over from the pill "Kein Signal" and stays until a picture arrives.
        property bool noSignalOpen: false
        property string noSignalApp: ""
        // empty, off, silent (on but no picture, or CEC says nothing), starting, unresponsive,
        // lost (the picture went while watching) and format (it arrives, but does not fit).
        property string noSignalCase: ""
        property string noSignalFormat: ""     // what arrives in the format case, "4K mit 120 Hz"
        property bool noSignalPreview: false   // opened by hand: no polling, a picture does not end it
        property double noSignalSince: 0       // LG's auto off counts from here
        property double wakeSince: 0           // "Einschalten" pressed
        property int noSignalLeft: -1          // seconds until LG's auto off, -1 without countdown
        property bool autoOff: false           // LG turns the TV off without a signal
        property bool backToNoSignal: false    // the source bar opened over the screen returns to it
        property url noSignalPicture
        property string noSignalCredit: ""

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
            if (noSignalOpen && !noticeOpen) return noSignalSpeech();
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

        // The case once, then the focused action; the countdown says how long is left.
        function noSignalSpeech() {
            if (noSignalScreen.counting) {
                return { context: "nosignal", intro: "", layer: "nosignal:countdown",
                         layerIntro: I18n.t("no_signal", "speech.countdown",
                                            { minutes: Math.max(1, Math.ceil(noSignalLeft / 60)) }),
                         subject: "stayOn", text: I18n.t("no_signal", "action.stay_on"), change: "" };
            }
            var action = noSignalScreen.actions[noSignalScreen.focusIndex];
            return { context: "nosignal", intro: "", layer: "nosignal:" + noSignalApp + ":" + noSignalCase,
                     layerIntro: guide.sentence([noSignalScreen.title, noSignalScreen.detail], ". "),
                     subject: "action:" + noSignalScreen.focusIndex, text: action ? action.label : "", change: "" };
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
            // Over the screen without a picture the bar samples its photo, and back returns there.
            backToNoSignal = noSignalOpen;
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
            if (liveGlass.pictureReady || backToNoSignal) startOpenAnimation();
        }

        // LG's input app calls this instead of showing its banner.
        function openBanner(appId) {
            bar.opacity = 0;
            noSignalOpen = false;
            backToNoSignal = false;
            noSignalPreview = false;
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
            if (params.novos) return novosNotice(params);
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
            if (button.novosCommand) {
                updates.send(button.novosCommand, button.novosValues || {});
            } else if (button.toastAction) {
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
                    !signalCheck.running && !updatePillOpen && !whatsNewOpen && !noSignalOpen) close();
        }

        // ---- Neu in novOS ----------------------------------------------------------------
        // The release's own notes (module/release-notes.json): every version after the one
        // before the update, so that whoever skipped versions sees all of them. At most four
        // features in the modal, the fixes as one line below.

        function localText(texts) {
            if (!texts || typeof texts !== "object") return String(texts || "");
            return texts[I18n.language] || texts.en || texts.de || "";
        }

        // 1.0.0-beta.2 < 1.0.0-beta.10 < 1.0.0 < 1.0.1; a local build sorts before every release.
        function versionKey(text) {
            var match = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$/.exec(text || "");
            if (!match) return null;
            var parts = [Number(match[1]), Number(match[2]), Number(match[3]), match[4] ? 0 : 1];
            (match[4] || "").split(".").forEach(function (part) {
                parts.push(/^\d+$/.test(part) ? Number(part) : part);
            });
            return parts;
        }

        function newer(a, b) {
            for (var i = 0; i < Math.max(a.length, b.length); i++) {
                if (a[i] === undefined) return false;
                if (b[i] === undefined) return true;
                if (a[i] !== b[i]) return typeof a[i] === typeof b[i] ? a[i] > b[i] : typeof a[i] === "string";
            }
            return false;
        }

        function openWhatsNew(params) {
            var notes = {};
            try {
                var request = new XMLHttpRequest();
                request.open("GET", Qt.resolvedUrl("module/release-notes.json"), false);
                request.send();
                notes = JSON.parse(String(request.responseText || "{}"));
            } catch (error) {
            }
            var current = versionKey(params.version);
            var before = versionKey(params.previous);
            var features = [];
            var fixes = [];
            var versions = Object.keys(notes).filter(function (name) {
                var key = versionKey(name);
                return key && !newer(key, current) && (before ? newer(key, before) : name === params.version);
            });
            versions.sort(function (a, b) { return newer(versionKey(a), versionKey(b)) ? -1 : 1; });
            versions.forEach(function (name) {
                (notes[name].items || []).forEach(function (item) {
                    var entry = { title: localText(item.title), text: localText(item.text), icon: item.icon || "",
                                  open: item.open || "",
                                  image: item.image ? Qt.resolvedUrl("module/release-art/" + name + "/" + item.image) : "" };
                    if (item.kind === "fix") fixes.push(entry);
                    else features.push(entry);
                });
            });
            whatsNew.version = params.version || "";
            whatsNew.items = features.slice(0, 4);
            whatsNew.fixedText = fixes.length === 0 ? "" :
                I18n.t("picker", fixes.length > 1 ? "whatsnew.fixed_more" : "whatsnew.fixed",
                       { text: fixes[0].text, count: fixes.length - 1 });
            var at = new Date((params.installed || Date.now() / 1000) * 1000);
            var time = at.toLocaleTimeString(Qt.locale(I18n.qtLocale), Locale.ShortFormat);
            var today = new Date().toDateString() === at.toDateString();
            whatsNew.installedText = today ? I18n.t("picker", "whatsnew.installed_today", { time: time }) :
                I18n.t("picker", "whatsnew.installed_on", { time: time,
                       date: at.toLocaleDateString(Qt.locale(I18n.qtLocale), Locale.ShortFormat) });
            whatsNew.focusIndex = whatsNew.items.length + 1;
            stayOpen();
            whatsNewOpen = true;
            whatsNew.shown = liveGlass.pictureReady;
        }

        function finishWhatsNew() {
            whatsNewOpen = false;
            whatsNew.shown = false;
            closeWhenIdle();
        }

        // Opens a page of the settings (OK on a novelty, "Alle Neuerungen").
        function openSettingsPage(page) {
            service.call("luna://com.webos.service.systemUIManager", "/launch",
                         JSON.stringify({ appId: "com.webos.app.quicksettings", params: { page: page } }));
            finishWhatsNew();
        }

        function openUpdatePill() {
            stayOpen();
            if (!updatePillOpen) updateOverHome = false;
            updatePillOpen = true;
            updatePillShown = liveGlass.pictureReady;
            updatePillCheck.restart();
            updateScreenLimit.restart();
            service.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
        }

        // The pill goes when the update is through or failed; the restart takes the window anyway.
        // The black screen stays through "restarting": it says that novOS restarts.
        // Read from the bridge itself: in onInfoChanged, updateInfo may not have followed yet.
        function checkUpdatePill() {
            var info = updates.info || {};
            var installing = info.busy === true && installCommands.indexOf(info.command) >= 0;
            if (!updatePillOpen || (installing && (info.phase === "running" ||
                                                   (info.phase === "restarting" && updateOverHome)))) return;
            closeUpdatePill();
        }

        function closeUpdatePill() {
            updatePillOpen = false;
            updatePillShown = false;
            updateScreenLimit.stop();
            closeWhenIdle();
        }

        // The version being installed: the offer of the check, else the updater's steps
        // ("downloading novOS 0.9.1-beta.3 (18 MB)"); restore and rollback have no check.
        function updateVersion(info) {
            var offer = info.result && info.result.check || {};
            if (offer.available) return offer.available;
            var steps = info.steps || [];
            for (var i = 0; i < steps.length; i++) {
                var found = /novOS (\d[^\s)]*)/.exec(steps[i].message || "");
                if (found) return found[1];
            }
            return "";
        }

        // novOS' own notices (boards Update-1 and Update-6), in this window's words.
        function novosNotice(params) {
            var version = params.version || "";
            if (params.novos === "available") {
                var channel = I18n.t("picker", "update.channel_" + (params.channel === "stable" ? "stable" : "beta"));
                var size = params.size > 0 ? Math.max(1, Math.round(params.size / 1000000)) : 0;
                return { title: I18n.t("picker", "update.available", { version: version }),
                         detail: size ? I18n.t("picker", "update.available_size", { channel: channel, size: size }) : channel,
                         icon: "notice-update",
                         buttons: [{ label: I18n.t("picker", "update.show"), focus: true,
                                     toastAction: { serviceURI: "luna://com.webos.service.systemUIManager",
                                                    serviceMethod: "/launch",
                                                    launchParams: { appId: "com.webos.app.quicksettings",
                                                                    params: { page: "settings:info:update" } } } },
                                   { label: I18n.t("picker", "update.later") }],
                         dialog: false, modal: false, sourceId: "", closeAction: null, timestamp: "",
                         timeout: 15000 };
            }
            if (params.novos === "ready") {
                // Loaded in the background; novOS asks before it installs (K3-NovUpdate-5).
                return { title: I18n.t("picker", "update.ready", { version: version }),
                         detail: I18n.t("picker", "update.ready_detail"), icon: "notice-update",
                         buttons: [{ label: I18n.t("picker", "update.install_now"), focus: true,
                                     novosCommand: "update" },
                                   { label: I18n.t("picker", "update.tonight"),
                                     novosCommand: "tonight", novosValues: { version: version } }],
                         dialog: false, modal: false, sourceId: "", closeAction: null, timestamp: "",
                         timeout: 20000 };
            }
            // A patch (K3-Neu-5): how many fixes, and "Details" to the update page.
            var fixes = params.fixes || 0;
            var details = { label: I18n.t("picker", "update.details"),
                            toastAction: { serviceURI: "luna://com.webos.service.systemUIManager", serviceMethod: "/launch",
                                           launchParams: { appId: "com.webos.app.quicksettings",
                                                           params: { page: "settings:info:update" } } } };
            return { title: I18n.t("picker", "update.installed", { version: version }),
                     detail: params.back ? I18n.t("picker", "update.back_detail") :
                             fixes > 0 ? I18n.t("picker", fixes === 1 ? "update.fixed_one" : "update.fixed_count",
                                                { count: fixes }) : I18n.t("picker", "update.installed_detail"),
                     icon: "notice-update",
                     buttons: (fixes > 0 ? [details] : []).concat([{ label: I18n.t("global", "ok"), focus: true }]),
                     dialog: false, modal: false, sourceId: "", closeAction: null, timestamp: "", timeout: 10000 };
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
                // Without a picture the pill stands briefly, then the screen takes over.
                pillTimer.interval = state === "noSignal" ? GlassStyle.noSignalHandover : 2200;
                pillTimer.restart();
                if (state === "arrived") {
                    service.call("luna://com.webos.service.videooutput", "/getStatus", "{}");
                }
            }
            if (liveGlass.pictureReady) pillShown = true;
        }

        // ---- Kein Signal -------------------------------------------------------------------
        // Concept E of K3-KeinSignal. The case comes from LG's input status: no cable (hotplug),
        // CEC reports the device off, or it is plugged and sends nothing. "Einschalten"
        // launches the input again, as a switch to a sleeping device does; without a picture
        // after noSignalWakeLimit the device does not answer.

        function deviceOf(appId) {
            for (var i = 0; i < devices.length; i++) {
                if (devices[i].appId === appId) return devices[i];
            }
            return null;
        }

        // By hand (params.noSignal: { appId, kind, format }), for a preview of each case.
        function showNoSignal(info) {
            enterBanner();
            bannerApp = info.appId || "";
            bannerState = "";
            pillShown = false;
            noSignalFormat = info.format || "";
            openNoSignal(info.kind || "", true);
            service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
        }

        function openNoSignal(kind, preview) {
            stayOpen();
            pillTimer.stop();
            signalCheck.stop();
            pillShown = false;
            noSignalApp = bannerApp;
            noSignalCase = kind;
            noSignalPreview = preview === true;
            noSignalSince = Date.now();
            wakeSince = Date.now();
            noSignalLeft = -1;
            backToNoSignal = false;
            pickNoSignalPicture();
            service.call("luna://com.webos.settingsservice", "/getSystemSettings",
                         JSON.stringify({ category: "time", keys: ["autoOff15Min", "noSignalAutoOff"] }));
            noSignalOpen = true;
            updateNoSignal();
        }

        // A picture of the launcher, the same for as long as the screen stands.
        function pickNoSignalPicture() {
            try {
                var request = new XMLHttpRequest();
                request.open("GET", Qt.resolvedUrl("launcher/backgrounds/index.json"), false);
                request.send();
                var list = JSON.parse(request.responseText);
                var entry = list[Math.floor(Math.random() * list.length)];
                noSignalPicture = Qt.resolvedUrl("launcher/backgrounds/" + entry.file);
                noSignalCredit = entry.credit || "";
            } catch (error) {
                noSignalPicture = "";
                noSignalCredit = "";
            }
        }

        function updateNoSignal() {
            if (!noSignalOpen) return;
            var device = deviceOf(noSignalApp);
            if (!device) {
                // The first answer is still on its way; a source without a port has nothing to wait for.
                if (devices.length > 0 && !noSignalPreview) closeNoSignal(false);
                return;
            }
            if (device.hdmiSignalExist && noSignalCase !== "format" && !noSignalPreview) {
                closeNoSignal(true);
                return;
            }
            var kind = noSignalCase;
            if (kind === "starting" && !noSignalPreview && Date.now() - wakeSince >= GlassStyle.noSignalWakeLimit) {
                kind = "unresponsive";
            }
            if (kind === "" || kind === "empty" || kind === "off" || kind === "silent") {
                kind = !device.hdmiPlugIn ? "empty" : deviceIsOff(device) ? "off" : "silent";
            }
            if (!device.hdmiPlugIn && !noSignalPreview) kind = "empty";
            presentNoSignal(kind, device);
        }

        function presentNoSignal(kind, device) {
            var port = "HDMI " + device.port;
            var name = deviceName(device);
            var tr = function (key, params) { return I18n.t("no_signal", key, params); };
            var action = function (id, key, icon) { return { id: id, label: tr(key), icon: icon || "" }; };
            var switchSource = action("switch", "action.switch_source", "nosignal-switch");
            var home = action("home", "action.home", "nosignal-home");
            var cases = {
                empty: { icon: "source-hdmi", title: tr("title.empty"), detail: tr("detail.empty", { port: port }),
                         actions: [switchSource, home] },
                off: { icon: deviceIcon(device), title: tr("title.off", { device: name }), detail: port,
                       actions: [action("turnOn", "action.turn_on", "nosignal-power"), switchSource] },
                silent: { icon: deviceIcon(device), title: tr("title.silent", { device: name }), detail: port,
                          actions: [switchSource, home] },
                // Only the way out, and no focus on it: the picture comes by itself.
                starting: { busy: true, title: tr("title.starting", { device: name }),
                            detail: tr("detail.starting", { port: port }), actions: [switchSource], focus: -1 },
                unresponsive: { icon: "source-alert", title: tr("title.unresponsive", { device: name }),
                                detail: tr("detail.unresponsive", { port: port }),
                                actions: [action("turnOn", "action.turn_on_again", "nosignal-power"), switchSource] },
                lost: { icon: deviceIcon(device), title: tr("title.off", { device: name }),
                        detail: tr("detail.lost", { port: port }),
                        actions: [action("tvOff", "action.tv_off", "nosignal-power"),
                                  action("turnOn", "action.turn_back_on")] },
                format: { icon: "nosignal-picture", title: tr("title.format"),
                          detail: noSignalFormat !== "" ? tr("detail.format", { device: name, format: noSignalFormat }) : port,
                          actions: [action("deepColor", "action.deep_color")] }
            };
            var entry = cases[kind] || cases.silent;
            var changed = kind !== noSignalCase || noSignalScreen.actions.length === 0;
            noSignalCase = kind;
            noSignalScreen.icon = entry.icon || "";
            noSignalScreen.busy = entry.busy === true;
            noSignalScreen.title = entry.title;
            noSignalScreen.detail = entry.detail;
            if (changed) {
                noSignalScreen.actions = entry.actions;
                noSignalScreen.focusIndex = entry.focus !== undefined ? entry.focus : 0;
            }
        }

        function noSignalAction(id) {
            if (id === "switch") {
                open();
            } else if (id === "home") {
                // Our launcher, as the home key opens it while novOS runs.
                service.call("luna://com.webos.service.systemUIManager", "/launch",
                             JSON.stringify({ appId: "com.webos.app.store-streamer" }));
                closeNoSignal(false);
                close();
            } else if (id === "turnOn") {
                var device = deviceOf(noSignalApp);
                if (!device) return;
                wakeSince = Date.now();
                presentNoSignal("starting", device);
                service.call("luna://com.webos.applicationManager", "/launch", NovosSettings.launchRequest(noSignalApp));
            } else if (id === "tvOff") {
                // Untested on the TV: the method of LG's public "turn off" command.
                service.call("luna://com.webos.service.tvpower/power", "/turnOffTV", "{}");
            } else if (id === "deepColor") {
                openSettingsPage("settings:sources");
            }
        }

        // LG keeps its own count; a key here only restarts ours (see docs, untested on the TV).
        function updateCountdown() {
            if (!noSignalOpen || !autoOff) {
                noSignalLeft = -1;
                return;
            }
            var left = noSignalSince + GlassStyle.noSignalOffDelay - Date.now();
            noSignalLeft = left <= GlassStyle.noSignalWarning ? Math.max(0, Math.ceil(left / 1000)) : -1;
        }

        // A picture arrived: the pill confirms it as after a switch.
        function closeNoSignal(arrived) {
            noSignalOpen = false;
            backToNoSignal = false;
            noSignalPreview = false;
            noSignalLeft = -1;
            if (arrived) {
                bannerApp = noSignalApp;
                signalChecks = 0;
                signalCheck.restart();
                updateBanner();
                openTimer.restart();
            } else {
                closeWhenIdle();
            }
        }

        // Back from the source bar that opened over the screen.
        function returnToNoSignal() {
            backToNoSignal = false;
            bannerMode = true;
            barShown = false;
            barFade.restart();
            forceActiveFocus();
            noSignalScreen.wake();
            service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
        }

        function close() {
            if (backToNoSignal && noSignalOpen && switchingApp === "") {
                returnToNoSignal();
                return;
            }
            if (closing) return;
            closing = true;
            noSignalOpen = false;
            backToNoSignal = false;
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
                if (updatePillOpen) updatePillShown = true;
                if (whatsNewOpen) whatsNew.shown = true;
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
                backToNoSignal = false;
                close();
            } else if (source.running) {
                close();
            } else {
                // Another source: the screen without a picture goes with the bar.
                backToNoSignal = false;
                noSignalOpen = false;
                switchingApp = source.appId;
                switched = source;
                switchChecks = 0;
                service.call("luna://com.webos.applicationManager", "/launch",
                             NovosSettings.launchRequest(source.appId));
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
            // "Neu in novOS" takes every key while it stands.
            if (bannerMode && whatsNewOpen) {
                if (!isBackKey(event.key) && !event.isAutoRepeat) whatsNew.handleKey(event.key);
                event.accepted = true;
                return;
            }
            if (bannerMode && noticeOpen && notice.buttons.length > 0) {
                if (noticeKey(event)) {
                    event.accepted = true;
                    return;
                }
            }
            if (bannerMode && updateScreenShown) {
                // Nothing to steer while novOS installs; the screen goes by itself.
                event.accepted = true;
                return;
            }
            // The screen without a picture takes every key; the source sends nothing anyway.
            if (bannerMode && noSignalOpen) {
                noSignalScreen.handleKey(event.key, event.isAutoRepeat);
                event.accepted = true;
                return;
            }
            // A key while the pill "Kein Signal" stands brings the screen at once.
            if (bannerMode && bannerState === "noSignal" && pillTimer.running) {
                openNoSignal("", false);
                event.accepted = true;
                return;
            }
            if (bannerMode) {
                rootWindow.webOSXInput.invokeFullKeyToAppAction(event.key, event.nativeScanCode, foregroundApp);
                // The update pill stays while the remote goes on to the source.
                if (!updatePillOpen || noticeOpen || bannerState !== "" || attributes.length > 0) close();
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
            if (bannerMode && whatsNewOpen) {
                if (isBackKey(event.key)) finishWhatsNew();
                event.accepted = true;
                return;
            }
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
                    if (picker.noSignalOpen && picker.bannerMode) picker.updateNoSignal();
                    else if (picker.bannerMode) picker.updateBanner();
                    else picker.placeFocus();
                } else if (method === "/getSystemSettings") {
                    // LG's switches for turning off without a signal; "off" in either ends the countdown.
                    var times = response.settings || {};
                    var values = [times.autoOff15Min, times.noSignalAutoOff];
                    picker.autoOff = values.indexOf("on") >= 0 && values.indexOf("off") < 0;
                    picker.updateCountdown();
                } else if (method === "/getStatus") {
                    picker.updateFormat(response.video && response.video[0]);
                } else if (method === "/getForegroundAppInfo") {
                    if (picker.updatePillOpen)
                        picker.updateOverHome = !response.appId || response.appId === "com.webos.app.home";
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

        // While the screen without a picture stands: LG's input status and the countdown.
        Timer {
            interval: GlassStyle.clockTick
            repeat: true
            running: picker.noSignalOpen && picker.bannerMode
            onTriggered: {
                picker.updateCountdown();
                if (picker.noSignalPreview) return;
                service.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
            }
        }

        Timer {
            id: pillTimer
            interval: 2200
            onTriggered: {
                if (!picker.bannerMode) {
                    picker.close();
                } else if (picker.bannerState === "noSignal" && !picker.noSignalOpen) {
                    picker.openNoSignal("", false);
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

        // The full screen while the source sends no picture; the pills and the bar lie above it.
        NoSignalScreen {
            id: noSignalScreen
            anchors.fill: parent
            unit: picker.unit
            titleFont: picker.titleFamily
            rowFont: picker.rowFamily
            valueFont: picker.valueFamily
            shown: picker.noSignalOpen
            // The bar, or LG's notice at the same place at the bottom, takes the row's place.
            covered: picker.barShown || picker.noticeShown
            pictureSource: picker.noSignalPicture
            pictureCredit: picker.noSignalCredit
            countdown: picker.noSignalLeft
            onActivated: picker.noSignalAction(id)
            onStayOn: {
                picker.noSignalSince = Date.now();
                picker.updateCountdown();
            }
        }

        // The source bar over that screen samples its photo, not the missing video.
        readonly property bool barOnPhoto: noSignalScreen.visible && !bannerMode

        ImageGlass {
            id: barPhotoGlass
            sourceItem: picker.barOnPhoto ? noSignalScreen.backdropItem : null
            unit: picker.unit
            area: picker.barArea
            visible: false
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
            backdrop: picker.barOnPhoto ? barPhotoGlass.texture : liveGlass.texture
            glassShader: liveGlass.glassShader
            backdropMargin: picker.barOnPhoto ? barPhotoGlass.margin : liveGlass.margin
            backdropArea: picker.barArea
            hasBackdrop: picker.barOnPhoto || liveGlass.hasFrame ? 1 : 0
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
                            color: GlassStyle.optionRing
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

        WhatsNew {
            id: whatsNew
            x: (picker.width - width) / 2
            y: (picker.height - height) / 2
            z: 5
            unit: picker.unit
            titleFont: picker.titleFamily
            rowFont: GlassStyle.rowFont
            valueFont: picker.valueFamily
            glassShader: liveGlass.glassShader
            backdrop: liveGlass.texture
            backdropMargin: liveGlass.margin
            backdropArea: Qt.rect(picker.pillArea.x - x, picker.pillArea.y - y,
                                  picker.pillArea.width, picker.pillArea.height)
            hasBackdrop: liveGlass.hasFrame ? 1 : 0
            onOpenItem: picker.openSettingsPage(item.open)
            onAllNews: picker.openSettingsPage("settings:info:update")
            onDone: picker.finishWhatsNew()
        }

        SetupBridge {
            id: updates
            folder: "/tmp/novos-update"
            active: picker.updatePillOpen
            onInfoChanged: picker.checkUpdatePill()
        }

        Timer {
            id: updatePillCheck
            interval: 3000      // the service may not have written its first state yet
            onTriggered: picker.checkUpdatePill()
        }

        // An updater that ends without a last word must not leave the black screen standing.
        Timer {
            id: updateScreenLimit
            interval: GlassStyle.updateScreenLimit
            onTriggered: picker.closeUpdatePill()
        }

        // K3-Update-5-Neustart in novOS: black with the boot light, the wordmark, the bar and
        // what happens. In place of the pill while LG's Home would be in front.
        Item {
            id: updateScreen
            anchors.fill: parent
            opacity: picker.updateScreenShown ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: GlassStyle.popoverDuration }
            }

            BootGlow {
                anchors.fill: parent
                pulsing: true
            }

            RestartScreen {
                anchors.fill: parent
                unit: picker.unit
                variant: "install"
                title: picker.updateLabel
                detail: I18n.t("picker", picker.updateInfo.phase === "restarting" ?
                                         "update.screen_restart" : "update.screen_detail")
                progress: picker.updateInfo.phase === "restarting" ? 1 : (picker.updateInfo.percent || 0) / 100
            }
        }

        ProgressPill {
            id: updatePill
            x: picker.width - width - 56 * picker.unit
            // LG's attribute pill sits at the top right too: then below it.
            y: 56 * picker.unit + (picker.attributesShown ? attributePill.height + 16 * picker.unit : 0)
            unit: picker.unit
            titleFont: picker.titleFamily
            valueFont: picker.valueFamily
            glassShader: liveGlass.glassShader
            backdrop: liveGlass.texture
            backdropMargin: liveGlass.margin
            backdropArea: Qt.rect(picker.pillArea.x - x, picker.pillArea.y - y,
                                  picker.pillArea.width, picker.pillArea.height)
            hasBackdrop: liveGlass.hasFrame ? 1 : 0
            label: picker.updateLabel
            value: I18n.t("picker", "update.percent", { percent: picker.updateInfo.percent || 0 })
            progress: (picker.updateInfo.percent || 0) / 100
            shown: picker.updatePillShown && !picker.updateOverHome
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
