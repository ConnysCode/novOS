import QtQuick 2.12
import QtQml 2.12
import SystemUIComponent 1.0
import WebOS.Global 1.0
import WebOSServices 1.0
import "module"
import "module/SourceList.js" as SourceList
import "module/ListScroll.js" as ListScroll

// Quick Settings panel, built to the Konzept 3 hand-off. All values are logical
// px on a 1920×1080 stage. Row values come from the TV. The two shortcuts write
// the same settings as LG's menu; the category rows only read so far.
StarfishSystemUIWindow {
    id: rootWindow
    objectName: "starfishSystemUIWindow"
    property string previewVersion: "0.3.0"
    property bool cursorVisible: false
    property bool opened: false
    // Performance probe, off outside perf-on-tv.sh (module/PerfProbe.qml).
    readonly property real perfCreated: PerfProbe.mark("window.create")

    Connections {
        target: rootWindow.lifeCycleStatus
        onLaunch: {
            PerfProbe.mark("launch", payload && payload.reason ? payload.reason : "");
            if (payload && payload.reason === "preload") {
                rootWindow.opened = false;
                rootWindow.exit();
            } else if (rootWindow.opened && payload && payload.params && String(payload.params.page || "").indexOf("settings") === 0) {
                // A long press of the gear key, or LG's settings app handing over: open the modal.
                var wanted = String(payload.params.page).split(":");
                panel.openSettings(wanted[1] || "picture", wanted[2] || "");
            } else if (rootWindow.opened) {
                panel.close();
            } else {
                webOSShell.setWindowProperty("delayCloseWindowTimeout", 1000);
                webOSShell.setWindowProperty("legacyWindowName", "quickSetting");
                webOSShell.setWindowProperty("_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
                rootWindow.show();
                rootWindow.opened = true;
                panel.launchPage = payload && payload.params && payload.params.page || panel.initialPage;
                panel.launch();
            }
        }
        onClose: {
            PerfProbe.mark("exit");
            PerfProbe.finish("exit");
            rootWindow.opened = false;
            rootWindow.exit();
        }
    }

    Connections {
        target: rootWindow.webOSInputManager
        onCursorVisibilityChanged: {
            rootWindow.cursorVisible = rootWindow.webOSInputManager.cursorVisibility;
        }
    }

    FocusScope {
        id: panel
        objectName: "GlassQuickSettings"
        anchors.fill: parent
        focus: true

        readonly property real unit: Math.min(width / 1920, height / 1080)
        readonly property real hairline: Math.max(1, unit)

        // Hand-off tokens.
        readonly property color textPrimary: GlassStyle.textPrimary
        readonly property color textSecondary: GlassStyle.textSecondary   // white 72 %
        readonly property color chevronIdle: "#80ffffff"     // white 50 %
        readonly property color separator: GlassStyle.separator       // white 12 %
        readonly property color hover: "#14ffffff"           // white 8 %
        readonly property color focusFill: GlassStyle.focusFill       // white 95 %
        readonly property color focusText: GlassStyle.focusText
        readonly property color focusSecondary: GlassStyle.focusSecondary
        readonly property real focusScale: GlassStyle.focusScale
        readonly property int focusDuration: GlassStyle.focusDuration
        readonly property int colorDuration: GlassStyle.colorDuration
        readonly property int panelDuration: 140
        readonly property int pageDuration: GlassStyle.pageDuration
        readonly property int popoverDuration: GlassStyle.popoverDuration
        readonly property int modalFadeDuration: 160
        readonly property real pageShift: GlassStyle.pageShift
        readonly property real dimmedOpacity: GlassStyle.dimmedOpacity
        readonly property var standardCurve: GlassStyle.curve

        // Panel frame on the stage.
        readonly property real panelInset: 56 * unit
        readonly property real panelWidth: 600 * unit
        readonly property real panelHeight: 968 * unit
        readonly property real panelX: width - panelInset - panelWidth
        readonly property real panelRadius: 48 * unit
        readonly property real panelPadding: 28 * unit
        readonly property real leftEdge: 48 * unit       // titles, section labels and row text

        // Backdrop. The crop reaches 56 px past the panel so the blur has real
        // content to fade into at the edges.
        readonly property real backdropMargin: 56 * unit
        readonly property rect panelArea: Qt.rect(panelX, panelInset, panelWidth, panelHeight)
        readonly property rect modalArea: Qt.rect((width - 1200 * unit) / 2, (height - 740 * unit) / 2,
                                                  1200 * unit, 740 * unit)
        // Wide enough for the panel and the value popovers beside it.
        readonly property rect sideArea: Qt.rect(840 * unit, panelInset, width - 896 * unit, panelHeight)
        // The large settings modal, 1680 × 920 in the centre (K3-Einstellungen).
        readonly property rect settingsArea: Qt.rect((width - 1680 * unit) / 2, (height - 920 * unit) / 2,
                                                     1680 * unit, 920 * unit)
        // The game bar along the top edge and its genre list below it (module/GameBar.qml).
        readonly property rect gameArea: Qt.rect(panelInset, 40 * unit, width - 2 * panelInset, 620 * unit)
        readonly property rect backdropArea: !modalBackdrop ? (mode === "game" ? gameArea : sideArea)
                                                            : (settingsBackdrop ? settingsArea : modalArea)
        // Three times the hand-off's 28 px: it hides the low capture rate at no
        // measurable extra CPU load.
        readonly property int openTimeout: 900
        readonly property int backlightStep: 5

        property int initialFocus: 2           // the cog to the settings modal
        property int focusIndex: initialFocus
        property int overviewFocus: 0
        property string page: "overview"
        property string popover: ""      // key of the shortcut whose control is open
        property string popoverContent: "backlight"   // stays while it fades out
        property int lastShortcut: 0
        property bool leftConsumed: false
        property bool closing: false
        property bool panelShown: false
        property string initialPage: ""     // preview only: page to open at once
        property string launchPage: ""      // page asked for by the launch, for example the source picker
        property bool panelHidden: false    // a modal stands in the screen centre
        // The one rule for every popover: the row that opened it stays as it is,
        // everything else in the panel steps back to this opacity.
        property real stepBack: choicePopover.shown || popover !== "" ? dimmedOpacity : 1
        Behavior on stepBack { NumberAnimation { duration: panel.popoverDuration } }
        property bool modalNeeded: false
        property bool pagesNeeded: false
        // Pages not on screen are drawn once beyond the screen edge, which uploads their
        // glyphs before the first visit, and then leave the scene entirely. Stacked inside
        // the panel even a trace of opacity would show on dark glass.
        property bool pagesWarm: false
        readonly property real warmOffset: 3000 * unit
        readonly property int warmDuration: 120
        // Subpages built so far: when the focus has rested on the row that opens one, or once
        // it opened. The rest stays unbuilt (docs/performance-plan.md).
        property var pagesWanted: []
        onFocusIndexChanged: pageWarm.restart()
        onPageChanged: pageWarm.restart()
        readonly property bool modalActive: modalLoader.item !== null && modalLoader.item.active
        property bool settingsNeeded: false
        readonly property bool settingsActive: settingsLoader.item !== null && settingsLoader.item.active
        property bool settingsBackdrop: false   // the glass samples the area of the settings modal
        // Opened for the settings modal alone (long press of the gear key, LG's settings app):
        // the panel never shows, and leaving the modal closes the window.
        property bool settingsLaunch: false
        // While a game runs the gear key shows the game bar instead of the panel
        // (docs/game-overlay-plan.md). "panel" or "game".
        property string mode: "panel"
        property bool fromGame: false         // the panel came from the bar: Back on its overview returns
        property string gameFocus: ""         // the action the bar opens on, "" for the genre
        property var pendingSettings: null   // the modal was asked for and is still being built
        property var pendingFlow: []          // work for the flow, which is still being built
        property bool flowWaiting: false      // a flow the user asked for is still being built
        property var modalSwitching: null       // a profile the settings switch to, for the switch screen
        property real modalSwitchStarted: 0
        property string profileNameFor: ""      // the profile whose name the name entry edits
        property string settingsConfirm: ""     // action a confirmation of the modal runs
        property var settingsConfirmParams: ({})
        property bool modalBackdrop: false  // the glass samples the screen centre
        // A modal lies on the dimmed picture: the modal scrim (none when the panel never
        // stood, see settingsLaunch), and for the settings modal its own dimming on top.
        // The glass takes all of it beyond the content scrim.
        readonly property real modalVeil: {
            if (!modalBackdrop) return 0;
            var sheet = settingsLoader.item;
            var total = settingsLaunch || mode === "game" ? 0 : GlassStyle.modalScrim;
            if (settingsBackdrop && sheet !== null) total = GlassStyle.stackScrims(total, sheet.backdropVeil);
            return GlassStyle.veilBeyondContent(total) * (1 - settingsPicture);
        }
        // The settings modal's band editor stands over the bare picture (module/BandEditor.qml):
        // 0 to 1 while the modal's card steps aside, the dimming goes with it.
        readonly property real settingsPicture: settingsBackdrop && settingsLoader.item !== null ?
                                                settingsLoader.item.pictureShare : 0
        property real panelFade: panelHidden ? 0 : 1
        Behavior on panelFade { NumberAnimation { duration: panel.modalFadeDuration } }

        // Two shortcut icons top right beside the title, then the design's categories.
        readonly property var rows: [
            { key: "backlight", png: "backlight", title: settingsStore.title("picture.backlight"), icon: true, x: 412, w: 64, h: 64, y: 34 },
            { key: "eyeComfort", png: "eyeComfort", title: settingsStore.title("picture.eyeComfortMode"), icon: true, x: 488, w: 64, h: 64, y: 34 },
            // Opens the large settings modal. Left of the two shortcuts, last in the array so
            // that the indices of the shortcuts stay as they were.
            { key: "allSettings", png: "allSettings", title: I18n.t("panel", "row.all_settings"), icon: true, x: 336, w: 64, h: 64, y: 34 },
            { key: "picture", png: "picture", title: settingsStore.areaTitle("picture"), y: 122 },
            { key: "sound", png: "sound", title: settingsStore.areaTitle("sound"), y: 192 },
            { key: "sources", png: "sources", title: settingsStore.areaTitle("sources"), y: 262 },
            { key: "network", png: "network", title: settingsStore.areaTitle("network"), y: 351 },
            // The active profile's avatar instead of the icon, its name as the value.
            { key: "profiles", png: "accounts", title: I18n.t("profile", "row.profiles"), y: 421 },
            { key: "apps", png: "apps", title: I18n.t("panel", "row.apps"), y: 491 },
            { key: "smartHome", png: "smartHome", title: I18n.t("panel", "row.smart_home"), y: 561 },
            { key: "accessibility", png: "accessibility", title: settingsStore.areaTitle("accessibility"), y: 650 },
            { key: "energy", png: "energy", title: settingsStore.areaTitle("energy"), y: 720 },
            { key: "system", png: "system", title: settingsStore.areaTitle("system"), y: 790 },
            { key: "debug", png: "debug", title: I18n.t("panel", "row.debug"), y: 860 }
        ]
        readonly property int rowHeight: 68
        readonly property int firstCategory: 3

        // Current TV state. Empty until the TV has answered.
        property string tvName: ""
        property string foregroundApp: ""
        onForegroundAppChanged: PerfProbe.mark("foreground", foregroundApp)
        property var sourceDevices: []
        property string detailDeviceId: ""        // the input on the device detail page, for example HDMI_3
        readonly property var detailDevice: deviceById(sourceDevices, detailDeviceId)
        readonly property var sourceDetailRows: buildSourceDetailRows(detailDevice)
        property string toastText: ""
        property string pendingToast: ""          // shown once eim confirms the change
        readonly property var sourceRows: buildSourceRows(sourceDevices, foregroundApp)
        property var pictureModes: []
        property string dynamicRange: ""
        readonly property var pictureRows: buildPictureRows(pictureModes, pictureMode)
        property string pictureMode: ""
        property int backlight: -1
        property bool backlightLocked: false    // LG blocks it in energy saving
        property string eyeComfort: ""
        property string soundOutput: ""
        property string soundMode: ""
        property var soundModes: []
        property bool hasArcDevice: false
        readonly property var soundRows: buildSoundRows(soundModes, soundMode, soundOutput, hasArcDevice)
        property int connectedInputs: -1
        property string networkState: ""        // wifi, wired or none
        property bool hasInternet: false
        property string networkName: ""
        property string networkAddress: ""
        property string networkGateway: ""
        property int networkFrequency: 0
        property int wifiBars: 0
        property int wifiProfile: 0
        property string audioGuidance: ""
        property string guidanceSpeed: ""
        property string highContrast: ""
        property string screenZoom: ""
        property string remotePointer: ""
        property string audioDescription: ""
        readonly property var accessRows: buildAccessRows(audioGuidance, highContrast, screenZoom, audioDescription,
                                                          remotePointer)
        property string modelName: ""
        property string softwareVersion: ""
        property string sdkVersion: ""
        property string countryCode: ""
        property string timezone: ""
        property var localeInfo: null
        property int languageIndex: 0
        property int languageScroll: 0
        property bool toastShown: false
        readonly property int languagesTop: 162
        readonly property int languagesHeight: 806
        readonly property int languagePitch: 72
        readonly property int languageLimit: Math.max(0, languages.length * languagePitch - 4 + 28 - languagesHeight)
        readonly property var languageFocusRow: ({ key: "languageChoice", x: 28, w: 544, h: 68,
                                                   y: languagesTop + languageIndex * languagePitch - languageScroll })
        // "german" is the name in the language of the TV; LanguagePage reads that field.
        readonly property var languages: [
            { code: "cs-CZ", name: "Čeština", german: I18n.t("panel", "language.czech") },
            { code: "da-DK", name: "Dansk", german: I18n.t("panel", "language.danish") },
            { code: "de-DE", name: "Deutsch", german: I18n.t("panel", "language.german") },
            { code: "en-GB", name: "English", german: I18n.t("panel", "language.english") },
            { code: "es-ES", name: "Español", german: I18n.t("panel", "language.spanish") },
            { code: "fr-FR", name: "Français", german: I18n.t("panel", "language.french") },
            { code: "hr-HR", name: "Hrvatski", german: I18n.t("panel", "language.croatian") },
            { code: "it-IT", name: "Italiano", german: I18n.t("panel", "language.italian") },
            { code: "hu-HU", name: "Magyar", german: I18n.t("panel", "language.hungarian") },
            { code: "nl-NL", name: "Nederlands", german: I18n.t("panel", "language.dutch") },
            { code: "nb-NO", name: "Norsk", german: I18n.t("panel", "language.norwegian") },
            { code: "pl-PL", name: "Polski", german: I18n.t("panel", "language.polish") },
            { code: "pt-PT", name: "Português", german: I18n.t("panel", "language.portuguese") },
            { code: "ro-RO", name: "Română", german: I18n.t("panel", "language.romanian") },
            { code: "sk-SK", name: "Slovenčina", german: I18n.t("panel", "language.slovak") },
            { code: "fi-FI", name: "Suomi", german: I18n.t("panel", "language.finnish") },
            { code: "sv-SE", name: "Svenska", german: I18n.t("panel", "language.swedish") },
            { code: "tr-TR", name: "Türkçe", german: I18n.t("panel", "language.turkish") },
            { code: "el-GR", name: "Ελληνικά", german: I18n.t("panel", "language.greek") },
            { code: "ru-RU", name: "Русский", german: I18n.t("panel", "language.russian") },
            { code: "uk-UA", name: "Українська", german: I18n.t("panel", "language.ukrainian") }
        ]
        readonly property string languageCode: localeInfo && localeInfo.locales ? localeInfo.locales.UI : ""
        // Try-outs that are changed live. Each row with min, max and step gets the
        // slider of the row delegate, with left and right as its keys.
        readonly property var debugRows: [
            { key: "debugBlur", title: I18n.t("panel", "row.blur_intensity"), y: 166, h: 104, plain: true,
              min: 20, max: 140, step: 4 },
            { key: "hideInputBanner", title: I18n.t("panel", "row.hide_lg_banner"), y: 316, h: 80, plain: true,
              sublabel: I18n.t("panel", "detail.hide_lg_banner"), toggle: NovosSettings.hideInputBanner },
            { key: "demoDevices", title: I18n.t("panel", "row.demo_devices"), y: 446, h: 80, plain: true,
              sublabel: I18n.t("panel", "detail.demo_devices"), toggle: NovosSettings.demoDevices },
            { key: "demoProfiles", title: I18n.t("panel", "row.demo_profiles"), y: 530, h: 80, plain: true,
              sublabel: I18n.t("panel", "detail.demo_profiles"), toggle: NovosSettings.demoProfiles }
        ]
        readonly property var systemRows: [
            { key: "tvName", title: settingsStore.text("network", "row.tv_name"), y: 226, h: 68 },
            { key: "language", title: settingsStore.text("system", "row.menu_language"), y: 714, h: 68 },
            { key: "reboot", title: I18n.t("panel", "row.restart"), y: 844, h: 68, plain: true }
        ]
        property string energySaving: ""
        property string quickStart: ""
        property string powerSound: ""          // LG's tvOnSound: off or a volume
        property int sleepSeconds: 0
        property bool onTimerEnabled: false
        property int onTimerHour: 0
        property int onTimerMinute: 0
        property string onTimerApp: ""
        property bool offTimerEnabled: false
        property int offTimerHour: 0
        property int offTimerMinute: 0
        property int clockTick: 0                 // re-evaluates the remaining time
        readonly property var energyRows: buildEnergyRows(sleepSeconds, quickStart, powerSound, clockTick)
        property var apps: []
        property string appsSignature: ""
        property int appIndex: 0
        property int appScroll: 0
        property var selectedApp: null
        property string removingApp: ""
        property int removeChecks: 0
        readonly property int appsTop: 162        // below title and subtitle
        readonly property int appsHeight: 806
        readonly property int appPitch: 100
        readonly property int appLimit: Math.max(0, apps.length * appPitch - 4 + 28 - appsHeight)
        readonly property var appFocusRow: ({ key: "app", x: 28, w: 544, h: 96,
                                              y: appsTop + appIndex * appPitch - appScroll })
        readonly property var appRows: buildAppRows(selectedApp)
        readonly property var networkRows: buildNetworkRows(networkState, wifiProfile)
        readonly property var networkInfo: buildNetworkInfo(networkState, wifiBars, networkAddress, networkGateway)
        readonly property var networkStatus: buildNetworkStatus(networkState, hasInternet, networkName, networkFrequency)

        readonly property var pictureModeHints: ({
            vivid: I18n.t("panel", "picture_hint.vivid"),
            normal: I18n.t("panel", "picture_hint.balanced"),
            standard: I18n.t("panel", "picture_hint.balanced"),
            eco: I18n.t("panel", "picture_hint.eco"),
            cinema: I18n.t("panel", "picture_hint.cinema"),
            cinemaBright: I18n.t("panel", "picture_hint.cinema_bright"),
            sports: I18n.t("panel", "picture_hint.sports"),
            game: I18n.t("panel", "picture_hint.game"),
            photo: I18n.t("panel", "picture_hint.photo"),
            filmMaker: I18n.t("panel", "picture_hint.filmmaker"),
            expert1: I18n.t("panel", "picture_hint.expert_bright"),
            expert2: I18n.t("panel", "picture_hint.expert_dark")
        })
        function pictureModeBase(value) {
            var base = value;
            if (value.indexOf("dolbyHdr") === 0) base = value.substring(8);
            else if (value.indexOf("hdr") === 0) base = value.substring(3);
            return base.charAt(0).toLowerCase() + base.substring(1);
        }

        // The TV lists the modes of the current signal. Personal modes need
        // LG's setup wizard first, so they are left out.
        function buildPictureRows(modes, current) {
            var result = [];
            for (var i = 0; i < modes.length; i++) {
                var mode = modes[i];
                var base = pictureModeBase(mode.value);
                if (!mode.visible || !mode.active || base === "personalized") continue;
                result.push({
                    key: "mode", value: mode.value, h: 84, y: 158 + result.length * 88,
                    title: settingsStore.label("picture.pictureMode", mode.value),
                    sublabel: pictureModeHints[base] || "",
                    active: mode.value === current
                });
            }
            return result;
        }

        // The TV lists every output it could drive, not what is plugged in. Only
        // outputs that certainly exist are offered, plus the current one.
        function buildSoundRows(modes, current, output, hasArc) {
            var outputs = ["tv_speaker"];
            if (hasArc) outputs.push("external_arc");
            if (output !== "" && outputs.indexOf(output) < 0) outputs.push(output);
            var result = [];
            var i;
            for (i = 0; i < outputs.length; i++) {
                result.push({
                    key: "soundOutput", value: outputs[i], h: 68, y: 166 + i * 72,
                    title: settingsStore.label("sound.soundOutput", outputs[i]),
                    active: outputs[i] === output
                });
            }
            var top = 372;
            for (i = 0; i < modes.length; i++) {
                var mode = modes[i];
                if (!mode.visible || !mode.active) continue;
                result.push({
                    key: "soundMode", value: mode.value, h: 68,
                    y: top, title: settingsStore.label("sound.soundMode", mode.value),
                    active: mode.value === current
                });
                top += 72;
            }
            return result;
        }

        function selectSound(setting, value) {
            var values = {};
            values[setting] = value;
            if (setting === "soundMode") soundMode = value;
            else soundOutput = value;
            settingsStore.set("sound." + setting, value);
        }

        function selectPictureMode(value) {
            if (value === pictureMode) return;
            pictureMode = value;
            writePicture({ pictureMode: value });
        }

        function buildNetworkStatus(state, internet, name, frequency) {
            if (state === "wired") {
                return { icon: "lan-32", title: I18n.t("panel", "status.wired"),
                         detail: internet ? I18n.t("panel", "status.lan_internet") :
                                            I18n.t("panel", "status.lan_no_internet") };
            }
            if (state === "wifi" && !internet) {
                return { icon: "wifi-32", title: I18n.t("panel", "status.no_internet"),
                         detail: I18n.t("panel", "status.router_offline", { name: name }) };
            }
            if (state === "wifi") {
                var band = frequency <= 0 ? "" : (frequency < 3000 ? I18n.t("panel", "value.band_2_4_ghz") :
                                                  (frequency < 5925 ? "5 GHz" : "6 GHz"));
                return { icon: "wifi-32", title: I18n.t("panel", "status.connected_to", { name: name }),
                         detail: band === "" ? I18n.t("panel", "status.wifi_internet") :
                                               I18n.t("panel", "status.wifi_band_internet", { band: band }) };
            }
            return { icon: "wifi-off-32", title: I18n.t("panel", "status.not_connected"),
                     detail: I18n.t("panel", "status.nothing_connected") };
        }

        function buildNetworkInfo(state, bars, address, gateway) {
            var signal = "–";
            if (state === "wired") signal = I18n.t("panel", "value.cable");
            else if (state === "wifi") signal = bars >= 3 ? I18n.t("panel", "value.signal_very_good") :
                                                (bars === 2 ? I18n.t("panel", "value.signal_good") :
                                                              I18n.t("panel", "value.signal_weak"));
            return [{ label: I18n.t("panel", "label.signal"), value: signal, y: 310 },
                    { label: I18n.t("panel", "label.ip_address"), value: address === "" ? "–" : address, y: 370 },
                    { label: I18n.t("panel", "label.gateway"), value: gateway === "" ? "–" : gateway, y: 430 }];
        }

        // Forgetting only exists for the Wi-Fi the TV is connected to.
        function buildNetworkRows(state, profile) {
            var result = [];
            if (state === "wired") {
                result.push({ key: "wifiChange", title: I18n.t("panel", "row.change_wifi"), y: 548, h: 80,
                              sublabel: I18n.t("panel", "detail.cable_priority") });
            } else {
                result.push({ key: "wifiChange", title: I18n.t("panel", "row.change_wifi"), y: 548, h: 68 });
            }
            if (state === "wifi" && profile > 0) {
                result.push({ key: "wifiForget", title: I18n.t("panel", "row.forget_network"), y: 620, h: 68, danger: true });
            }
            return result;
        }

        // ---- Profiles (K3-Profil-Panel-Seite) -----------------------------------------
        // The active profile in a card, then the other profiles signed in on this TV (OK
        // switches at once), "Profil hinzufügen", and two ways into the settings' area.
        readonly property int profileListTop: 310
        readonly property int profileLimit: 4      // more live in the settings' area
        readonly property var profileRows: buildProfileRows(profileStore.others, profileStore.active)
        readonly property var profileLabels: {
            var others = Math.min(profileStore.others.length, profileLimit);
            var labels = [{ text: I18n.t("profile", "section.switch_to"), y: 280 }];
            if (profileStore.active) {
                labels.push({ text: profileStore.active.nick, y: profileListTop + (others + 1) * 72 + 30 });
            }
            return labels;
        }

        function buildProfileRows(others, current) {
            var result = [];
            var y = profileListTop;
            for (var i = 0; i < others.length && i < profileLimit; i++) {
                result.push({ key: "profileSwitch", userNo: others[i].userNo, title: others[i].nick, y: y, h: 68,
                              avatar: { initial: others[i].initial, tint: others[i].tint }, avatarSize: 40,
                              plain: true });
                y += 72;
            }
            result.push({ key: "profileAdd", title: I18n.t("profile", "row.add"), png: "add", y: y, h: 68, plain: true });
            if (!current) return result;
            y += 72 + 60;
            result.push({ key: "profileEdit", title: I18n.t("profile", "row.edit"), y: y, h: 68 });
            result.push({ key: "profileAll", title: I18n.t("profile", "row.all_settings"), y: y + 72, h: 68 });
            return result;
        }

        function profileType(profile) {
            if (!profile) return "";
            var type = profile.accountType === "LGE" ? "type.lge" :
                       (profile.accountType === "GGL" ? "type.ggl" : "type.other");
            return I18n.t("profile", type);
        }

        // OK on a profile switches at once; the black switch screen covers the change.
        function switchProfile(userNo) {
            profileStore.switchTo(userNo);
        }

        readonly property var sleepMinutes: settingsStore.sleepChoices

        function clockText(hour, minute) {
            return (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute;
        }

        // Texts with a number have one key for exactly one and one for any other count.
        function countText(key, count, params) {
            var values = params || {};
            values.count = count;
            return I18n.t("panel", key + (count === 1 ? "_one" : "_other"), values);
        }

        // The TV only reports the time left, so the chosen length is the next step up.
        function sleepChoice(seconds) {
            var minutes = Math.ceil(seconds / 60);
            if (minutes <= 0) return 0;
            for (var i = 1; i < sleepMinutes.length; i++) {
                if (minutes <= sleepMinutes[i]) return sleepMinutes[i];
            }
            return minutes;
        }

        function buildEnergyRows(seconds, start, sound, tick) {
            var result = [{ key: "energySaving", title: settingsStore.title("picture.energySaving"), y: 166, h: 68,
                            opens: true }];
            var top = 296;
            if (seconds > 0) {
                var end = new Date(Date.now() + seconds * 1000);
                result.push({ key: "sleepTimer", title: settingsStore.text("energy", "row.sleep_timer"), y: top, h: 80, opens: true,
                              sublabel: countText("detail.sleep_off_at", sleepChoice(seconds),
                                                  { time: clockText(end.getHours(), end.getMinutes()) }) });
                top += 84;
            } else {
                result.push({ key: "sleepTimer", title: settingsStore.text("energy", "row.sleep_timer"), y: top, h: 68,
                              opens: true });
                top += 72;
            }
            result.push({ key: "onTimer", title: settingsStore.text("energy", "row.on_timer"), y: top, h: 68, opens: true });
            result.push({ key: "offTimer", title: settingsStore.text("energy", "row.off_timer"), y: top + 72, h: 68,
                          opens: true });
            top += 202;
            result.push({ key: "screenOff", title: settingsStore.text("energy", "row.screen_off"), y: top, h: 68, plain: true });
            result.push({ key: "quickStart", title: settingsStore.title("option.quickStartMode"), y: top + 72, h: 80,
                          plain: true, sublabel: I18n.t("panel", "detail.quick_start"),
                          toggle: start === "on" });
            result.push({ key: "powerSound", title: I18n.t("panel", "row.power_sound"), y: top + 156, h: 80,
                          plain: true, sublabel: I18n.t("panel", "detail.power_sound"),
                          toggle: sound !== "" && sound !== "off" });
            return result;
        }

        function labelsOf(entry) {
            if (entry.key === "profiles") return profileLabels;
            if (entry.key === "access") {
                var offset = audioGuidance === "on" ? 0 : 12;
                return [{ text: I18n.t("panel", "section.speech"), y: 134 },
                        { text: I18n.t("panel", "section.vision"), y: 348 + offset },
                        { text: I18n.t("panel", "section.hearing"), y: 550 + offset },
                        { text: I18n.t("panel", "section.remote"), y: 680 + offset }];
            }
            if (entry.key !== "energy") return entry.labels || [];
            var shift = sleepSeconds > 0 ? 12 : 0;
            return [{ text: I18n.t("panel", "section.energy"), y: 134 },
                    { text: I18n.t("panel", "section.timer"), y: 264 },
                    { text: I18n.t("panel", "section.screen_start"), y: 538 + shift }];
        }

        // Screen position of a row, for the popover beside it.
        function rowCentre(row) {
            return panel.panelInset + (row.y + rowHeightOf(row) / 2) * unit;
        }

        function openChoice(row) {
            if (row.key === "energySaving") {
                var values = [];
                ["auto", "off", "min", "med", "max"].forEach(function (value) {
                    values.push({ value: value, label: settingsStore.label("picture.energySaving", value) });
                });
                choicePopover.openList(settingsStore.title("picture.energySaving"), values, energySaving, rowCentre(row));
            } else if (row.key === "guidanceSpeed") {
                var speeds = ["verySlow", "slow", "medium", "fast", "veryFast"].map(function (value) {
                    return { value: value, label: settingsStore.label("option.audioGuidanceSpeed", value) };
                });
                choicePopover.openList(settingsStore.title("option.audioGuidanceSpeed"), speeds, guidanceSpeed, rowCentre(row));
            } else if (row.key === "sleepTimer") {
                var minutes = sleepMinutes.map(function (value) {
                    return { value: String(value),
                             label: settingsStore.minutesLabel(value) };
                });
                choicePopover.openList(settingsStore.text("energy", "row.sleep_timer"), minutes, String(sleepChoice(sleepSeconds)), rowCentre(row));
            } else if (row.key === "deviceIcon") {
                var types = SourceList.iconChoices.map(function (choice) {
                    return { value: choice.value, label: typeName(choice) };
                });
                choicePopover.openList(I18n.t("panel", "row.device_type"), types,
                                       SourceList.iconChoice(detailDevice).value, rowCentre(row));
            } else if (row.key === "onTimer") {
                choicePopover.openTime(settingsStore.text("energy", "row.on_timer"), onTimerHour, onTimerMinute, rowCentre(row));
            } else {
                choicePopover.openTime(settingsStore.text("energy", "row.off_timer"), offTimerHour, offTimerMinute, rowCentre(row));
            }
        }

        function applyChoice(value) {
            if (focusedRow.key === "energySaving") {
                energySaving = value;
                writePicture({ energySaving: value });
            } else if (focusedRow.key === "guidanceSpeed") {
                guidanceSpeed = value;
                writeOption("audioGuidanceSpeed", value);
            } else if (focusedRow.key === "deviceIcon") {
                saveDeviceIcon(value);
            } else {
                setSleepTimer(value);
            }
            choicePopover.close();
        }

        function setSleepTimer(minutes) {
            sleepSeconds = Number(minutes) * 60;
            backdropService.call("luna://com.webos.service.tvReservationAgent/timer/sleep", "/add",
                                 JSON.stringify({ sleepTimeMinute: minutes }));
        }

        function readSleepTimer() {
            backdropService.call("luna://com.webos.service.tvReservationAgent/timer/sleep",
                                 "/getRemainTime", "{}");
        }

        function writeTimer(values) {
            settingsStore.setAll("time", values);
        }

        function applyTimer(hour, minute) {
            if (focusedRow.key === "onTimer") {
                onTimerEnabled = true;
                onTimerHour = hour;
                onTimerMinute = minute;
                var values = { onTimerEnable: "on", onTimerHour: String(hour), onTimerMinute: String(minute) };
                // A TV without a tuned channel cannot start on Live TV.
                if (onTimerApp === "com.webos.app.livetv") {
                    onTimerApp = "com.webos.app.home";
                    values.onTimerAppId = onTimerApp;
                }
                writeTimer(values);
            } else {
                offTimerEnabled = true;
                offTimerHour = hour;
                offTimerMinute = minute;
                writeTimer({ offTimerEnable: "on", offTimerHour: String(hour), offTimerMinute: String(minute) });
            }
            choicePopover.close();
        }

        function disableTimer() {
            if (focusedRow.key === "onTimer") {
                onTimerEnabled = false;
                writeTimer({ onTimerEnable: "off" });
            } else {
                offTimerEnabled = false;
                writeTimer({ offTimerEnable: "off" });
            }
            choicePopover.close();
        }

        function toggleQuickStart() {
            quickStart = quickStart === "on" ? "off" : "on";
            settingsStore.set("option.quickStartMode", quickStart);
        }

        // LG knows only a volume for the sound at power on and off. On brings back
        // LG's default level.
        function togglePowerSound() {
            powerSound = powerSound !== "" && powerSound !== "off" ? "off" : "low";
            settingsStore.set("general.tvOnSound", powerSound);
        }

        function askScreenOff() {
            withFlow(function (flow) {
                flow.openDialog({
                    action: "screenOff", icon: "screen-off-44", confirm: I18n.t("panel", "modal.screen_off_confirm"),
                    safe: true, title: I18n.t("panel", "modal.screen_off_title"),
                    busyTitle: I18n.t("panel", "modal.screen_off_busy"),
                    text: I18n.t("panel", "modal.screen_off_text")
                });
            });
        }

        function runDialogAction(action) {
            if (action === "settings") {
                settingsLoader.item.confirmed(settingsConfirm, settingsConfirmParams);
                if (flow()) flow().closeFlow();
            } else if (action === "removeApp") {
                removeApp();
            } else if (action === "reboot") {
                backdropService.call("luna://com.webos.service.tvpower/power2", "/reboot",
                                     JSON.stringify({ reason: "reset" }));
            } else if (action === "screenOff") {
                backdropService.call("luna://com.webos.service.tvpower/power", "/turnOffScreen", "{}");
                if (flow()) flow().closeFlow();
                close();
            }
        }

        function sizeText(bytes) {
            if (!bytes) return "";
            var megabytes = bytes / 1048576;
            if (megabytes < 1000) return Math.max(1, Math.round(megabytes)) + " MB";
            return (megabytes / 1024).toFixed(1).replace(".", Qt.locale(I18n.qtLocale).decimalPoint) + " GB";
        }

        // Only some apps report a size, so it shows where it is known.
        function buildApps(list) {
            var result = [];
            for (var i = 0; i < list.length; i++) {
                var app = list[i];
                if (!app.visible || !app.title) continue;
                var file = app.largeIcon || app.icon || "";
                var size = sizeText(app.appsize);
                result.push({
                    id: app.id, title: app.title, version: app.version || "", size: size,
                    removable: app.removable === true,
                    detail: app.removable ? size :
                            (size !== "" ? I18n.t("panel", "detail.preinstalled_size", { size: size }) :
                                           I18n.t("panel", "detail.preinstalled")),
                    iconPath: file === "" ? "" :
                              "file://" + (file.charAt(0) === "/" ? file : app.folderPath + "/" + file)
                });
            }
            result.sort(function (a, b) { return a.title.localeCompare(b.title); });
            return result.slice(0, 60);
        }

        function buildAppInfo(app) {
            if (!app) return [];
            var info = [{ label: I18n.t("panel", "label.version"), value: app.version, y: 374 }];
            if (app.size !== "") info.push({ label: I18n.t("panel", "label.storage"), value: app.size, y: 434 });
            return info;
        }

        function buildAppRows(app) {
            if (!app) return [];
            var top = app.size !== "" ? 522 : 462;
            var result = [{ key: "appStart", title: I18n.t("panel", "row.start_app"), y: top, h: 68, plain: true }];
            if (app.removable) {
                result.push({ key: "appRemove", title: I18n.t("global", "remove"), y: top + 72, h: 68, danger: true });
            }
            return result;
        }

        function buildAccessRows(guidance, contrast, zoom, description, pointer) {
            var shift = guidance === "on" ? 0 : 12;
            var result = [{ key: "audioGuidance", title: settingsStore.title("option.audioGuidance"), y: 166, h: 80,
                            plain: true, sublabel: I18n.t("panel", "detail.audio_guidance"),
                            toggle: guidance === "on" }];
            if (guidance === "on") {
                result.push({ key: "guidanceSpeed", title: settingsStore.title("option.audioGuidanceSpeed"), y: 250, h: 68,
                              opens: true });
            }
            result.push({ key: "highContrast", title: settingsStore.title("option.highContrast"), y: 380 + shift, h: 68, plain: true,
                          toggle: contrast === "on" });
            result.push({ key: "screenZoom", title: settingsStore.title("option.screenMagnification"), y: 452 + shift, h: 68, plain: true,
                          toggle: zoom === "on" });
            result.push({ key: "audioDescription", title: settingsStore.title("sound.audioDescription"), y: 582 + shift,
                          h: 80, plain: true, sublabel: I18n.t("panel", "detail.audio_description"),
                          toggle: description === "on" });
            result.push({ key: "remotePointer", title: I18n.t("panel", "row.remote_pointer"), y: 712 + shift,
                          h: 80, plain: true, sublabel: I18n.t("panel", "detail.remote_pointer"),
                          toggle: pointer !== "off" });
            return result;
        }

        // As LG names it, plus the platform release with its build: "webOS25 / 10.3.2-33".
        // LG counts the marketing name from the platform: 10.x is webOS 25.
        function webOSLabel(sdkVersion) {
            var release = sdkVersion;
            try {
                var request = new XMLHttpRequest();
                request.open("GET", "file:///var/run/nyx/os_info.json", false);
                request.send();
                release = JSON.parse(request.responseText).core_os_release || sdkVersion;
            } catch (error) {
                release = sdkVersion;
            }
            var major = parseInt(release, 10);
            return isNaN(major) ? release : "webOS" + (major + 15) + " / " + release;
        }

        function sliderValue(key) {
            return key === "debugBlur" ? GlassStyle.blur : 0;
        }

        function adjustSlider(row, direction) {
            var value = Math.max(row.min, Math.min(row.max, sliderValue(row.key) + direction * row.step));
            if (row.key === "debugBlur") GlassStyle.blur = value;
        }

        function toggleOption(property, key) {
            panel[property] = panel[property] === "on" ? "off" : "on";
            writeOption(key, panel[property]);
            // Switched on here, the guide speaks the new state right away.
            if (key === "audioGuidance") guide.setting = panel[property];
        }

        function writeOption(key, value) {
            settingsStore.set("option." + key, value);
        }

        function toggleRemotePointer() {
            remotePointer = remotePointer === "off" ? "on" : "off";
            settingsStore.set("general.remotePointer", remotePointer);
        }

        function toggleAudioDescription() {
            audioDescription = audioDescription === "on" ? "off" : "on";
            settingsStore.set("sound.audioDescription", audioDescription);
        }

        function countryName(code) {
            var names = { DEU: I18n.t("panel", "value.germany"), AUT: I18n.t("panel", "value.austria"),
                          CHE: I18n.t("panel", "value.switzerland") };
            return names[code] || code;
        }

        function timezoneName(zone) {
            if (zone === "Europe/Berlin") return I18n.t("panel", "value.timezone_berlin");
            return zone.substring(zone.lastIndexOf("/") + 1).replace(/_/g, " ");
        }

        // A software update can cost the root access, so this page only informs.
        function buildSystemInfo() {
            return [{ label: I18n.t("panel", "label.model"), value: modelName, y: 166 },
                    { label: I18n.t("panel", "label.software"), value: softwareVersion, y: 356 },
                    { label: I18n.t("panel", "label.webos_version"), value: sdkVersion, y: 416 },
                    { label: I18n.t("panel", "label.software_update"), value: I18n.t("panel", "value.not_checked"),
                      y: 476 },
                    { label: I18n.t("panel", "label.country"), value: countryName(countryCode), y: 594 },
                    { label: I18n.t("panel", "label.timezone"), value: timezoneName(timezone), y: 654 }];
        }

        function languageName(code) {
            for (var i = 0; i < languages.length; i++) {
                if (languages[i].code === code) return languages[i].name;
            }
            return code;
        }

        function openLanguages() {
            for (var i = 0; i < languages.length; i++) {
                if (languages[i].code === languageCode) languageIndex = i;
            }
            moveLanguage(0);
            changePage("languages", 0);
        }

        function moveLanguage(step) {
            languageIndex = Math.max(0, Math.min(languages.length - 1, languageIndex + step));
            languageScroll = ListScroll.centred(languageIndex * languagePitch, languagePitch - 4, languagesHeight,
                                                languageLimit + languagesHeight);
        }

        // Same fields as LG's language list. The audio language stays as it is.
        function selectLanguage() {
            var code = languages[languageIndex].code;
            if (!localeInfo || code === languageCode) return;
            var next = JSON.parse(JSON.stringify(localeInfo));
            next.locales.UI = code;
            next.locales.FMT = code;
            next.locales.TV = code;
            var keyboard = code.split("-")[0];
            next.keyboards = keyboard === "en" ? ["en"] : ["en", keyboard];
            localeInfo = next;
            backdropService.call("luna://com.webos.settingsservice", "/setSystemSettings",
                                 JSON.stringify({ settings: { localeInfo: next } }));
        }

        // The name entry is the panel's; the settings own the profile store that writes it.
        function saveProfileName(name) {
            if (settingsLoader.item && profileNameFor !== "") {
                settingsLoader.item.confirmed("profileRename", { userNo: profileNameFor, nick: name });
            }
        }

        function saveTvName(name) {
            tvName = name;
            settingsStore.set("network.deviceName", "[LG] " + name);
            showToast(I18n.t("panel", "toast.tv_name_saved"));
        }

        function askReboot() {
            withFlow(function (flow) {
                flow.openDialog({
                    action: "reboot", icon: "refresh-44", confirm: I18n.t("panel", "row.restart"),
                    title: I18n.t("panel", "modal.restart_title"), busyTitle: I18n.t("panel", "modal.restart_busy"),
                    text: I18n.t("panel", "modal.restart_text")
                });
            });
        }

        function infoRowsOf(name) {
            if (name === "network") return networkInfo;
            if (name === "system") return buildSystemInfo();
            if (name === "appDetail") return buildAppInfo(selectedApp);
            if (name === "sourceDetail") return buildSourceInfo(detailDevice);
            return [];
        }

        function readApps() {
            backdropService.call("luna://com.webos.applicationManager", "/listApps", JSON.stringify({
                properties: ["id", "title", "icon", "largeIcon", "folderPath", "visible",
                             "removable", "version", "appsize"] }));
        }

        function applyApps(list) {
            var next = buildApps(list);
            var signature = JSON.stringify(next);
            if (signature !== appsSignature) {
                appsSignature = signature;
                apps = next;
            }
            appIndex = Math.max(0, Math.min(appIndex, apps.length - 1));
            if (removingApp === "") return;
            var gone = next.every(function (app) { return app.id !== removingApp; });
            if (gone) appRemoved();
        }

        function moveApp(step) {
            appIndex = Math.max(0, Math.min(apps.length - 1, appIndex + step));
            appScroll = ListScroll.centred(appIndex * appPitch, appPitch - 4, appsHeight, appLimit + appsHeight);
        }

        function openApp() {
            selectedApp = apps[appIndex] || null;
            if (selectedApp) changePage("appDetail", 0);
        }

        function askRemoveApp() {
            var texts = { name: selectedApp.title, size: selectedApp.size };
            var app = selectedApp;
            withFlow(function (flow) {
                flow.openDialog({
                    action: "removeApp", appIcon: app.iconPath, confirm: I18n.t("global", "remove"),
                    title: I18n.t("panel", "modal.remove_app_title", texts),
                    busyTitle: I18n.t("panel", "modal.remove_app_busy", texts),
                    text: app.size !== "" ? I18n.t("panel", "modal.remove_app_text_size", texts) :
                                            I18n.t("panel", "modal.remove_app_text")
                });
            });
        }

        function removeApp() {
            removingApp = selectedApp.id;
            removeChecks = 0;
            backdropService.call("luna://com.webos.appInstallService", "/remove",
                                 JSON.stringify({ id: removingApp }));
            removeCheck.restart();
        }

        function appRemoved() {
            removeCheck.stop();
            removingApp = "";
            selectedApp = null;
            changePage("apps", 0);
            moveApp(0);
            if (flow()) flow().closeFlow();
        }

        function removeFailed() {
            if (removingApp === "") return;
            removeCheck.stop();
            removingApp = "";
            if (flow()) flow().showError(I18n.t("panel", "modal.remove_app_failed"));
        }

        function rowValue(key) {
            if (key === "backlight") return backlight < 0 ? "" : String(backlight);
            if (key === "eyeComfort") {
                return eyeComfort === "" ? "" : I18n.t("global", eyeComfort === "on" ? "on" : "off");
            }
            if (key === "picture") return pictureMode === "" ? "" : settingsStore.label("picture.pictureMode", pictureMode);
            if (key === "sound") return soundOutput === "" ? "" : settingsStore.label("sound.soundOutput", soundOutput);
            if (key === "sources") return connectedInputs < 0 ? "" : countText("value.connected_count", connectedInputs);
            if (key === "network") {
                if (networkState === "wired") return "LAN";
                if (networkState === "wifi") return I18n.t("panel", "value.wifi");
                return networkState === "none" ? I18n.t("panel", "status.not_connected") : "";
            }
            if (key === "tvName") return tvName;
            if (key === "profiles") {
                if (!profileStore.known) return "";
                return profileStore.active ? profileStore.active.nick : I18n.t("profile", "value.not_signed_in");
            }
            if (key === "profileEdit") return I18n.t("profile", "value.edit");
            if (key === "deviceName") return detailDevice ? SourceList.deviceName(detailDevice) : "";
            if (key === "deviceIcon") return detailDevice ? typeName(SourceList.iconChoice(detailDevice)) : "";
            if (key === "debugBlur") return Math.round(GlassStyle.blur) + " px";
            if (key === "guidanceSpeed") return guidanceSpeed === "" ? "" : settingsStore.label("option.audioGuidanceSpeed", guidanceSpeed);
            if (key === "language") return languageName(languageCode);
            if (key === "energySaving") return energySaving === "" ? "" : settingsStore.label("picture.energySaving", energySaving);
            if (key === "sleepTimer") {
                return sleepSeconds > 0 ? I18n.t("panel", "value.sleep_remaining",
                                                 { minutes: Math.ceil(sleepSeconds / 60) }) :
                                          I18n.t("global", "off");
            }
            if (key === "onTimer") return onTimerEnabled ? clockText(onTimerHour, onTimerMinute) : I18n.t("global", "off");
            if (key === "offTimer") {
                return offTimerEnabled ? clockText(offTimerHour, offTimerMinute) : I18n.t("global", "off");
            }
            return "";
        }

        // ---- Audio-Guidance: what the focus says ----------------------------
        // The texts follow what the panel shows. The remaining sleep time is left
        // out, otherwise the focused row would speak again every minute.
        readonly property var focusSpeech: currentSpeech()
        onFocusSpeechChanged: guide.follow(focusSpeech)

        function spokenValue(row) {
            if (row.toggle !== undefined) return I18n.t("panel", row.toggle ? "speech.on" : "speech.off");
            if (row.key === "sleepTimer") return sleepSeconds > 0 ? "" : I18n.t("global", "off");
            if (row.key === "backlight" && backlightLocked) {
                return I18n.t("panel", "speech.value_locked", { value: rowValue(row.key) });
            }
            return rowValue(row.key);
        }

        function rowSpeech(row) {
            if (row.key === "app") {
                var app = apps[appIndex];
                return { subject: "app:" + (app ? app.id : ""),
                         text: app ? guide.sentence([app.title, app.detail]) : "" };
            }
            if (row.key === "languageChoice") {
                var language = languages[languageIndex];
                var chosen = language && language.code === languageCode ? I18n.t("panel", "speech.selected") : "";
                return { subject: "language:" + (language ? language.code : ""),
                         text: language ? guide.sentence([language.german, chosen]) : "", change: chosen };
            }
            var selected = row.active ? I18n.t("panel", "speech.selected") : "";
            var state = guide.sentence([spokenValue(row), selected]);
            return { subject: focusIndex + ":" + row.key + ":" + (row.value || row.appId || ""),
                     text: guide.sentence([row.title, spokenValue(row), row.sublabel || "", selected]),
                     change: state };
        }

        function infoSpeech(name) {
            return infoRowsOf(name).map(function (info) {
                return guide.sentence([info.label, info.value]);
            });
        }

        // Read once when a page opens: its title and what it only shows.
        function pageIntro(name) {
            if (name === "overview") return I18n.t("panel", "speech.quick_menu");
            if (name === "appDetail") {
                return guide.sentence([selectedApp ? selectedApp.title : "", I18n.t("panel", "title.app_details")].concat(
                                          infoSpeech(name)));
            }
            if (name === "sourceDetail") {
                return guide.sentence([detailDevice ? SourceList.deviceName(detailDevice) : "",
                                       I18n.t("panel", "title.device_details")].concat(infoSpeech(name)));
            }
            var title = "";
            for (var i = 0; i < subpages.length; i++) {
                if (subpages[i].key === name) title = subpages[i].title;
            }
            if (name === "network") {
                return guide.sentence([title, networkStatus.title, networkStatus.detail].concat(infoSpeech(name)),
                                      ". ");
            }
            if (name === "system") return guide.sentence([title].concat(infoSpeech(name)), ". ");
            if (name === "apps") return guide.sentence([title, countText("detail.app_count", apps.length)]);
            return title;
        }

        function popoverSpeech() {
            if (popover === "backlight") {
                var level = backlightLocked ? I18n.t("panel", "speech.backlight_locked") : rowValue("backlight");
                return { subject: "popover:backlight",
                         text: guide.sentence([settingsStore.title("picture.backlight"), level,
                                               I18n.t("panel", "speech.change_left_right")]),
                         change: level };
            }
            return { subject: "popover:eyeComfort",
                     text: guide.sentence([settingsStore.title("picture.eyeComfortMode"), rowValue("eyeComfort"),
                                           I18n.t("panel", "speech.ok_toggles")]),
                     change: rowValue("eyeComfort") };
        }

        function currentSpeech() {
            var focus = { context: page, intro: pageIntro(page), layer: "", layerIntro: "" };
            var part;
            if (modalActive) {
                part = modalLoader.item.speech;
                focus.layer = "modal:" + part.layer;
                focus.layerIntro = part.intro;
            } else if (settingsActive) {
                part = settingsLoader.item.speech;
                if (!part) return null;
                focus.context = "settings";
                focus.intro = part.intro || "";
                focus.layer = part.layer;
                focus.layerIntro = part.layerIntro || "";
            } else if (choicePopover.shown) {
                part = choicePopover.speech;
                focus.layer = "choice:" + choicePopover.title;
                focus.layerIntro = part.intro;
            } else if (popover !== "") {
                part = popoverSpeech();
            } else {
                part = rowSpeech(focusedRow);
            }
            focus.subject = part.subject;
            focus.text = part.text;
            focus.change = part.change;
            return focus;
        }

        readonly property var subpages: [
            { key: "sources", title: settingsStore.areaTitle("sources") },
            { key: "picture", title: I18n.t("panel", "title.picture_mode") },
            { key: "sound", title: settingsStore.areaTitle("sound"),
              labels: [{ text: I18n.t("panel", "section.sound_output"), y: 132 },
                       { text: I18n.t("panel", "section.sound_mode"), y: 338 }] },
            { key: "network", title: settingsStore.areaTitle("network"),
              labels: [{ text: I18n.t("panel", "section.connection"), y: 278 },
                       { text: I18n.t("panel", "section.wifi"), y: 516 }] },
            { key: "apps", title: I18n.t("panel", "row.apps") },
            { key: "profiles", title: I18n.t("profile", "title.profiles") },
            { key: "energy", title: settingsStore.areaTitle("energy") },
            { key: "access", title: settingsStore.areaTitle("accessibility") },
            { key: "debug", title: I18n.t("panel", "row.debug"),
              labels: [{ text: I18n.t("panel", "section.glass"), y: 134 },
                       { text: I18n.t("panel", "section.sources"), y: 284 }] },
            { key: "system", title: settingsStore.areaTitle("system"),
              labels: [{ text: I18n.t("panel", "section.device"), y: 134 },
                       { text: I18n.t("panel", "section.software"), y: 324 },
                       { text: I18n.t("panel", "section.region_language"), y: 562 },
                       { text: I18n.t("panel", "section.restart"), y: 812 }] },
            { key: "languages", title: settingsStore.text("system", "row.menu_language"), back: settingsStore.areaTitle("system") },
            { key: "appDetail", title: I18n.t("panel", "title.app_details"), back: I18n.t("panel", "row.apps"),
              labels: [{ text: I18n.t("panel", "section.info"), y: 342 }] },
            { key: "sourceDetail", title: I18n.t("panel", "title.device_details"), back: settingsStore.areaTitle("sources"),
              labels: [{ text: I18n.t("panel", "section.customize"), y: 420 },
                       { text: I18n.t("panel", "section.info"), y: 624 }] }
        ]
        readonly property var currentRows: rowsOfPage(page)
        readonly property var focusedRow: currentRows[focusIndex] || rows[0]

        function rowsOfPage(name) {
            if (name === "sources") return sourceRows;
            if (name === "picture") return pictureRows;
            if (name === "sound") return soundRows;
            if (name === "network") return networkRows;
            if (name === "profiles") return profileRows;
            if (name === "apps") return [appFocusRow];
            if (name === "appDetail") return appRows;
            if (name === "sourceDetail") return sourceDetailRows;
            if (name === "energy") return energyRows;
            if (name === "system") return systemRows;
            if (name === "debug") return debugRows;
            if (name === "access") return accessRows;
            if (name === "languages") return [languageFocusRow];
            return rows;
        }

        function rowHeightOf(row) {
            return row && row.h ? row.h : rowHeight;
        }

        function rowXOf(row) {
            return row && row.x ? row.x : 28;
        }

        function rowWidthOf(row) {
            return row && row.w ? row.w : 544;
        }

        function openPopover(key) {
            popoverContent = key;
            popover = key;
        }

        // Named devices first, as in the design. Home is always reachable.
        function buildSourceRows(devices, activeApp) {
            var named = [];
            var plain = [];
            for (var i = 0; i < devices.length; i++) {
                var device = devices[i];
                (device.label.indexOf("HDMI") === 0 ? plain : named).push(device);
            }
            var result = [];
            var ordered = named.concat(plain);
            for (var j = 0; j <= ordered.length; j++) {
                var item = ordered[j];
                var appId = item ? item.appId : "com.webos.app.home";
                var state = I18n.t("panel", "detail.home_screen");
                if (item && item.label.indexOf("HDMI") === 0) {
                    state = item.hdmiPlugIn ? I18n.t("panel", "detail.connected") :
                                              I18n.t("panel", "detail.nothing_connected");
                } else if (item) {
                    state = "HDMI " + item.port;
                }
                // Inputs open their own page, so the running one says so in words.
                if (item && appId === activeApp) state = I18n.t("panel", "detail.with_running", { detail: state });
                result.push({
                    key: "device", appId: appId, h: 72, y: 132 + result.length * 76,
                    deviceId: item ? item.id : undefined,
                    title: item ? SourceList.deviceName(item) : "Home",
                    sublabel: state,
                    active: appId === activeApp,
                    png: item ? SourceList.deviceIcon(item) : "source-home"
                });
            }
            return result;
        }

        // ---- Device detail page ---------------------------------------------
        function deviceById(devices, id) {
            for (var i = 0; i < devices.length; i++) {
                if (devices[i].id === id) return devices[i];
            }
            return null;
        }

        function buildSourceDetailRows(device) {
            if (!device) return [];
            return [{ key: "deviceSwitch", title: I18n.t("panel", "row.switch_to_device"), y: 320, h: 68,
                      plain: true },
                    { key: "deviceName", title: I18n.t("panel", "row.device_name"), y: 452, h: 68 },
                    { key: "deviceIcon", title: I18n.t("panel", "row.device_type"), y: 524, h: 68,
                      opens: true }];
        }

        function deviceStatus(device) {
            if (!device.hdmiPlugIn) return I18n.t("panel", "detail.nothing_connected");
            return I18n.t("panel", SourceList.deviceIsOff(device) ? "value.device_off" : "detail.connected");
        }

        function buildSourceInfo(device) {
            if (!device) return [];
            var info = [{ label: I18n.t("panel", "label.port"), value: "HDMI " + device.port, y: 656 },
                        { label: I18n.t("panel", "label.status"), value: deviceStatus(device), y: 716 }];
            var cec = SourceList.cecName(device);
            if (cec !== "") info.push({ label: I18n.t("panel", "label.cec_name"), value: cec, y: 776 });
            return info;
        }

        // Port and state under the name in the head of the page.
        function deviceHeadline(device) {
            if (!device) return "";
            var port = "HDMI " + device.port;
            return device.appId === foregroundApp ? I18n.t("panel", "detail.with_running", { detail: port }) : port;
        }

        function openSourceDetail(id) {
            detailDeviceId = id;
            changePage("sourceDetail", 0);
        }

        function typeName(choice) {
            return I18n.t("source", "type." + choice.key);
        }

        // As LG's input editor: label and icon in one call, marked as the user's choice.
        // The name shown stays the name stored, even when only the type changes,
        // because a stored choice makes eim show the label instead of the CEC name.
        function writeDeviceInfo(label, icon, saved) {
            pendingToast = saved;
            backdropService.call("luna://com.webos.service.eim", "/setDeviceInfo",
                                 JSON.stringify({ id: detailDevice.id, label: label, icon: icon,
                                                  customized: true }));
        }

        function saveDeviceName(name) {
            if (!detailDevice || name === "" || name === SourceList.deviceName(detailDevice)) return;
            writeDeviceInfo(name, detailDevice.icon, I18n.t("panel", "toast.device_name_saved"));
        }

        function saveDeviceIcon(icon) {
            if (!detailDevice || icon === detailDevice.icon) return;
            writeDeviceInfo(SourceList.deviceName(detailDevice), icon, I18n.t("panel", "toast.device_type_saved"));
        }

        function deviceInfoSaved(ok) {
            if (ok) showToast(pendingToast);
            pendingToast = "";
            backdropService.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
        }

        function showToast(text) {
            toastText = text;
            toastShown = true;
            toastTimer.restart();
        }

        // Both pages stay loaded and cross-fade, while the focus surface glides
        // to its new place. Building rows during the animation made it stutter.
        function changePage(name, focus) {
            page = name;
            focusIndex = focus;
        }

        // Confirmations, name entry and Wi-Fi are built when first asked for, in the
        // background. Built with every opening of the panel they cost each opening CPU time
        // and frames, built in one piece they stopped the picture for 180 ms
        // (docs/performance-plan.md). work(flow) runs once the flow stands; while a flow the
        // user asked for (shows) is still being built, keys wait.
        function withFlow(work, shows) {
            if (modalLoader.status === Loader.Ready) {
                work(modalLoader.item);
                return;
            }
            PerfProbe.mark("flow.request");
            var works = pendingFlow.slice();
            works.push(work);
            pendingFlow = works;
            if (shows !== false) flowWaiting = true;
            if (!modalNeeded) {
                modalNeeded = true;
                // By URL, so that Qt compiles the flow only now, in its loader thread.
                modalLoader.setSource(Qt.resolvedUrl("module/PanelFlow.qml"), { host: panel, glass: liveGlass });
            }
        }

        function flowNetworkChanged() {
            readNetworkState();
            networkRefresh.restart();
        }

        function flowBuilt() {
            var works = pendingFlow;
            pendingFlow = [];
            flowWaiting = false;
            if (closing) return;
            for (var i = 0; i < works.length; i++) works[i](modalLoader.item);
        }

        // The flow, if it has been built; for closing or updating what it shows.
        function flow() {
            return modalLoader.item;
        }

        function openPage(name) {
            if (name === "accessibility") name = "access";
            PerfProbe.mark("page.open", name);
            var started = PerfProbe.now();
            subpagesLoader.asynchronous = false;
            wantPage(name);
            overviewFocus = focusIndex;
            var pageRows = rowsOfPage(name);
            var focus = 0;
            for (var i = pageRows.length - 1; i >= 0; i--) {
                if (pageRows[i].active) focus = i;
            }
            changePage(name, focus);
            PerfProbe.cost("page.open", started, name);
            if (name === "network") withFlow(function (flow) { flow.prepareList(); }, false);
        }

        function wantPage(name) {
            if (pagesWanted.indexOf(name) >= 0) return;
            pagesNeeded = true;
            pagesWanted = pagesWanted.concat([name]);
        }

        // The subpage the focused row leads to, "" for none.
        function pageBehind(row) {
            if (!row) return "";
            if (page === "overview" && opensPage(row)) return row.key === "accessibility" ? "access" : row.key;
            if (row.key === "language") return "languages";
            if (row.key === "device" && row.deviceId) return "sourceDetail";
            if (page === "apps") return "appDetail";
            return "";
        }

        // Once the focus rests on a row with a page behind it, that page is built in the
        // background, so that opening it usually finds it standing.
        Timer {
            id: pageWarm
            interval: panel.focusDuration + panel.popoverDuration
            onTriggered: {
                if (!panel.panelShown || panel.closing) return;
                var name = panel.pageBehind(panel.focusedRow);
                if (name !== "") panel.wantPage(name);
            }
        }

        function opensPage(row) {
            return row.key === "sources" || row.key === "picture" || row.key === "sound" ||
                   row.key === "network" || row.key === "apps" || row.key === "energy" || row.key === "system" ||
                   row.key === "accessibility" || row.key === "debug" || row.key === "profiles";
        }

        function sourceRowOf(id) {
            for (var i = 0; i < sourceRows.length; i++) {
                if (sourceRows[i].deviceId === id) return i;
            }
            return 0;
        }

        function backOrClose() {
            if (page === "overview" && fromGame) panelToGame();
            else if (page === "overview") close();
            else if (page === "appDetail") changePage("apps", 0);
            else if (page === "sourceDetail") changePage("sources", sourceRowOf(detailDeviceId));
            else if (page === "languages") changePage("system", 1);
            else changePage("overview", overviewFocus);
        }

        // Rows without an own page lead into LG's interface.
        readonly property var linkTargets: ({})

        function openLink(link) {
            backdropService.call("luna://com.webos.applicationManager", "/launch", JSON.stringify(link));
            close();
        }

        // The hub lives in the launcher's window; over the launcher it opens on top of it.
        function openSmartHome() {
            backdropService.call("luna://com.webos.service.systemUIManager", "/launch",
                                 JSON.stringify({ appId: "com.webos.app.store-streamer", params: { page: "hub" } }));
            close();
        }

        function switchTo(row) {
            if (row.appId !== foregroundApp) {
                backdropService.call("luna://com.webos.applicationManager", "/launch",
                                     NovosSettings.launchRequest(row.appId));
            }
            close();
        }

        // Through the shared store, so that a picture value marks its mode as changed
        // (pictureSettingModified) exactly as LG's app and the settings modal do.
        function writePicture(values) {
            for (var key in values) settingsStore.set("picture." + key, values[key]);
        }

        function adjustBacklight(step) {
            if (backlightLocked || backlight < 0) return;
            backlight = Math.max(0, Math.min(100, backlight + step));
            settingsStore.set("picture.backlight", backlight);
        }

        function toggleEyeComfort() {
            if (eyeComfort === "") return;
            eyeComfort = eyeComfort === "on" ? "off" : "on";
            writePicture({ eyeComfortMode: eyeComfort });
        }

        function activateFocusedRow() {
            if (focusedRow.key === "allSettings") openSettings(settingsAreaOf(page), "");
            else if (focusedRow.icon) openPopover(focusedRow.key);
            else if (focusedRow.key === "profiles" && profileStore.known && !profileStore.active) openSettings("profile", "signIn");
            else if (opensPage(focusedRow)) openPage(focusedRow.key);
            else if (focusedRow.key === "device" && focusedRow.deviceId) openSourceDetail(focusedRow.deviceId);
            else if (focusedRow.key === "device") switchTo(focusedRow);
            else if (focusedRow.key === "deviceSwitch") switchTo({ appId: detailDevice.appId });
            else if (focusedRow.key === "deviceName") withFlow(function (flow) { flow.openDeviceName(SourceList.deviceName(detailDevice)); });
            else if (focusedRow.key === "mode") selectPictureMode(focusedRow.value);
            else if (focusedRow.key === "profileSwitch") switchProfile(focusedRow.userNo);
            else if (focusedRow.key === "profileAdd") openSettings("profile", "signIn");
            else if (focusedRow.key === "profileEdit") openSettings("profile", "edit");
            else if (focusedRow.key === "profileAll") openSettings("profile", "");
            else if (linkTargets[focusedRow.key]) openLink(linkTargets[focusedRow.key]);
            else if (focusedRow.key === "soundOutput") selectSound("soundOutput", focusedRow.value);
            else if (focusedRow.key === "soundMode") selectSound("soundMode", focusedRow.value);
            else if (focusedRow.key === "wifiChange") withFlow(function (flow) { flow.openList(); });
            else if (focusedRow.key === "app") openApp();
            else if (focusedRow.key === "smartHome") openSmartHome();
            else if (focusedRow.key === "tvName") withFlow(function (flow) { flow.openTvName(tvName); });
            else if (focusedRow.key === "audioGuidance") toggleOption("audioGuidance", "audioGuidance");
            else if (focusedRow.key === "highContrast") toggleOption("highContrast", "highContrast");
            else if (focusedRow.key === "screenZoom") toggleOption("screenZoom", "screenMagnification");
            else if (focusedRow.key === "remotePointer") toggleRemotePointer();
            else if (focusedRow.key === "audioDescription") toggleAudioDescription();
            else if (focusedRow.key === "language") openLanguages();
            else if (focusedRow.key === "languageChoice") selectLanguage();
            else if (focusedRow.key === "reboot") askReboot();
            else if (focusedRow.opens === true) openChoice(focusedRow);
            else if (focusedRow.key === "screenOff") askScreenOff();
            else if (focusedRow.key === "quickStart") toggleQuickStart();
            else if (focusedRow.key === "powerSound") togglePowerSound();
            else if (focusedRow.key === "hideInputBanner") NovosSettings.hideInputBanner = !NovosSettings.hideInputBanner;
            else if (focusedRow.key === "demoDevices") NovosSettings.demoDevices = !NovosSettings.demoDevices;
            else if (focusedRow.key === "demoProfiles") NovosSettings.demoProfiles = !NovosSettings.demoProfiles;
            else if (focusedRow.key === "appStart") switchTo({ appId: selectedApp.id });
            else if (focusedRow.key === "appRemove") askRemoveApp();
            else if (focusedRow.key === "wifiForget") withFlow(function (flow) { flow.openForget(wifiProfile, networkName); });
        }

        function readTvState() {
            // Every settings value comes from the shared store, subscribed once.
            settingsStore.request();
            applyStore();
            // localeInfo has no category at LG, so it stays outside the store's subscriptions.
            backdropService.call("luna://com.webos.settingsservice", "/getSystemSettings",
                                 JSON.stringify({ keys: ["localeInfo"] }));
            readSleepTimer();
            backdropService.call("luna://com.webos.service.eim", "/getAllInputStatus", "{}");
            backdropService.call("luna://com.webos.service.tv.systemproperty", "/getSystemInfo",
                                 JSON.stringify({ keys: ["modelName", "firmwareVersion", "sdkVersion"] }));
            backdropService.call("luna://com.palm.systemservice/time", "/getSystemTime", "{}");
            readNetworkState();
        }

        function readNetworkState() {
            backdropService.call("luna://com.palm.connectionmanager", "/getStatus", "{}");
            backdropService.call("luna://com.webos.service.wifi", "/getstatus", "{}");
        }

        function applyNetworkStatus(response) {
            var wired = response.wired && response.wired.state === "connected";
            var wifi = response.wifi && response.wifi.state === "connected";
            var active = wired ? response.wired : (wifi ? response.wifi : {});
            networkState = wired ? "wired" : (wifi ? "wifi" : "none");
            hasInternet = active.onInternet === "yes";
            networkAddress = active.ipAddress || "";
            networkGateway = active.gateway || "";
            networkName = wifi ? (response.wifi.displayName || response.wifi.ssid || "") : "";
            networkFrequency = wifi ? Number(response.wifi.connectedFrequency || 0) : 0;
        }

        function applyWifiStatus(response) {
            var info = response.networkInfo;
            wifiBars = info ? (info.signalBars || 0) : 0;
            wifiProfile = info ? (info.profileId || 0) : 0;
        }

        // The panel steps aside first, so that it never shows the moved crop.
        // Panel, settings modal and the flows of WifiSetup never show glass over glass:
        // whatever stands fades out first, then the backdrop moves, then the next shows.
        function modalChanged() {
            var flow = modalLoader.item;
            var sheet = settingsLoader.item;
            var flowActive = flow !== null && flow.active;
            var sheetActive = sheet !== null && sheet.active;
            if (flowActive || sheetActive) panelHidden = true;
            if (flow !== null && flow.shown && !flowActive) flow.shown = false;
            if (sheet !== null && sheet.shown && (!sheetActive || flowActive)) sheet.shown = false;
            modalStep.restart();
        }

        function modalStepDone() {
            var flow = modalLoader.item;
            var sheet = settingsLoader.item;
            var flowActive = flow !== null && flow.active;
            var sheetActive = sheet !== null && sheet.active;
            modalBackdrop = flowActive || sheetActive;
            settingsBackdrop = !flowActive && sheetActive;
            liveGlass.snap();
            if (flowActive) flow.shown = true;
            else if (flow !== null) flow.reset();
            if (sheetActive && !flowActive) {
                sheet.shown = true;
            } else if (!sheetActive && sheet !== null) {
                sheet.reset();
            }
            if (!flowActive && !sheetActive) {
                if (settingsLaunch) close();
                else panelHidden = false;
            }
        }

        // What the settings modal shows about this TV without asking again.
        readonly property var settingsHostState: ({
            source: currentSourceName(), foreground: foregroundApp, network: networkState,
            online: hasInternet, ipAddress: networkAddress, wifiName: networkName, modelName: modelName,
            firmware: softwareVersion, country: countryCode, tvName: tvName,
            timezone: timezone, panelVersion: previewVersion
        })

        // "HDMI 1 · PlayStation 5" for an input. Every app shares one set of picture and sound
        // values at LG (input "ip"), so for an app it reads "Apps".
        function currentSourceName() {
            for (var i = 0; i < sourceDevices.length; i++) {
                var device = sourceDevices[i];
                if (device.appId === foregroundApp) {
                    var name = SourceList.deviceName(device);
                    return device.label && name && name !== device.label ? device.label + " · " + name : (name || device.label);
                }
            }
            if (foregroundApp === "com.webos.app.livetv") return I18n.t("settings", "detail.source_live_tv");
            if (foregroundApp !== "") return I18n.t("settings", "detail.source_apps");
            return "";
        }

        // The page of the panel decides where the modal opens.
        function settingsAreaOf(name) {
            var areas = { picture: "picture", sound: "sound", sources: "sources", sourceDetail: "sources",
                          network: "network", energy: "energy", access: "accessibility", system: "system",
                          languages: "system", profiles: "profile" };
            return areas[name] || "picture";
        }

        // The settings modal, opened on one of its areas.
        // The modal is built in the background (about 120 ms of work, which in one piece
        // stopped the picture) and opens once it stands. Keys wait for it meanwhile.
        function openSettings(areaId, pageId) {
            var wanted = { area: areaId || "picture", page: pageId || "" };
            if (settingsLoader.status !== Loader.Ready) {
                PerfProbe.mark("settings.request");
                pendingSettings = wanted;
                if (!settingsNeeded) {
                    settingsNeeded = true;
                    // By URL, so that Qt compiles the modal only now, in its loader thread.
                    settingsLoader.setSource(Qt.resolvedUrl("module/PanelSettings.qml"),
                                             { host: panel, glass: liveGlass });
                }
                return;
            }
            var started = PerfProbe.now();
            settingsLoader.item.open(wanted.area, wanted.page);
            PerfProbe.cost("settings.open", started);
        }

        function settingsBuilt() {
            var wanted = pendingSettings;
            pendingSettings = null;
            if (wanted !== null && !closing) openSettings(wanted.area, wanted.page);
        }

        function settingsHostAction(name, params) {
            if (name === "confirm") {
                settingsConfirm = params.action;
                settingsConfirmParams = params.params || {};
                withFlow(function (flow) {
                    // Without an icon of its own a confirmation warns: "" left an empty circle.
                    flow.openDialog({ action: "settings", icon: params.icon || "alert-44",
                                      title: params.title, text: params.text, confirm: params.confirm,
                                      safe: params.safe === true, danger: params.danger });
                });
            } else if (name === "wifiSetup") {
                withFlow(function (flow) { flow.openList(); });
            } else if (name === "tvName") {
                withFlow(function (flow) { flow.openTvName(tvName); });
            } else if (name === "wifiForget") {
                withFlow(function (flow) { flow.openForget(wifiProfile, networkName); });
            } else if (name === "closePanel") {
                close();
            } else if (name === "profileSwitching") {
                modalSwitching = params.profile || null;
                modalSwitchStarted = params.started || 0;
            } else if (name === "profileSwitched") {
                close();
            } else if (name === "profileName") {
                profileNameFor = params.userNo || "";
                withFlow(function (flow) { flow.openProfileName(params.current || ""); });
            } else if (name === "toast") {
                showToast(params.text || "");
            } else if (name === "switchInput" && params.input) {
                switchTo({ appId: params.input.appId });
            } else if (name === "deviceDetails" && params.input) {
                // The panel's name entry for an input, saved through eim/setDeviceInfo.
                detailDeviceId = params.input.id;
                withFlow(function (flow) { flow.openDeviceName(SourceList.deviceName(params.input.device)); });
            } else if (name === "language") {
                // The language list lives in the panel; the modal steps back to it.
                settingsLoader.item.close();
                // Opened for the modal alone, the panel comes in now.
                if (settingsLaunch) {
                    settingsLaunch = false;
                    startOpenAnimation();
                }
                openPage("system");
                openLanguages();
            }
        }

        // The panel's copies of the values it shows, refreshed from the shared store.
        function applyStore() {
            var store = settingsStore;
            var value;
            function text(key) {
                var raw = store.val(key);
                return raw === undefined || raw === null ? undefined : String(raw);
            }
            var dimension = store.dimension("picture");
            if (dimension.dynamicRange) dynamicRange = dimension.dynamicRange;
            if ((value = text("picture.pictureMode")) !== undefined) pictureMode = value;
            if ((value = store.val("picture.backlight")) !== undefined) backlight = Number(value);
            if ((value = text("picture.energySaving")) !== undefined) {
                energySaving = value;
                backlightLocked = value === "auto" || value === "max";
            }
            if ((value = text("picture.eyeComfortMode")) !== undefined) eyeComfort = value;
            if ((value = text("sound.soundOutput")) !== undefined) soundOutput = value;
            if ((value = text("sound.soundMode")) !== undefined) soundMode = value;
            if ((value = text("sound.audioDescription")) !== undefined) audioDescription = value;
            if ((value = text("option.quickStartMode")) !== undefined) quickStart = value;
            if ((value = text("option.country")) !== undefined) countryCode = value;
            if ((value = text("option.audioGuidance")) !== undefined) audioGuidance = value;
            if ((value = text("option.audioGuidanceSpeed")) !== undefined) guidanceSpeed = value;
            if ((value = text("option.highContrast")) !== undefined) highContrast = value;
            if ((value = text("option.screenMagnification")) !== undefined) screenZoom = value;
            if ((value = text("general.remotePointer")) !== undefined) remotePointer = value;
            if ((value = text("general.tvOnSound")) !== undefined) powerSound = value;
            if (store.val("time.onTimerEnable") !== undefined) {
                onTimerEnabled = store.val("time.onTimerEnable") === "on";
                onTimerHour = Number(store.val("time.onTimerHour") || 0);
                onTimerMinute = Number(store.val("time.onTimerMinute") || 0);
                onTimerApp = text("time.onTimerAppId") || "";
            }
            if (store.val("time.offTimerEnable") !== undefined) {
                offTimerEnabled = store.val("time.offTimerEnable") === "on";
                offTimerHour = Number(store.val("time.offTimerHour") || 0);
                offTimerMinute = Number(store.val("time.offTimerMinute") || 0);
            }
            if ((value = text("network.deviceName"))) tvName = value.replace("[LG] ", "");
            var modes = store.options("picture.pictureMode");
            if (JSON.stringify(modes) !== JSON.stringify(pictureModes)) pictureModes = modes;
            var sounds = store.options("sound.soundMode");
            if (JSON.stringify(sounds) !== JSON.stringify(soundModes)) soundModes = sounds;
        }

        // A press of the gear key: the game bar while a game runs, otherwise the panel. A launch
        // with a page opens it straight away; page "game" shows the bar with stand-in values.
        function launch() {
            mode = "panel";
            fromGame = false;
            if (launchPage === "game") {
                openGame("");
            } else if (launchPage === "") {
                PerfProbe.mark("game.check");
                gameStatus.check();
            } else {
                open();
            }
        }

        function gameDecided(game) {
            PerfProbe.mark("game.decided", game ? "game" : "panel");
            if (!rootWindow.opened || closing) return;
            if (game) openGame("");
            else open();
        }

        function openGame(focusKey) {
            mode = "game";
            page = "overview";
            popover = "";
            modalStep.stop();
            choicePopover.shown = false;
            settingsLaunch = false;
            panelHidden = false;
            modalBackdrop = false;
            settingsBackdrop = false;
            gameFocus = focusKey;
            gameBar.demo = launchPage === "game";
            guide.reset();
            closing = false;
            panelShown = false;
            forceActiveFocus();
            openTimer.restart();
            backdropService.call("luna://com.webos.applicationManager",
                                 "/getForegroundAppInfo", "{}");
            PerfProbe.beginPhase("open");
            settingsStore.request();
            gameStatus.live = true;
            if (liveGlass.pictureReady) startOpenAnimation();
        }

        // "Schnellmenü" on the bar: the panel comes in, and Back on its overview returns to
        // the bar on "Schnellmenü". Glass never stands over glass: what stands fades out
        // first, then the backdrop moves to the other area (modeSwitch).
        function gameToPanel() {
            gameBar.hide();
            fromGame = true;
            modeSwitch.target = "panel";
            modeSwitch.restart();
        }

        function panelToGame() {
            fromGame = false;
            openAnimation.stop();
            panelOut.restart();
            modeSwitch.target = "game";
            modeSwitch.restart();
        }

        function modeSwitched(target) {
            if (closing) return;
            mode = target;
            liveGlass.snap();
            if (target === "game") {
                gameBar.open("quick");
            } else {
                launchPage = "";
                open();
            }
        }

        function open() {
            page = "overview";
            popover = "";
            modalStep.stop();
            choicePopover.shown = false;
            settingsLaunch = launchPage.indexOf("settings") === 0;
            panelHidden = false;
            modalBackdrop = false;
            settingsBackdrop = false;
            focusIndex = initialFocus;
            guide.reset();
            closing = false;
            panelShown = false;
            forceActiveFocus();
            openTimer.restart();
            backdropService.call("luna://com.webos.applicationManager",
                                 "/getForegroundAppInfo", "{}");
            PerfProbe.beginPhase("open");
            var started = PerfProbe.now();
            readTvState();
            // Opened for the settings modal alone: its descriptors are needed at once.
            if (settingsLaunch) settingsStore.describeAll();
            PerfProbe.cost("panel.readTvState", started);
            if (liveGlass.pictureReady) startOpenAnimation();
        }

        function close() {
            if (closing) return;
            PerfProbe.mark("close");
            PerfProbe.finish("close");
            closing = true;
            guide.stop();
            pendingSettings = null;
            pendingFlow = [];
            flowWaiting = false;
            if (modalLoader.item) modalLoader.item.closeFlow();
            if (settingsLoader.item) settingsLoader.item.close();
            openTimer.stop();
            gameBar.hide();
            gameStatus.live = false;
            liveGlass.stop();
            openAnimation.stop();
            closeAnimation.restart();
        }

        function startOpenAnimation() {
            if (mode === "game") {
                if (closing || gameBar.shown || gameStatus.checking) return;
                PerfProbe.mark("open.animation", "game");
                openTimer.stop();
                panelShown = true;
                gameBar.open(gameFocus);
                return;
            }
            if (closing || openAnimation.running || glass.opacity > 0) return;
            PerfProbe.mark("open.animation");
            openTimer.stop();
            openAnimation.restart();
        }

        function moveFocus(step) {
            if (page === "apps") {
                moveApp(step);
            } else if (page === "languages") {
                moveLanguage(step);
            } else if (page === "overview" && focusIndex < firstCategory) {
                if (step > 0) {
                    lastShortcut = focusIndex;
                    focusIndex = firstCategory;
                }
            } else if (page === "overview" && focusIndex === firstCategory && step < 0) {
                focusIndex = lastShortcut;
            } else {
                focusIndex = Math.max(0, Math.min(currentRows.length - 1, focusIndex + step));
            }
        }

        AudioGuide {
            id: guide
            quiet: panel.closing
        }

        readonly property var sharedSettings: settingsStore

        // LG's settings for the panel and the settings modal: one subscription, one way
        // of writing, the catalog names (module/SettingsStore.qml).
        SettingsStore {
            id: settingsStore
            extraKeys: ({ network: ["deviceName"], option: ["country"],
                          // The game bar: latency and LG's list of its values.
                          picture: ["memcDelayLevel"], other: ["gameDashboardStatusList"],
                          general: ["remotePointer", "tvOnSound"],
                          time: ["onTimerHour", "onTimerMinute", "onTimerAppId", "offTimerHour", "offTimerMinute"] })
            // The descriptors the panel itself reads (value lists, picture dimensions); the
            // settings modal asks for the rest when it opens.
            descKeys: ["picture.pictureMode", "picture.backlight", "picture.energySaving",
                       "picture.eyeComfortMode", "sound.soundMode", "sound.soundOutput",
                       "sound.audioDescription", "option.audioGuidanceSpeed",
                       // The game bar shows VRR only where the TV has it.
                       "other.gameOptimization", "other.freesync"]
            onRevisionChanged: panel.applyStore()
        }

        // The TV's profiles (module/ProfileStore.qml); the row, the page and the switch screen.
        ProfileStore {
            id: profileStore
            onNotice: {
                if (kind === "switched") panel.close();
                else if (kind === "failed") panel.showToast(I18n.t("profile", "notice.failed"));
                else if (kind === "signedIn") panel.showToast(I18n.t("profile", "notice.signed_in", { name: profile.nick }));
                else if (kind === "signedOut") panel.showToast(I18n.t("profile", "notice.signed_out", { name: profile.nick }));
                else if (kind === "removed") panel.showToast(I18n.t("profile", "notice.removed", { name: profile.nick }));
            }
        }

        Service {
            id: backdropService
            appId: "com.webos.app.quicksettings"
            onResponse: {
                var response = JSON.parse(payload);
                if (method === "/setSystemSettings") {
                    if (!response.returnValue) panel.readTvState();
                } else if (method === "/getSystemSettings") {
                    if (response.settings && response.settings.localeInfo) panel.localeInfo = response.settings.localeInfo;
                } else if (method === "/getAllInputStatus") {
                    var devices = response.devices || [];
                    // "connected" only says that the port exists.
                    var connected = 0;
                    for (var i = 0; i < devices.length; i++) {
                        if (devices[i].hdmiPlugIn) connected++;
                    }
                    panel.connectedInputs = connected;
                    panel.sourceDevices = devices;
                    panel.hasArcDevice = response.arcDevice === true;
                } else if (method === "/setDeviceInfo") {
                    panel.deviceInfoSaved(response.returnValue === true);
                } else if (method === "/getStatus") {
                    panel.applyNetworkStatus(response);
                } else if (method === "/getstatus") {
                    panel.applyWifiStatus(response);
                } else if (method === "/getSystemInfo") {
                    panel.modelName = response.modelName || "";
                    panel.softwareVersion = response.firmwareVersion || "";
                    panel.sdkVersion = panel.webOSLabel(response.sdkVersion || "");
                } else if (method === "/getSystemTime") {
                    panel.timezone = response.timezone || "";
                } else if (method === "/getRemainTime") {
                    panel.sleepSeconds = response.sleepTimeSecond || 0;
                } else if (method === "/add") {
                    panel.readSleepTimer();
                } else if (method === "/listApps") {
                    panel.applyApps(response.apps || []);
                } else if (method === "/remove") {
                    if (response.returnValue === false) panel.removeFailed();
                } else if (method === "/getForegroundAppInfo") {
                    panel.foregroundApp = response.appId || "";
                    liveGlass.setForeground(panel.foregroundApp);
                }
            }
            onError: {
                if (method === "/setSystemSettings") {
                    panel.readTvState();
                } else if (method === "/remove") {
                    panel.removeFailed();
                } else if (method === "/setDeviceInfo") {
                    panel.deviceInfoSaved(false);
                }
            }
        }

        // The panel never waits long for a picture. It opens with the fallback
        // material and the glass arrives with the first frame.
        Timer {
            id: openTimer
            interval: panel.openTimeout
            repeat: false
            onTriggered: panel.startOpenAnimation()
        }

        // The service reports removing in stages. The list shows when it is done.
        Timer {
            id: removeCheck
            interval: 1500
            repeat: true
            onTriggered: {
                panel.removeChecks++;
                if (panel.removeChecks > 20) panel.removeFailed();
                else panel.readApps();
            }
        }

        Timer {
            id: toastTimer
            interval: 2500
            onTriggered: panel.toastShown = false
        }

        // Keeps the remaining sleep time current while the energy page is open.
        Timer {
            interval: 20000
            repeat: true
            running: panel.page === "energy" && panel.sleepSeconds > 0
            onTriggered: {
                panel.readSleepTimer();
                panel.clockTick++;
            }
        }

        Timer {
            id: modalStep
            interval: panel.modalFadeDuration + 20
            repeat: false
            onTriggered: panel.modalStepDone()
        }

        // The network needs a moment before it reports its new state.
        Timer {
            id: networkRefresh
            interval: 1500
            repeat: false
            onTriggered: panel.readNetworkState()
        }

        function handlePopoverKey(key, autoRepeat) {
            if (key === Qt.Key_Left || key === Qt.Key_Right) {
                if (popover === "backlight") {
                    adjustBacklight(key === Qt.Key_Right ? backlightStep : -backlightStep);
                }
            } else if (key === Qt.Key_Up || key === Qt.Key_Down) {
                popover = "";
            } else if (Remote.isOk(key)) {
                if (autoRepeat) return;
                if (popover === "eyeComfort") toggleEyeComfort();
                else popover = "";
            }
        }

        function isBackKey(key) {
            return Remote.isBack(key);
        }

        // Keys of the remote, and the steps of the performance probe (PerfMeter).
        function pressKey(key, autoRepeat) {
            if (profileStore.switching || modalSwitching) return true;     // the switch screen takes no keys
            var started = PerfProbe.now();
            var handled = handlePress(key, autoRepeat);
            PerfProbe.cost("key.press", started, modalActive ? "flow" : (settingsActive ? "settings" : page));
            return handled;
        }

        function releaseKey(key) {
            if (profileStore.switching || modalSwitching) return true;
            var started = PerfProbe.now();
            var handled = handleRelease(key);
            PerfProbe.cost("key.release", started, modalActive ? "flow" : (settingsActive ? "settings" : page));
            return handled;
        }

        Keys.onPressed: {
            if (pressKey(event.key, event.isAutoRepeat)) event.accepted = true;
        }

        Keys.onReleased: {
            if (releaseKey(event.key)) event.accepted = true;
        }

        // Probe only: everything that follows the settings rebuilds, nothing is written.
        function bump() {
            settingsStore.changed();
        }

        function handlePress(key, autoRepeat) {
            if (pendingSettings !== null || flowWaiting || modeSwitch.running) {
                return true;
            } else if (modalActive) {
                modalLoader.item.handleKey(key, autoRepeat);
            } else if (settingsActive) {
                settingsLoader.item.handleKey(key, autoRepeat);
            } else if (mode === "game") {
                return gameBar.handlePress(key, autoRepeat);
            } else if (choicePopover.shown) {
                choicePopover.handleKey(key, autoRepeat);
            } else if (popover !== "") {
                handlePopoverKey(key, autoRepeat);
            } else if (key === Qt.Key_Up) {
                moveFocus(-1);
            } else if (key === Qt.Key_Down) {
                moveFocus(1);
            } else if (key === Qt.Key_Right && focusedRow.icon && focusIndex === 0) {
                focusIndex = 1;
            } else if (key === Qt.Key_Right && focusedRow.icon && focusIndex === 2) {
                focusIndex = 0;
            } else if (key === Qt.Key_Left && focusedRow.icon && focusIndex === 1) {
                focusIndex = 0;
                leftConsumed = true;
            } else if (key === Qt.Key_Left && focusedRow.icon && focusIndex === 0) {
                focusIndex = 2;
                leftConsumed = true;
            } else if ((key === Qt.Key_Left || key === Qt.Key_Right) && focusedRow.step !== undefined) {
                adjustSlider(focusedRow, key === Qt.Key_Right ? 1 : -1);
                if (key === Qt.Key_Left) leftConsumed = true;
            } else if (key === Qt.Key_Right && focusedRow.opens === true) {
                if (!autoRepeat) openChoice(focusedRow);
            } else if (key === Qt.Key_Right && (focusedRow.key === "app" || focusedRow.key === "tvName" ||
                                                focusedRow.key === "language" || focusedRow.key === "deviceName" ||
                                                (focusedRow.key === "device" && focusedRow.deviceId))) {
                if (!autoRepeat) activateFocusedRow();
            } else if (key === Qt.Key_Right && opensPage(focusedRow)) {
                if (!autoRepeat) openPage(focusedRow.key);
            } else if (key === Qt.Key_Right && linkTargets[focusedRow.key]) {
                if (!autoRepeat) openLink(linkTargets[focusedRow.key]);
            } else if (Remote.isOk(key)) {
                if (!autoRepeat) activateFocusedRow();
            } else if (key !== Qt.Key_Left && key !== Qt.Key_Right && !isBackKey(key)) {
                return false;
            }
            return true;
        }

        function handleRelease(key) {
            if (modeSwitch.running) {
                return true;
            } else if (flowWaiting) {
                // Back while a dialog is still being built: it does not open after all.
                if (isBackKey(key)) {
                    pendingFlow = [];
                    flowWaiting = false;
                }
            } else if (pendingSettings !== null) {
                // Back while the modal is still being built: it does not open after all.
                if (isBackKey(key)) pendingSettings = null;
                if (isBackKey(key) && settingsLaunch) close();
            } else if (modalActive) {
                if (isBackKey(key)) modalLoader.item.back();
            } else if (settingsActive) {
                if (isBackKey(key)) settingsLoader.item.back();
                else return false;
            } else if (mode === "game") {
                return gameBar.handleRelease(key);
            } else if (choicePopover.shown) {
                if (isBackKey(key)) choicePopover.close();
                else return false;
            } else if (key === Qt.Key_Left && leftConsumed) {
                leftConsumed = false;
            } else if (popover !== "") {
                if (isBackKey(key) || (key === Qt.Key_Left && popover === "eyeComfort")) {
                    popover = "";
                } else {
                    return false;
                }
            } else if (key === Qt.Key_Left || isBackKey(key)) {
                backOrClose();
            } else {
                return false;
            }
            return true;
        }

        readonly property string titleFamily: GlassStyle.titleFont
        readonly property string rowFamily: GlassStyle.rowFont
        readonly property string valueFamily: GlassStyle.valueFont

        MouseArea {
            anchors.fill: parent
            onClicked: panel.close()
        }

        LiveBackdrop {
            id: liveGlass
            anchors.fill: parent
            unit: panel.unit
            area: panel.backdropArea
            margin: panel.backdropMargin
            opened: rootWindow.opened
            shown: panel.panelShown
            closing: panel.closing
            veil: panel.modalVeil
            onReady: if (rootWindow.opened) panel.startOpenAnimation()
            onPictureReadyChanged: if (pictureReady) PerfProbe.mark("glass.picture")
        }

        PerfMeter {
            target: panel
            start: panel.panelShown
        }

        // Content scrim: rgba(4, 6, 8, .18), rising to .55 behind a modal.
        Rectangle {
            anchors.fill: parent
            color: GlassStyle.scrimColor
            opacity: (GlassStyle.contentScrim + (GlassStyle.modalScrim - GlassStyle.contentScrim) * modalDim *
                      (1 - panel.settingsPicture)) * glass.opacity
            property real modalDim: panel.panelHidden ? 1 : 0
            Behavior on modalDim { NumberAnimation { duration: panel.modalFadeDuration } }
        }

        // Panel shadow: 0 30px 80px rgba(0, 0, 0, .35), as a nine-patch for the GPU's sake.
        BorderImage {
            id: panelShadow
            x: glass.x - 180 * panel.unit + glassOffset.x
            y: glass.y - 180 * panel.unit
            width: glass.width + 360 * panel.unit
            height: glass.height + 360 * panel.unit
            opacity: glass.opacity * panel.panelFade
            visible: opacity > 0
            source: Qt.resolvedUrl("module/icons/shadow-panel.png")
            border.left: 240
            border.right: 240
            border.top: 240
            border.bottom: 240
        }



        // Glass material. All layers sit in one pass so the edge lights follow
        // the same rounded shape as the panel, as CSS inset shadows do.
        Rectangle {
            id: glass
            x: panel.panelX
            y: panel.panelInset
            width: panel.panelWidth
            height: panel.panelHeight
            radius: panel.panelRadius
            color: "transparent"
            opacity: 0
            transform: Translate { id: glassOffset; x: 48 * panel.unit }

            ShaderEffect {
                id: material
                anchors.fill: parent
                opacity: panel.panelFade
                visible: opacity > 0
                blending: true
                property variant backdrop: liveGlass.texture
                property size panelSize: Qt.size(width, height)
                property real cornerRadius: glass.radius
                // Tuned on the TV: visible from the sofa without reading as a
                // white frame on the heavily blurred glass.
                property real topLightWidth: 1.5 * panel.unit
                property real contourWidth: 1.25 * panel.unit
                property real glowHeight: 16 * panel.unit
                property real backdropMargin: panel.backdropMargin
                property point backdropOrigin: Qt.point(panel.panelX - panel.sideArea.x, 0)
                property size backdropArea: Qt.size(panel.sideArea.width, panel.sideArea.height)
                property real dim: 0
                property real hasBackdrop: liveGlass.hasFrame ? 1 : 0
                property real edgeGain: GlassStyle.edgeGain
                // Only a picture that arrives late fades in. One that was there before
                // the panel opened must not start from the neutral fallback.
                Behavior on hasBackdrop {
                    enabled: panel.panelShown
                    NumberAnimation { duration: panel.panelDuration }
                }
                vertexShader: GlassStyle.glassVertexShader
                fragmentShader: liveGlass.glassShader
            }

            MouseArea {
                anchors.fill: parent
                onClicked: panel.forceActiveFocus()
            }

            // Everything that changes with the page.
            Item {
                id: pageContent
                anchors.fill: parent
                opacity: panel.panelFade
                visible: opacity > 0

                // The single focus surface. It slides between rows.
                FocusSurface {
                    id: focusSurface
                    x: panel.rowXOf(panel.focusedRow) * panel.unit
                    y: panel.focusedRow.y * panel.unit
                    width: panel.rowWidthOf(panel.focusedRow) * panel.unit
                    height: panel.rowHeightOf(panel.focusedRow) * panel.unit
                    unit: panel.unit
                    focusScale: panel.focusScale
                    radius: panel.focusedRow.icon ? 32 : 26
                }

                Item {
                    id: overviewLayer
                    readonly property bool isActive: panel.page === "overview"
                    width: parent.width
                    height: parent.height
                    x: (isActive ? 0 : -panel.pageShift) * panel.unit
                    opacity: isActive ? 1 : 0.004
                    visible: isActive || opacity > 0.01 || !panel.pagesWarm
                    transform: Translate { x: overviewLayer.isActive || panel.pagesWarm ? 0 : panel.warmOffset }

                    Behavior on x {
                        NumberAnimation {
                            duration: panel.pageDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: panel.standardCurve
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: panel.pageDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: panel.standardCurve
                        }
                    }

                    Text {
                        id: title
                        x: panel.leftEdge
                        y: 34 * panel.unit
                        height: 38.4 * panel.unit
                        verticalAlignment: Text.AlignVCenter
                        text: I18n.t("global", "settings")
                        color: panel.textPrimary
                        font.family: GlassStyle.titleFont
                        font.pixelSize: 32 * panel.unit
                        font.letterSpacing: -0.64 * panel.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        x: panel.leftEdge
                        y: 74.4 * panel.unit
                        height: 23.4 * panel.unit
                        verticalAlignment: Text.AlignVCenter
                        text: panel.tvName
                        color: panel.textSecondary
                        font.family: GlassStyle.valueFont
                        font.pixelSize: 18 * panel.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Item {
                        anchors.fill: parent
                        readonly property bool isActive: overviewLayer.isActive
                        Repeater {
                            model: panel.rows.slice(0, panel.firstCategory)
                            delegate: rowDelegate
                        }
                    }

                    // The rows dim behind an open popover.
                    Item {
                        anchors.fill: parent
                        readonly property bool isActive: overviewLayer.isActive
                        Repeater {
                            model: [338, 637]   // between the three groups of rows
                            Rectangle {
                                opacity: panel.stepBack
                                x: 48 * panel.unit
                                y: modelData * panel.unit
                                width: 504 * panel.unit
                                height: panel.hairline
                                color: panel.separator
                            }
                        }

                        Repeater {
                            model: panel.rows.slice(panel.firstCategory)
                            delegate: rowDelegate
                        }
                    }
                }

                Timer {
                    interval: panel.warmDuration
                    running: subpagesLoader.status === Loader.Ready
                    onTriggered: panel.pagesWarm = true
                }

                Loader {
                    id: subpagesLoader
                    anchors.fill: parent
                    onLoaded: PerfProbe.mark("loader.subpages")
                    active: panel.panelShown || panel.pagesNeeded
                    asynchronous: true
                    sourceComponent: Component {
                        Item {
                            Repeater {
                                model: panel.subpages

                                Item {
                                    id: subpage
                                    readonly property bool isActive: panel.page === modelData.key
                                    readonly property string pageKey: modelData.key
                                    readonly property bool wanted: panel.pagesWanted.indexOf(modelData.key) >= 0
                                    property bool warm: false
                                    width: pageContent.width
                                    height: pageContent.height
                                    x: (isActive ? 0 : panel.pageShift) * panel.unit
                                    opacity: isActive ? 1 : 0.004
                                    visible: isActive || opacity > 0.01 || (pageLoader.status === Loader.Ready && !warm)
                                    transform: Translate { x: subpage.isActive || subpage.warm ? 0 : panel.warmOffset }

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: panel.pageDuration
                                            easing.type: Easing.Bezier
                                            easing.bezierCurve: panel.standardCurve
                                        }
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: panel.pageDuration
                                            easing.type: Easing.Bezier
                                            easing.bezierCurve: panel.standardCurve
                                        }
                                    }

                                    // The page itself: built when the focus rests on the row that opens it (in the
                                    // background) or when it opens (then only this page, at once). Built all together
                                    // they stopped the picture for 330 ms and more (docs/performance-plan.md).
                                    Loader {
                                        id: pageLoader
                                        anchors.fill: parent
                                        active: subpage.wanted || subpage.isActive
                                        asynchronous: !subpage.isActive
                                        onLoaded: {
                                            PerfProbe.mark("page.built", subpage.pageKey);
                                            warmTimer.restart();
                                        }
                                        sourceComponent: Component {
                                            Item {
                                            // Everything except the rows, which step back on their own.
                                            Item {
                                                anchors.fill: parent
                                                opacity: panel.stepBack

                                            PageHeader {
                                                x: panel.leftEdge
                                                y: 34 * panel.unit
                                                width: parent.width - 2 * panel.leftEdge
                                                unit: panel.unit
                                                back: modelData.back || I18n.t("global", "settings")
                                                title: modelData.title
                                                subtitle: modelData.key === "languages" ? I18n.t("panel", "detail.menu_language") :
                                                          modelData.key === "apps" ? panel.countText("detail.app_count", panel.apps.length) :
                                                          modelData.key === "picture" ?
                                                          I18n.t("panel", "detail.content_range", { range: panel.dynamicRange === "hdr" ? "HDR" :
                                                                    (panel.dynamicRange === "sdr" ? "SDR" : panel.dynamicRange) }) : ""
                                            }

                                            Repeater {
                                                model: panel.labelsOf(modelData)
                                                SectionTitle {
                                                    x: panel.leftEdge
                                                    y: modelData.y * panel.unit
                                                    height: 24 * panel.unit
                                                    unit: panel.unit
                                                    text: modelData.text
                                                }
                                            }

                                            Repeater {
                                                model: panel.infoRowsOf(subpage.pageKey)

                                                Item {
                                                    x: 48 * panel.unit
                                                    y: modelData.y * panel.unit
                                                    width: 504 * panel.unit
                                                    height: 56 * panel.unit

                                                    Text {
                                                        height: parent.height
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: modelData.label
                                                        color: panel.textSecondary
                                                        font.family: GlassStyle.valueFont
                                                        font.pixelSize: 22 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }

                                                    Text {
                                                        anchors.right: parent.right
                                                        height: parent.height
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: modelData.value
                                                        color: panel.textPrimary
                                                        font.family: GlassStyle.rowFont
                                                        font.pixelSize: 22 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }
                                                }
                                            }

                                                // Shown instead of the speed row while Audio-Guidance is off.
                                    Item {
                                        x: 48 * panel.unit
                                        y: 250 * panel.unit
                                        width: 504 * panel.unit
                                        height: 80 * panel.unit
                                        visible: subpage.pageKey === "access" && panel.audioGuidance !== "on"

                                        Text {
                                            y: 12 * panel.unit
                                            height: 28 * panel.unit
                                            verticalAlignment: Text.AlignVCenter
                                            text: settingsStore.title("option.audioGuidanceSpeed")
                                            color: "#66ffffff"
                                            font.family: panel.rowFamily
                                            font.pixelSize: 22 * panel.unit
                                            font.hintingPreference: Font.PreferNoHinting
                                        }

                                        Text {
                                            y: 42 * panel.unit
                                            height: 22 * panel.unit
                                            verticalAlignment: Text.AlignVCenter
                                            text: I18n.t("panel", "detail.needs_setting", { name: settingsStore.title("option.audioGuidance") })
                                            color: GlassStyle.textDetail
                                            font.family: panel.valueFamily
                                            font.pixelSize: 17 * panel.unit
                                            font.hintingPreference: Font.PreferNoHinting
                                        }

                                        Text {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 34 * panel.unit
                                            height: parent.height
                                            verticalAlignment: Text.AlignVCenter
                                            text: panel.rowValue("guidanceSpeed")
                                            color: "#66ffffff"
                                            font.family: panel.valueFamily
                                            font.pixelSize: 18 * panel.unit
                                            font.hintingPreference: Font.PreferNoHinting
                                        }
                                    }

                                            // App name and icon of the detail page.
                                            Item {
                                                anchors.fill: parent
                                                visible: modelData.key === "appDetail"

                                                AppIcon {
                                                    x: 48 * panel.unit
                                                    y: 160 * panel.unit
                                                    width: 128 * panel.unit
                                                    height: 128 * panel.unit
                                                    cornerRadius: 32 * panel.unit
                                                    source: panel.selectedApp ? panel.selectedApp.iconPath : ""
                                                }

                                                Column {
                                                    x: 200 * panel.unit
                                                    y: 224 * panel.unit - height / 2
                                                    width: 352 * panel.unit
                                                    spacing: 4 * panel.unit

                                                    Text {
                                                        width: parent.width
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                        text: panel.selectedApp ? panel.selectedApp.title : ""
                                                        color: panel.textPrimary
                                                        font.family: GlassStyle.titleFont
                                                        font.pixelSize: 28 * panel.unit
                                                        font.letterSpacing: -0.28 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }

                                                    Text {
                                                        width: parent.width
                                                        wrapMode: Text.WordWrap
                                                        visible: panel.selectedApp !== null && !panel.selectedApp.removable
                                                        text: I18n.t("panel", "detail.preinstalled_fixed")
                                                        color: panel.textSecondary
                                                        font.family: GlassStyle.valueFont
                                                        font.pixelSize: 18 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }
                                                }
                                            }

                                            // Icon, name and port in the head of a device's page.
                                            Item {
                                                anchors.fill: parent
                                                visible: modelData.key === "sourceDetail"

                                                GlassControl {
                                                    x: 48 * panel.unit
                                                    y: 160 * panel.unit
                                                    width: 128 * panel.unit
                                                    height: 128 * panel.unit
                                                    unit: panel.unit
                                                    radius: 32
                                                    fill: "#1affffff"

                                                    Image {
                                                        anchors.centerIn: parent
                                                        opacity: panel.detailDevice && !panel.detailDevice.hdmiPlugIn ? 0.55 : 1
                                                        source: panel.detailDevice ?
                                                                Qt.resolvedUrl("module/icons/detail-" +
                                                                               SourceList.deviceIcon(panel.detailDevice) + ".png") : ""
                                                    }
                                                }

                                                Column {
                                                    x: 200 * panel.unit
                                                    y: 224 * panel.unit - height / 2
                                                    width: 352 * panel.unit
                                                    spacing: 4 * panel.unit

                                                    Text {
                                                        width: parent.width
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                        text: panel.detailDevice ? SourceList.deviceName(panel.detailDevice) : ""
                                                        color: panel.textPrimary
                                                        font.family: GlassStyle.titleFont
                                                        font.pixelSize: 28 * panel.unit
                                                        font.letterSpacing: -0.28 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }

                                                    Text {
                                                        width: parent.width
                                                        text: panel.deviceHeadline(panel.detailDevice)
                                                        color: panel.textSecondary
                                                        font.family: GlassStyle.valueFont
                                                        font.pixelSize: 18 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }
                                                }
                                            }

                                            // The scrolling list of the apps page, built for this page only.
                                            Repeater {
                                                model: subpage.pageKey === "apps" ? 1 : 0

                                                AppsPage {
                                                    y: panel.appsTop * panel.unit
                                                    width: subpage.width
                                                    height: panel.appsHeight * panel.unit
                                                    visible: subpage.opacity > 0.01
                                                    unit: panel.unit
                                                    rowFont: panel.rowFamily
                                                    valueFont: panel.valueFamily
                                                    apps: panel.apps
                                                    focusedIndex: subpage.isActive ? panel.appIndex : -1
                                                    scroll: panel.appScroll
                                                    limit: panel.appLimit
                                                    pitch: panel.appPitch
                                                    duration: panel.focusDuration
                                                    curve: panel.standardCurve
                                                    onRowClicked: {
                                                        panel.appIndex = row;
                                                        panel.moveApp(0);
                                                        panel.openApp();
                                                    }
                                                }
                                            }

                                            // The language list, built for this page only.
                                    Repeater {
                                        model: subpage.pageKey === "languages" ? 1 : 0

                                        LanguagePage {
                                            y: panel.languagesTop * panel.unit
                                            width: subpage.width
                                            height: panel.languagesHeight * panel.unit
                                            visible: subpage.opacity > 0.01
                                            unit: panel.unit
                                            rowFont: panel.rowFamily
                                            valueFont: panel.valueFamily
                                            languages: panel.languages
                                            selected: panel.languageCode
                                            focusedIndex: subpage.isActive ? panel.languageIndex : -1
                                            scroll: panel.languageScroll
                                            limit: panel.languageLimit
                                            pitch: panel.languagePitch
                                            duration: panel.focusDuration
                                            curve: panel.standardCurve
                                            onRowClicked: {
                                                panel.languageIndex = row;
                                                panel.moveLanguage(0);
                                                panel.selectLanguage();
                                            }
                                        }
                                    }

                                    // The active profile in the head of the profiles page.
                                            Item {
                                                anchors.fill: parent
                                                visible: modelData.key === "profiles" && profileStore.active !== null

                                                GlassControl {
                                                    x: 28 * panel.unit
                                                    y: 136 * panel.unit
                                                    width: 544 * panel.unit
                                                    height: 112 * panel.unit
                                                    unit: panel.unit
                                                    radius: 26
                                                    fill: "#1affffff"

                                                    ProfileAvatar {
                                                        x: 20 * panel.unit
                                                        y: 24 * panel.unit
                                                        unit: panel.unit
                                                        size: 64
                                                        initial: profileStore.active ? profileStore.active.initial : ""
                                                        tint: profileStore.active ? profileStore.active.tint : GlassStyle.profileColors[0]
                                                    }

                                                    Text {
                                                        x: 102 * panel.unit
                                                        y: 25 * panel.unit
                                                        width: parent.width - x - 20 * panel.unit
                                                        height: 30 * panel.unit
                                                        verticalAlignment: Text.AlignVCenter
                                                        elide: Text.ElideRight
                                                        text: profileStore.active ? profileStore.active.nick : ""
                                                        color: panel.textPrimary
                                                        font.family: GlassStyle.rowFont
                                                        font.pixelSize: 24 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }

                                                    Text {
                                                        x: 102 * panel.unit
                                                        y: 57 * panel.unit
                                                        width: parent.width - x - 20 * panel.unit
                                                        height: 23 * panel.unit
                                                        verticalAlignment: Text.AlignVCenter
                                                        elide: Text.ElideRight
                                                        text: I18n.t("profile", "detail.active", { type: panel.profileType(profileStore.active) })
                                                        color: panel.textSecondary
                                                        font.family: GlassStyle.valueFont
                                                        font.pixelSize: 18 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }
                                                }
                                            }

                                    // Status and connection values of the network page.
                                            Item {
                                                anchors.fill: parent
                                                visible: modelData.key === "network"

                                                GlassControl {
                                                    x: 28 * panel.unit
                                                    y: 136 * panel.unit
                                                    width: 544 * panel.unit
                                                    height: 112 * panel.unit
                                                    unit: panel.unit
                                                    radius: 26
                                                    fill: "#1affffff"

                                                    GlassControl {
                                                        x: 20 * panel.unit
                                                        y: 24 * panel.unit
                                                        width: 64 * panel.unit
                                                        height: width
                                                        unit: panel.unit
                                                        radius: 32
                                                        fill: "#24ffffff"

                                                        Image {
                                                            anchors.centerIn: parent
                                                            source: panel.networkStatus.icon === undefined ? "" :
                                                                    Qt.resolvedUrl("module/icons/" + panel.networkStatus.icon + ".png")
                                                        }
                                                    }

                                                    Text {
                                                        id: networkTitle
                                                        x: 102 * panel.unit
                                                        y: 16 * panel.unit
                                                        width: parent.width - x - 20 * panel.unit
                                                        height: 30 * panel.unit
                                                        verticalAlignment: Text.AlignVCenter
                                                        elide: Text.ElideRight
                                                        text: panel.networkStatus.title
                                                        color: panel.textPrimary
                                                        font.family: GlassStyle.rowFont
                                                        font.pixelSize: 24 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }

                                                    Text {
                                                        x: 102 * panel.unit
                                                        y: 48 * panel.unit
                                                        width: parent.width - x - 20 * panel.unit
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                        text: panel.networkStatus.detail
                                                        color: panel.textSecondary
                                                        font.family: GlassStyle.valueFont
                                                        font.pixelSize: 18 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }
                                                }

                                    // Shown instead of the row when there is nothing to forget.
                                                Item {
                                                    x: 48 * panel.unit
                                                    y: (panel.networkState === "wired" ? 632 : 620) * panel.unit
                                                    width: 504 * panel.unit
                                                    height: 80 * panel.unit
                                                    visible: panel.networkRows.length < 2

                                                    Text {
                                                        y: 12 * panel.unit
                                                        height: 28 * panel.unit
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: I18n.t("panel", "row.forget_network")
                                                        color: "#66ffffff"
                                                        font.family: GlassStyle.rowFont
                                                        font.pixelSize: 22 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }

                                                    Text {
                                                        y: 42 * panel.unit
                                                        height: 22 * panel.unit
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: panel.networkState === "wired" ?
                                                              I18n.t("panel", "detail.forget_wired") :
                                                              I18n.t("panel", "detail.forget_none")
                                                        color: "#66ffffff"
                                                        font.family: GlassStyle.valueFont
                                                        font.pixelSize: 17 * panel.unit
                                                        font.hintingPreference: Font.PreferNoHinting
                                                    }
                                                }
                                            }
                                            }

                                            Item {
                                                anchors.fill: parent
                                                readonly property bool isActive: subpage.isActive
                                                Repeater {
                                                    model: modelData.key === "apps" || modelData.key === "languages" ? [] : panel.rowsOfPage(modelData.key)
                                                    delegate: rowDelegate
                                                }
                                            }
                                            }
                                        }
                                    }

                                    // A new page is drawn once off screen, so that its first real frame is not its first.
                                    Timer {
                                        id: warmTimer
                                        interval: panel.warmDuration
                                        onTriggered: subpage.warm = true
                                    }
                                }
                            }
                        }
                    }
                }

                Component {
                    id: rowDelegate

                    Item {
                        id: row
                        x: panel.rowXOf(modelData) * panel.unit
                        y: modelData.y * panel.unit
                        width: panel.rowWidthOf(modelData) * panel.unit
                        height: panel.rowHeightOf(modelData) * panel.unit
                        // The row that opened a popover stays as it is, the rest steps back.
                        opacity: focused ? 1 : panel.stepBack

                        readonly property var rowData: modelData
                        readonly property bool isTwoLine: modelData.sublabel !== undefined
                        readonly property bool isChoice: (modelData.key === "device" && modelData.deviceId === undefined) ||
                                                          modelData.key === "mode" ||
                                                          modelData.key === "soundOutput" || modelData.key === "soundMode"
                        readonly property real textTop: (height - 49 * panel.unit) / 2
                        readonly property bool isIcon: modelData.icon === true
                        // The overview's profile row shows the active profile's avatar.
                        readonly property var profileAvatar: modelData.avatar ? modelData.avatar :
                            (modelData.key === "profiles" && profileStore.active ?
                             { initial: profileStore.active.initial, tint: profileStore.active.tint } : null)
                        readonly property bool pageActive: parent !== null && parent.isActive === true
                        readonly property real iconSize: 30 * panel.unit

                        // Colours follow the surface itself, not the key press.
                        readonly property bool focused: pageActive &&
                            Math.abs(focusSurface.x - x) < width / 2 &&
                            Math.abs(focusSurface.y - y) < height / 2

                        Rectangle {
                            anchors.fill: parent
                            radius: (row.isIcon ? 32 : 26) * panel.unit
                            color: panel.hover
                            visible: rowPointer.containsMouse && !row.focused
                        }

                        Item {
                            anchors.fill: parent
                            scale: row.focused ? panel.focusScale : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: panel.focusDuration
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: panel.standardCurve
                                }
                            }

                            // Shared with the settings modal: module/GlassRow.qml.
                            GlassRow {
                                anchors.fill: parent
                                unit: panel.unit
                                titleFont: panel.rowFamily
                                valueFont: panel.valueFamily
                                focused: row.focused
                                // The panel keeps its values in one column, chevron or not.
                                markSpace: 54
                                colorDuration: panel.colorDuration
                                title: row.isIcon ? "" : modelData.title
                                subtitle: modelData.sublabel || ""
                                twoLines: row.isTwoLine
                                titleSize: row.rowData.key === "device" ? 21 : 22
                                subtitleSize: row.rowData.key === "device" ? 16 : 17
                                iconPng: row.profileAvatar ? "" : (row.rowData.png || "")
                                iconOnly: row.isIcon
                                avatar: row.profileAvatar
                                avatarSize: row.rowData.avatarSize || 32
                                leftInset: row.profileAvatar ? 34 + (row.rowData.avatarSize || 32) :
                                           (row.rowData.png !== undefined ? 66 : 20)
                                value: !row.isIcon && !row.isChoice ? panel.rowValue(row.rowData.key) : ""
                                mark: row.isIcon || row.rowData.danger === true || row.rowData.plain === true ? "" :
                                      (row.isChoice ? (row.rowData.active === true ? "choice" : "") : "chevron")
                                toggle: row.rowData.toggle
                                sliderShare: row.rowData.step === undefined ? -1 :
                                             (panel.sliderValue(row.rowData.key) - row.rowData.min) /
                                             (row.rowData.max - row.rowData.min)
                                danger: row.rowData.danger === true
                            }

                            // Shows that the eye comfort mode is on.
                            Rectangle {
                                x: 46 * panel.unit
                                y: 10 * panel.unit
                                width: 8 * panel.unit
                                height: 8 * panel.unit
                                radius: 4 * panel.unit
                                color: GlassStyle.accent
                                visible: row.rowData.key === "eyeComfort" && panel.eyeComfort === "on"
                            }
                        }

                        MouseArea {
                            id: rowPointer
                            anchors.fill: parent
                            hoverEnabled: rootWindow.cursorVisible
                            onClicked: {
                                panel.focusIndex = panel.currentRows.indexOf(row.rowData);
                                panel.forceActiveFocus();
                                panel.activateFocusedRow();
                            }
                        }
                    }
                }

                // Small glass popover with one control, below its shortcut icon and
                // flush with its right edge, since the icons sit at the panel's right.
                Item {
                    id: popoverBox
                    parent: panel
                    z: 10
                    readonly property real panelLeft: (panel.popoverContent === "eyeComfort" ? 552 : 476) * panel.unit - width
                    readonly property real panelTop: 110 * panel.unit
                    x: panel.panelX + panelLeft
                    y: panel.panelInset + panelTop
                    width: 400 * panel.unit
                    height: 76 * panel.unit
                    opacity: panel.popover === "" ? 0 : 1
                    visible: opacity > 0
                    scale: panel.popover === "" ? 0.96 : 1
                    transformOrigin: Item.TopRight

                    Behavior on opacity {
                        NumberAnimation { duration: panel.popoverDuration }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: panel.popoverDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: panel.standardCurve
                        }
                    }

                    SoftShadow {
                        unit: panel.unit
                        boxWidth: popoverBox.width
                        boxHeight: popoverBox.height
                        radius: 28
                        softness: 16
                        drop: 14
                        strength: 0.35
                        pad: 60
                    }

                    ShaderEffect {
                        anchors.fill: parent
                        property variant backdrop: liveGlass.texture
                        property size panelSize: Qt.size(width, height)
                        property real cornerRadius: 28 * panel.unit
                        property real topLightWidth: 1.5 * panel.unit
                        property real contourWidth: 1.25 * panel.unit
                        property real glowHeight: 10 * panel.unit
                        property real backdropMargin: panel.backdropMargin
                        property point backdropOrigin: Qt.point(panel.panelX - panel.sideArea.x + popoverBox.panelLeft,
                                                                popoverBox.panelTop)
                        property size backdropArea: Qt.size(panel.sideArea.width, panel.sideArea.height)
                        property real dim: 0.28
                        property real hasBackdrop: liveGlass.hasFrame ? 1 : 0
                        property real edgeGain: GlassStyle.edgeGain
                        vertexShader: GlassStyle.glassVertexShader
                        fragmentShader: liveGlass.glassShader
                    }

                    GlassSlider {
                        x: 24 * panel.unit
                        y: 35 * panel.unit
                        width: 300 * panel.unit
                        visible: panel.popoverContent === "backlight"
                        unit: panel.unit
                        share: Math.max(0, panel.backlight) / 100
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 24 * panel.unit
                        height: parent.height
                        visible: panel.popoverContent === "backlight"
                        verticalAlignment: Text.AlignVCenter
                        text: panel.rowValue("backlight")
                        color: panel.textPrimary
                        font.family: GlassStyle.rowFont
                        font.pixelSize: 20 * panel.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        x: 24 * panel.unit
                        height: parent.height
                        visible: panel.popoverContent === "eyeComfort"
                        verticalAlignment: Text.AlignVCenter
                        text: settingsStore.title("picture.eyeComfortMode")
                        color: panel.textPrimary
                        font.family: GlassStyle.rowFont
                        font.pixelSize: 22 * panel.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 100 * panel.unit
                        height: parent.height
                        visible: panel.popoverContent === "eyeComfort"
                        verticalAlignment: Text.AlignVCenter
                        text: panel.rowValue("eyeComfort")
                        color: panel.textSecondary
                        font.family: GlassStyle.valueFont
                        font.pixelSize: 18 * panel.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    // Switch, 64 × 36 with a 28 px knob.
                    GlassSwitch {
                        x: 316 * panel.unit
                        y: 20 * panel.unit
                        visible: panel.popoverContent === "eyeComfort"
                        unit: panel.unit
                        on: panel.eyeComfort === "on"
                    }
                }
            }
        }

        // Dialogs, name entry and Wi-Fi: built on first use, in the background, see withFlow().
        // The window is created anew for every key press, so whatever is built up front is
        // paid every time.
        Loader {
            id: modalLoader
            anchors.fill: parent
            onLoaded: {
                PerfProbe.mark("loader.flow");
                panel.flowBuilt();
            }
            z: 20
            asynchronous: true
        }

        // The large settings modal. Built only when it is asked for: it reads several
        // hundred settings, which no plain opening of the panel should wait for.
        Loader {
            id: settingsLoader
            anchors.fill: parent
            onLoaded: {
                PerfProbe.mark("loader.settings");
                panel.settingsBuilt();
            }
            z: 19
            asynchronous: true
        }

        // Black while a profile switch runs (K3-Profil-Wechsel); the panel closes once LG
        // reports the new profile.
        ProfileSwitchScreen {
            anchors.fill: parent
            z: 30
            unit: panel.unit
            profile: profileStore.switching || panel.modalSwitching
            started: profileStore.switching ? profileStore.switchStarted : panel.modalSwitchStarted
        }

        // Short confirmation inside the panel, for example after renaming the TV.
        GlassControl {
            parent: glass
            x: 28 * panel.unit
            y: 876 * panel.unit
            width: 544 * panel.unit
            height: 64 * panel.unit
            z: 5
            unit: panel.unit
            radius: 32
            fill: "#e61c202c"
            opacity: panel.toastShown ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: panel.popoverDuration }
            }

            Rectangle {
                x: 24 * panel.unit
                anchors.verticalCenter: parent.verticalCenter
                width: 32 * panel.unit
                height: width
                radius: width / 2
                color: GlassStyle.accent

                Image {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("module/icons/check-18.png")
                }
            }

            Text {
                x: 70 * panel.unit
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: panel.toastText
                color: panel.textPrimary
                font.family: panel.rowFamily
                font.pixelSize: 20 * panel.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        ChoicePopover {
            id: choicePopover
            z: 10
            unit: panel.unit
            titleFont: panel.titleFamily
            rowFont: panel.rowFamily
            backdrop: liveGlass.texture
            glassShader: liveGlass.glassShader
            shadowShader: liveGlass.shadowShader
            backdropMargin: panel.backdropMargin
            backdropArea: panel.sideArea
            hasBackdrop: liveGlass.hasFrame ? 1 : 0
            curve: panel.standardCurve
            onChosen: panel.applyChoice(value)
            onTimeChosen: panel.applyTimer(hour, minute)
            onTimerOff: panel.disableTimer()
        }

        Timer {
            id: modeSwitch
            property string target: "panel"
            interval: panel.panelDuration + 20
            onTriggered: panel.modeSwitched(target)
        }

        GameStatus {
            id: gameStatus
            onDecided: panel.gameDecided(game)
        }

        GameBar {
            id: gameBar
            anchors.fill: parent
            z: 9
            unit: panel.unit
            store: settingsStore
            status: gameStatus
            covered: panel.panelHidden
            backdrop: liveGlass.texture
            glassShader: liveGlass.glassShader
            shadowShader: liveGlass.shadowShader
            backdropMargin: panel.backdropMargin
            backdropArea: panel.gameArea
            hasBackdrop: liveGlass.hasFrame ? 1 : 0
            fadeDuration: panel.panelDuration
            onCloseRequested: panel.close()
            onQuickMenu: panel.gameToPanel()
            onGamesSettings: panel.openSettings("games", "")
        }

        // A launch with page "settings:<area>" opens the modal once the panel stands.
        Timer {
            id: settingsOpenTimer
            property string area: "picture"
            property string page: ""
            interval: 60
            onTriggered: panel.openSettings(area, page)
        }

        ParallelAnimation {
            id: openAnimation
            onStopped: {
                if (panel.closing) return;
                PerfProbe.mark("open.done");
                PerfProbe.beginPhase("shown");
                panel.panelShown = true;
                panel.readApps();
                if (panel.launchPage === "wifi") {
                    panel.openPage("network");
                    withFlow(function (flow) { flow.openList(); });
                } else if (panel.launchPage.indexOf("settings") === 0) {
                    // "settings", "settings:<area>" or "settings:<area>:<page>": straight into
                    // the settings modal, for example from novOS' update notice.
                    settingsOpenTimer.area = panel.launchPage.split(":")[1] || "picture";
                    settingsOpenTimer.page = panel.launchPage.split(":")[2] || "";
                    settingsOpenTimer.restart();
                } else if (panel.launchPage !== "") {
                    panel.openPage(panel.launchPage);
                }
            }
            NumberAnimation {
                target: glass
                property: "opacity"
                to: panel.settingsLaunch ? 0 : 1
                duration: panel.panelDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: panel.standardCurve
            }
            NumberAnimation {
                target: glassOffset
                property: "x"
                to: 0
                duration: panel.panelDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: panel.standardCurve
            }
        }

        // The panel steps back to the game bar; the window stays.
        ParallelAnimation {
            id: panelOut
            NumberAnimation {
                target: glass
                property: "opacity"
                to: 0
                duration: panel.panelDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: panel.standardCurve
            }
            NumberAnimation {
                target: glassOffset
                property: "x"
                to: 48 * panel.unit
                duration: panel.panelDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: panel.standardCurve
            }
        }

        SequentialAnimation {
            id: closeAnimation
            ParallelAnimation {
                NumberAnimation {
                    target: glass
                    property: "opacity"
                    to: 0
                    duration: panel.panelDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: panel.standardCurve
                }
                NumberAnimation {
                    target: glassOffset
                    property: "x"
                    to: 48 * panel.unit
                    duration: panel.panelDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: panel.standardCurve
                }
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
