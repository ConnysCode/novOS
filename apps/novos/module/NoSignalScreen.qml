import QtQuick 2.12
import "."

// The screen while the current source sends no picture, concept E of K3-KeinSignal: a flat
// photo over the whole screen and a row of pills at the bottom centre. On the left the status
// pill with the case and the time, beside it the actions; the focus starts on the first one.
// Nothing moves. After a minute without a key the actions fade and the photo dims (E3), any
// key brings them back without doing anything. In the last two minutes before the TV turns
// itself off a countdown pill and "Anlassen" join (E4); any key keeps the TV on.
//
// The owner decides the case (icon, title, detail, actions) and what an action does; it gets
// the keys through handleKey().
Item {
    id: screen

    property real unit: 1
    property string titleFont: GlassStyle.titleFont
    property string rowFont: GlassStyle.rowFont
    property string valueFont: GlassStyle.valueFont
    property bool shown: false
    property url pictureSource
    property string pictureCredit: ""
    property string icon: ""             // an icon of this module, without ".png"
    property bool busy: false            // a spinner in place of the icon
    property string title: ""
    property string detail: ""
    property var actions: []             // { id, label, icon }; icon names a 26 px pair "<icon>-26(-dark)"
    property int focusIndex: 0           // -1: no action has the focus yet
    property int countdown: -1           // seconds until the TV turns off, -1 without countdown
    property bool covered: false         // the source bar lies over the row; the row steps aside
    property date now: new Date()
    // What the glass samples, for a bar the owner lays over this screen.
    readonly property Item backdropItem: backdrop

    property bool quiet: false
    readonly property bool counting: countdown >= 0
    readonly property bool calm: quiet || counting
    readonly property bool actionsShown: (!quiet || counting) && !covered
    readonly property var shownActions: counting ? [{ id: "stayOn", label: I18n.t("no_signal", "action.stay_on"), icon: "" }]
                                                 : actions
    readonly property int shownFocus: counting ? 0 : focusIndex
    readonly property bool settled: opacity === 1
    property real calmLevel: calm ? 1 : 0
    property Item focusedPill: null

    signal activated(string id)
    signal stayOn()

    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: GlassStyle.pageDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }
    Behavior on calmLevel {
        NumberAnimation { duration: GlassStyle.pageDuration }
    }

    onShownChanged: if (shown) wake(); else quietTimer.stop()
    // The minute without a key starts again once the source bar is gone.
    onCoveredChanged: if (covered) quietTimer.stop(); else if (shown) wake()

    // The focus surface goes where the focused pill stands. Set, not bound: a pill that goes
    // with a new case must not pull the surface to the edge on its way out.
    function placePlate(pill) {
        focusedPill = pill;
        focusPlate.x = pill.x;
        focusPlate.width = pill.width;
    }

    function wake() {
        quiet = false;
        if (shown && !covered) quietTimer.restart();
        now = new Date();
    }

    function countdownText(seconds) {
        var rest = Math.max(0, seconds);
        var minutes = Math.floor(rest / 60);
        var left = rest % 60;
        return minutes + ":" + (left < 10 ? "0" : "") + left;
    }

    // Every key lands here while the screen stands. True when the screen took it.
    function handleKey(key, autoRepeat) {
        if (counting) {
            if (!autoRepeat) stayOn();
            wake();
            return true;
        }
        var waking = quiet;
        wake();
        if (waking) return true;
        var last = actions.length - 1;
        if (key === Qt.Key_Left) {
            if (last >= 0) focusIndex = focusIndex < 0 ? 0 : Math.max(0, focusIndex - 1);
        } else if (key === Qt.Key_Right) {
            if (last >= 0) focusIndex = focusIndex < 0 ? 0 : Math.min(last, focusIndex + 1);
        } else if (Remote.isOk(key)) {
            if (!autoRepeat && focusIndex >= 0 && focusIndex <= last) activated(actions[focusIndex].id);
        }
        return true;
    }

    Timer {
        id: quietTimer
        interval: GlassStyle.noSignalQuietDelay
        onTriggered: screen.quiet = true
    }

    Timer {
        interval: GlassStyle.clockTick
        running: screen.shown
        repeat: true
        onTriggered: screen.now = new Date()
    }

    // What the glass samples: the photo and the gradient under the pills. The glass hides it,
    // so both are drawn again below, as they are.
    Item {
        id: backdrop
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: GlassStyle.scrimColor
        }

        Image {
            id: picture
            anchors.fill: parent
            asynchronous: true
            cache: false
            source: screen.pictureSource
            sourceSize: Qt.size(1920, 1080)
            fillMode: Image.PreserveAspectCrop
        }

        Rectangle {
            width: parent.width
            height: GlassStyle.floorScrimHeight * screen.unit
            anchors.bottom: parent.bottom
            gradient: Gradient {
                GradientStop { position: 0; color: GlassStyle.scrim(0) }
                GradientStop { position: 1; color: GlassStyle.scrim(GlassStyle.floorScrim) }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: GlassStyle.scrimColor
    }

    ShaderEffect {
        anchors.fill: parent
        property variant source: picture
        visible: picture.status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        color: GlassStyle.scrim(GlassStyle.stackScrims(GlassStyle.contentScrim, GlassStyle.quietScrim * screen.calmLevel))
    }

    Rectangle {
        width: parent.width
        height: GlassStyle.floorScrimHeight * screen.unit
        anchors.bottom: parent.bottom
        gradient: Gradient {
            GradientStop { position: 0; color: GlassStyle.scrim(0) }
            GradientStop { position: 1; color: GlassStyle.scrim(GlassStyle.floorScrim) }
        }
    }

    ImageGlass {
        id: rowGlass
        sourceItem: screen.visible ? backdrop : null    // nothing to blur while the screen is gone
        unit: screen.unit
        area: Qt.rect(GlassStyle.bottomBarInset * screen.unit, strip.y,
                      screen.width - 2 * GlassStyle.bottomBarInset * screen.unit, strip.height)
        veil: GlassStyle.veilBeyondContent(GlassStyle.stackScrims(GlassStyle.contentScrim,
                                                                  GlassStyle.quietScrim * screen.calmLevel))
        visible: false
    }

    // Each picture names its author and licence, as CC BY asks.
    Text {
        anchors.right: parent.right
        anchors.rightMargin: GlassStyle.bottomBarInset * screen.unit
        y: GlassStyle.bottomBarInset * screen.unit
        visible: screen.pictureCredit !== ""
        text: I18n.t("launcher", "label.image_credit", { credit: screen.pictureCredit })
        color: GlassStyle.textFaint
        font.family: screen.rowFont
        font.pixelSize: GlassStyle.sectionSize * screen.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    // The row of pills. The strip carries the focus surface along when the row grows or shrinks.
    Item {
        id: strip
        x: (screen.width - width) / 2
        y: screen.height - height - GlassStyle.bottomBarInset * screen.unit
        width: row.width
        height: 88 * screen.unit
        z: 2
        opacity: screen.covered ? 0 : 1
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: GlassStyle.popoverDuration } }

        Behavior on x {
            enabled: screen.settled
            NumberAnimation { duration: GlassStyle.pageDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
        }

        // The single focus surface glides between the action pills, below their text.
        FocusSurface {
            id: focusPlate
            height: parent.height
            unit: screen.unit
            radius: 44
            focusScale: GlassStyle.focusScale
            animated: screen.settled
            opacity: screen.actionsShown && screen.shownFocus >= 0 && screen.shownActions.length > 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }
        }

        Row {
            id: row
            height: strip.height
            spacing: 12 * screen.unit

            // The case and the time.
            Item {
                id: statusPill
                width: statusRow.width + (24 + 30) * screen.unit
                height: row.height
                opacity: screen.quiet && !screen.counting ? GlassStyle.quietOpacity : 1

                Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }

                SoftShadow {
                    unit: screen.unit
                    radius: 44
                    softness: 30
                    drop: 24
                    strength: 0.30
                    pad: 110
                }

                GlassCard {
                    anchors.fill: parent
                    unit: screen.unit
                    cornerRadius: 44 * screen.unit
                    backdrop: rowGlass.texture
                    glassShader: GlassStyle.glassShader
                    backdropMargin: rowGlass.margin
                    backdropArea: Qt.rect(rowGlass.area.x - strip.x - statusPill.x, rowGlass.area.y - strip.y,
                                          rowGlass.area.width, rowGlass.area.height)
                    hasBackdrop: 1
                    shadow: ""
                }

                Row {
                    id: statusRow
                    x: 24 * screen.unit
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16 * screen.unit

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34 * screen.unit
                        height: 34 * screen.unit

                        Image {
                            anchors.fill: parent
                            visible: !screen.busy && screen.icon !== ""
                            smooth: true
                            source: screen.icon !== "" ? Qt.resolvedUrl("icons/" + screen.icon + ".png") : ""
                        }

                        Spinner {
                            anchors.centerIn: parent
                            size: 30 * screen.unit
                            lineWidth: 3 * screen.unit
                            visible: screen.busy
                            running: screen.busy && screen.shown
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * screen.unit

                        Text {
                            text: screen.title
                            color: GlassStyle.textPrimary
                            font.family: screen.titleFont
                            font.pixelSize: GlassStyle.rowSize * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Text {
                            visible: text !== ""
                            text: screen.detail
                            color: GlassStyle.textSecondary
                            font.family: screen.valueFont
                            font.pixelSize: GlassStyle.detailSize * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * screen.unit
                        height: 48 * screen.unit

                        Rectangle {
                            x: 6 * screen.unit
                            width: Math.max(1, screen.unit)
                            height: parent.height
                            color: GlassStyle.divider
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatTime(screen.now, "hh:mm")
                        color: GlassStyle.textPrimary
                        font.family: screen.titleFont
                        font.pixelSize: GlassStyle.pillClockSize * screen.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }

            // The last two minutes before the TV turns itself off.
            Item {
                id: countdownPill
                visible: screen.counting
                width: countdownRow.width + (24 + 30) * screen.unit
                height: row.height

                SoftShadow {
                    unit: screen.unit
                    radius: 44
                    softness: 30
                    drop: 24
                    strength: 0.30
                    pad: 110
                }

                GlassCard {
                    anchors.fill: parent
                    unit: screen.unit
                    cornerRadius: 44 * screen.unit
                    backdrop: rowGlass.texture
                    glassShader: GlassStyle.glassShader
                    backdropMargin: rowGlass.margin
                    backdropArea: Qt.rect(rowGlass.area.x - strip.x - countdownPill.x, rowGlass.area.y - strip.y,
                                          rowGlass.area.width, rowGlass.area.height)
                    hasBackdrop: 1
                    shadow: ""
                }

                Row {
                    id: countdownRow
                    x: 24 * screen.unit
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16 * screen.unit

                    ProgressRing {
                        anchors.verticalCenter: parent.verticalCenter
                        unit: screen.unit
                        size: 40
                        lineWidth: 4
                        value: screen.countdown / (GlassStyle.noSignalWarning / 1000)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * screen.unit

                        Text {
                            text: I18n.t("no_signal", "countdown.title", { time: screen.countdownText(screen.countdown) })
                            color: GlassStyle.textPrimary
                            font.family: screen.titleFont
                            font.pixelSize: GlassStyle.rowSize * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Text {
                            text: I18n.t("no_signal", "countdown.detail")
                            color: GlassStyle.textSecondary
                            font.family: screen.valueFont
                            font.pixelSize: GlassStyle.detailSize * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }

            Repeater {
                model: screen.shownActions

                Item {
                    id: actionPill
                    readonly property bool focused: index === screen.shownFocus
                    readonly property bool hasIcon: (modelData.icon || "") !== ""
                    readonly property real lead: (hasIcon ? 28 : 34) * screen.unit
                    width: actionRow.width + lead + 34 * screen.unit
                    height: row.height
                    opacity: screen.actionsShown ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }

                    // The focus surface takes this place.
                    onFocusedChanged: if (focused) screen.placePlate(actionPill)
                    onXChanged: if (focused) screen.placePlate(actionPill)
                    onWidthChanged: if (focused) screen.placePlate(actionPill)
                    Component.onCompleted: if (focused) screen.placePlate(actionPill)

                    SoftShadow {
                        unit: screen.unit
                        radius: 44
                        softness: 30
                        drop: 24
                        strength: 0.30
                        pad: 110
                        opacity: actionPill.focused ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
                    }

                    GlassCard {
                        anchors.fill: parent
                        unit: screen.unit
                        cornerRadius: 44 * screen.unit
                        backdrop: rowGlass.texture
                        glassShader: GlassStyle.glassShader
                        backdropMargin: rowGlass.margin
                        backdropArea: Qt.rect(rowGlass.area.x - strip.x - actionPill.x, rowGlass.area.y - strip.y,
                                              rowGlass.area.width, rowGlass.area.height)
                        hasBackdrop: 1
                        shadow: ""
                        opacity: actionPill.focused ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
                    }

                    Row {
                        id: actionRow
                        x: actionPill.lead
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12 * screen.unit
                        z: 2

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: actionPill.hasIcon
                            width: 26 * screen.unit
                            height: 26 * screen.unit
                            smooth: true
                            source: actionPill.hasIcon ? Qt.resolvedUrl("icons/" + modelData.icon + "-26" +
                                                                        (actionPill.focused ? "-dark" : "") + ".png") : ""
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || ""
                            color: actionPill.focused ? GlassStyle.focusText : GlassStyle.textPrimary
                            font.family: screen.titleFont
                            font.pixelSize: GlassStyle.rowSize * screen.unit
                            font.hintingPreference: Font.PreferNoHinting

                            Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            screen.wake();
                            if (screen.counting) {
                                screen.stayOn();
                            } else {
                                screen.focusIndex = index;
                                screen.activated(modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
