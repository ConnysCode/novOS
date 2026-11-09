import QtQuick 2.12
import "."
import "GameMode.js" as GameMode

// The game bar (K3-Spiel-A-HUD and K3-Spiel-A-Genre, docs/game-overlay-plan.md): one
// glass bar top centre with the genre chip, four live values and four actions. It
// replaces LG's game dashboard on the gear key while a game runs. The single white
// surface glides with Left and Right over the chip and the actions; the values take no
// focus. OK on the chip opens the genre list below it, and the bar steps back.
//
// The owner places it over the whole window, hands it the shared settings store, the
// GameStatus and the glass, and answers its signals.
Item {
    id: bar

    property real unit: 1
    property var store: null                  // SettingsStore
    property var status: null                 // GameStatus
    property variant backdrop
    property string glassShader: ""
    property string shadowShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property int fadeDuration: GlassStyle.popoverDuration
    property bool demo: false                 // preview: stand-in values where the TV has none

    property bool shown: false
    property bool covered: false              // a modal stands in front; the bar waits behind it
    property int focusIndex: 0                // 0 the chip, 1 … 4 the actions
    readonly property bool popoverShown: genreList.shown

    signal closeRequested()
    signal quickMenu()
    signal gamesSettings()

    // ---- Values -------------------------------------------------------------------

    readonly property int revision: store ? store.revision : 0
    function val(key) {
        return revision >= 0 && store ? store.val(key) : undefined;
    }
    function has(key) {
        return revision >= 0 && store ? store.has(key) : false;
    }
    function t(key, params) {
        return I18n.t("game", key, params);
    }

    readonly property string genre: String(val("other.gameGenre") || "Standard")
    readonly property string darkMode: String(val("other.darkMode") || "off")
    readonly property int frameRate: status && status.frameRate >= 0 ? status.frameRate : (demo ? 120 : -1)
    readonly property string vrrType: status && status.vrrType !== "" ? status.vrrType : (demo ? "vrr" : "")
    readonly property var stats: buildStats(GameMode.statusList(val("other.gameDashboardStatusList")),
                                            frameRate, vrrType, revision)

    function number(key) {
        var value = val(key);
        return value === undefined || value === null || value === "" ? "–" : String(value);
    }

    function onOff(value) {
        return value === "on" ? t("value.on") : (value === "off" ? t("value.off") : "–");
    }

    function hasGameSound() {
        var modes = store ? store.options("sound.soundMode") : [];
        for (var i = 0; i < modes.length; i++) {
            if (modes[i] === "game" || modes[i].value === "game") return true;
        }
        return false;
    }

    // One entry per value of LG's status list, in its order.
    function buildStats(list, rate, vrr, revision) {
        var result = [];
        for (var i = 0; i < list.length; i++) {
            var name = list[i];
            if (name === "fps") {
                result.push({ label: t("stat.frame_rate"), value: rate >= 0 ? String(rate) : "–",
                              suffix: t("unit.fps"), minWidth: 128 });
            } else if (name === "vrr_aiGameSound_whiteStabilizer") {
                var slot = GameMode.secondSlot(has("other.gameOptimization") || has("other.freesync"), hasGameSound());
                if (slot === "vrr") {
                    var state = GameMode.vrrState(vrr);
                    result.push({ label: t("stat.vrr"), value: state === "" ? "–" : t("value." + state),
                                  suffix: "", minWidth: 170 });
                } else if (slot === "aiGameSound") {
                    result.push({ label: t("stat.ai_game_sound"), value: onOff(val("sound.aigamesound")),
                                  suffix: "", minWidth: 170 });
                } else {
                    result.push({ label: t("stat.white_stabilizer"), value: number("other.whiteStabilizer"),
                                  suffix: t("unit.of_twenty"), minWidth: 170 });
                }
            } else if (name === "blackStabilizer") {
                result.push({ label: t("stat.black_stabilizer"), value: number("other.blackStabilizer"),
                              suffix: t("unit.of_twenty"), minWidth: 128 });
            } else if (name === "lowLatency") {
                var level = val("picture.memcDelayLevel");
                result.push({ label: t("stat.latency"),
                              value: level === undefined ? "–" : t(level === "none" ? "value.low" : "value.normal"),
                              suffix: "", minWidth: 128 });
            } else {
                // A value LG's dashboard offers that this bar does not read yet.
                result.push({ label: name, value: "–",
                              suffix: "", minWidth: 128 });
            }
        }
        return result;
    }

    // ---- Actions ------------------------------------------------------------------

    readonly property var actions: [
        { key: "darkRoom", icon: "game-dark-room",
          label: darkMode === "off" ? t("action.dark_room") : t("action.dark_room_level", { level: darkMode === "level2" ? 2 : 1 }) },
        { key: "multiView", icon: "game-multi-view", label: t("action.multi_view") },
        { key: "games", icon: "game-games", label: t("action.games") },
        { key: "quick", icon: "game-quick", label: t("action.quick_menu") }
    ]

    function actionIndex(key) {
        for (var i = 0; i < actions.length; i++) {
            if (actions[i].key === key) return i + 1;
        }
        return 0;
    }

    function open(focusKey) {
        genreList.shown = false;
        focusIndex = focusKey ? actionIndex(focusKey) : 0;
        shown = true;
    }

    function hide() {
        genreList.shown = false;
        shown = false;
    }

    function activate() {
        if (focusIndex === 0) {
            openGenres();
            return;
        }
        var key = actions[focusIndex - 1].key;
        if (key === "darkRoom") {
            if (store) store.set("other.darkMode", GameMode.nextDarkStep(darkMode));
        } else if (key === "multiView") {
            if (status) status.launchMultiView();
            closeRequested();
        } else if (key === "games") {
            gamesSettings();
        } else if (key === "quick") {
            quickMenu();
        }
    }

    function openGenres() {
        var options = [];
        for (var i = 0; i < GameMode.genres.length; i++) {
            var item = GameMode.genres[i];
            options.push({ label: t("genre." + item.key), detail: t("genre_detail." + item.key), value: item.value });
        }
        genreList.openList(t("label.genre"), options, genre, 0);
    }

    // Keys of the remote. Press moves and acts, release closes, as in the panel.
    function handlePress(key, autoRepeat) {
        if (genreList.shown) {
            genreList.handleKey(key, autoRepeat);
        } else if (key === Qt.Key_Left) {
            focusIndex = Math.max(0, focusIndex - 1);
        } else if (key === Qt.Key_Right) {
            focusIndex = Math.min(actions.length, focusIndex + 1);
        } else if (Remote.isOk(key)) {
            if (!autoRepeat) activate();
        } else if (key !== Qt.Key_Up && key !== Qt.Key_Down && !Remote.isBack(key)) {
            return false;
        }
        return true;
    }

    function handleRelease(key) {
        if (!Remote.isBack(key)) return false;
        if (genreList.shown) genreList.close();
        else closeRequested();
        return true;
    }

    // ---- Look ---------------------------------------------------------------------

    readonly property real padding: 16 * unit
    readonly property real gap: 28 * unit
    // Everything but the chip steps back while the genre list is open (popover rule).
    property real stepBack: genreList.shown ? GlassStyle.dimmedOpacity : 1
    Behavior on stepBack { NumberAnimation { duration: GlassStyle.popoverDuration } }

    readonly property Item focusedItem: focusIndex === 0 ? chip : actionRepeater.itemAt(focusIndex - 1)
    readonly property real focusRadius: focusIndex === 0 ? GlassStyle.chipRadius : GlassStyle.pillRadius

    opacity: shown && !covered ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation { duration: bar.fadeDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }

    GlassCard {
        id: card
        unit: bar.unit
        x: Math.round((bar.width - width) / 2)
        y: GlassStyle.topBarInset * bar.unit + (bar.shown ? 0 : -GlassStyle.pageShift * bar.unit)
        width: content.width + 2 * bar.padding
        height: content.height + 2 * bar.padding
        cornerRadius: GlassStyle.topBarRadius * bar.unit
        glides: false
        shadow: "shadow-panel"
        backdrop: bar.backdrop
        glassShader: bar.glassShader
        backdropMargin: bar.backdropMargin
        backdropArea: bar.backdropArea
        hasBackdrop: bar.hasBackdrop

        Behavior on y {
            NumberAnimation { duration: bar.fadeDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
        }

        FocusSurface {
            unit: bar.unit
            x: bar.padding + (bar.focusIndex === 0 ? chip.x : actionsRow.x + (bar.focusedItem ? bar.focusedItem.x : 0))
            y: bar.padding + (bar.focusIndex === 0 ? chip.y : actionsRow.y + (bar.focusedItem ? bar.focusedItem.y : 0))
            width: bar.focusedItem ? bar.focusedItem.width : 0
            height: bar.focusedItem ? bar.focusedItem.height : 0
            radius: bar.focusRadius
            focusScale: GlassStyle.focusScale
        }

        Row {
            id: content
            x: bar.padding
            y: bar.padding
            spacing: bar.gap

            // Genre chip: symbol, the capital label and the genre.
            Item {
                id: chip
                readonly property bool focused: bar.focusIndex === 0
                anchors.verticalCenter: parent.verticalCenter
                width: chipRow.width + 42 * bar.unit
                height: 80 * bar.unit

                GlassControl {
                    anchors.fill: parent
                    opacity: chip.focused ? 0 : 1
                    visible: opacity > 0
                    unit: bar.unit
                    radius: GlassStyle.chipRadius
                    Behavior on opacity {
                        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
                    }
                }

                Row {
                    id: chipRow
                    x: 18 * bar.unit
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14 * bar.unit

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: genreIcon.width
                        height: genreIcon.height

                        Image {
                            id: genreIcon
                            source: Qt.resolvedUrl("icons/game-genre.png")
                            opacity: chip.focused ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
                        }

                        Image {
                            source: Qt.resolvedUrl("icons/game-genre-dark.png")
                            opacity: chip.focused ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * bar.unit

                        SectionTitle {
                            unit: bar.unit
                            text: bar.t("label.genre")
                            color: chip.focused ? GlassStyle.focusSecondary : GlassStyle.textMuted
                            Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                        }

                        Text {
                            text: bar.t("genre." + GameMode.genreKey(bar.genre))
                            color: chip.focused ? GlassStyle.focusText : GlassStyle.textPrimary
                            font.family: GlassStyle.titleFont
                            font.pixelSize: GlassStyle.chipValueSize * bar.unit
                            font.hintingPreference: Font.PreferNoHinting
                            Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        bar.focusIndex = 0;
                        bar.activate();
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, bar.unit)
                height: chip.height - 12 * bar.unit
                color: GlassStyle.divider
                opacity: bar.stepBack
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 32 * bar.unit
                opacity: bar.stepBack

                Repeater {
                    model: bar.stats

                    GameStat {
                        unit: bar.unit
                        label: modelData.label
                        value: modelData.value
                        suffix: modelData.suffix
                        minWidth: modelData.minWidth
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, bar.unit)
                height: chip.height - 12 * bar.unit
                color: GlassStyle.divider
                opacity: bar.stepBack
            }

            Row {
                id: actionsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * bar.unit
                opacity: bar.stepBack

                Repeater {
                    id: actionRepeater
                    model: bar.actions

                    FooterButton {
                        unit: bar.unit
                        fontFamily: GlassStyle.rowFont
                        label: modelData.label
                        icon: modelData.icon
                        focused: bar.focusIndex === index + 1
                        onClicked: {
                            bar.focusIndex = index + 1;
                            bar.activate();
                        }
                    }
                }
            }
        }
    }

    // The genre list, 460 px wide, 16 px below the bar at the chip's left edge.
    ChoicePopover {
        id: genreList
        z: 10
        unit: bar.unit
        x: card.x + bar.padding + chip.x
        y: card.y + card.height + 16 * bar.unit
        width: 460 * bar.unit
        titleFont: GlassStyle.titleFont
        rowFont: GlassStyle.rowFont
        backdrop: bar.backdrop
        glassShader: bar.glassShader
        shadowShader: bar.shadowShader
        backdropMargin: bar.backdropMargin
        backdropArea: bar.backdropArea
        hasBackdrop: bar.hasBackdrop
        onChosen: {
            if (bar.store) bar.store.set("other.gameGenre", value);
            close();
        }
    }
}
