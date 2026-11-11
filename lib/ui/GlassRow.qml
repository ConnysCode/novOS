import QtQuick 2.12
import "."

// The content of one list row, shared by the quick panel and the settings modal: icon,
// title, second line, value, mark (chevron, ↗, choice tick or check), switch and slider.
// The owner places the row, draws the focus surface, scales and handles keys and pointer.
// Measures are the panel's, as accepted on the TV; see docs/design-system.md, "Aufbau von
// Unterseiten". Value and mark sit in the middle of the whole row, also under a second
// line; only a slider keeps its value level with its title.
Item {
    id: glassRow

    property real unit: 1
    property string titleFont: ""
    property string valueFont: ""
    property bool focused: false

    property string title: ""
    property string subtitle: ""
    property bool twoLines: subtitle !== ""
    property string value: ""
    property string mark: ""            // "", "chevron", "down", "external", "choice" (18 px) or "check" (24 px)
    property var toggle: undefined      // true or false draws the switch
    property real sliderShare: -1       // 0..1 draws the slider under the title
    // A slider around a centre (a balance, a trim from -5 to 10): the share of that centre,
    // where the fill starts at a mark, with a knob; -1 fills from the start. sliderEnds: a
    // short text in a circle at each end of the track, ["L", "R"].
    property real sliderOrigin: -1
    property var sliderEnds: null
    readonly property bool hasEnds: !!sliderEnds && sliderEnds.length === 2
    // With a second line and end circles the track moves down by 13 (row 124 instead of 104).
    readonly property real sliderY: twoLines && hasEnds ? 87 : 74
    property bool danger: false
    property bool disabled: false
    // A device list (K3-Einst-Geraeteliste): busy draws a 26 px spinner at the right instead of
    // the mark while something runs ("Verbindet …"); iconBusy puts it in the icon's place (the
    // search row while it searches); tone "warning" colours the second line ("fehlgeschlagen").
    property bool busy: false
    property bool iconBusy: false
    property string tone: ""
    property real titleSize: 22
    property real subtitleSize: 17
    property int colorDuration: 120

    // Icon at the left: a picture pair icons/row-<name>(-dark).png from the app, drawn by
    // build-icons.py. iconOnly centres it and drops the text (panel shortcuts).
    property string iconPng: ""
    property bool iconOnly: false
    readonly property bool hasIcon: iconPng !== "" || iconBusy
    // A profile's avatar instead of the icon: { initial, tint }. 32 px leaves the text where
    // an icon leaves it, a larger one moves it right by the difference.
    property var avatar: null
    property real avatarSize: 32
    readonly property bool hasAvatar: avatar !== null && avatar !== undefined
    property real leftInset: hasAvatar ? 34 + avatarSize : (hasIcon ? 66 : 20)
    readonly property real iconSize: 30 * unit

    readonly property real logicalHeight: height / unit
    readonly property bool slider: sliderShare >= 0
    readonly property bool hasToggle: toggle === true || toggle === false
    readonly property real titleTop: slider ? 18 : (twoLines ? (logicalHeight - 49) / 2 : 0)
    readonly property real titleHeight: slider ? 30 : (twoLines ? 27 : logicalHeight)
    // Room for the mark at the right of the value; the panel keeps 54 for every row.
    property real markSpace: mark === "" && !busy ? 20 : 54
    readonly property color mainColor: focused ? GlassStyle.focusText : GlassStyle.textPrimary
    readonly property color sideColor: focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
    // Room the text leaves at the right for value, mark or switch.
    readonly property real rightReserve: Math.max(hasToggle ? 100 : 44,
                                                  (valueText.visible ? valueText.implicitWidth / unit + 16 : 0) + markSpace)

    // The icon pair cross-fades, which keeps focus changes free of canvas repaints.
    Repeater {
        model: glassRow.iconPng !== "" && !glassRow.iconBusy ? ["", "-dark"] : []
        Image {
            x: glassRow.iconOnly ? (glassRow.width - glassRow.iconSize) / 2 : 20 * glassRow.unit
            y: (glassRow.height - glassRow.iconSize) / 2
            opacity: ((index === 1) === glassRow.focused ? 1 : 0) * (glassRow.disabled ? GlassStyle.disabledOpacity : 1)
            source: Qt.resolvedUrl("icons/row-" + glassRow.iconPng + modelData + ".png")
            Behavior on opacity { NumberAnimation { duration: glassRow.colorDuration } }
        }
    }

    ProfileAvatar {
        x: 20 * glassRow.unit
        y: (glassRow.height - height) / 2
        visible: glassRow.hasAvatar
        unit: glassRow.unit
        size: glassRow.avatarSize
        initial: glassRow.hasAvatar ? glassRow.avatar.initial : ""
        tint: glassRow.hasAvatar ? glassRow.avatar.tint : GlassStyle.profileColors[0]
    }

    Text {
        x: glassRow.leftInset * glassRow.unit
        y: glassRow.titleTop * glassRow.unit
        width: glassRow.width - (glassRow.leftInset + glassRow.rightReserve) * glassRow.unit
        height: glassRow.titleHeight * glassRow.unit
        visible: !glassRow.iconOnly
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: glassRow.title
        opacity: glassRow.disabled ? GlassStyle.disabledOpacity : 1
        color: glassRow.danger ? (glassRow.focused ? GlassStyle.dangerFocused : GlassStyle.danger) : glassRow.mainColor
        font.family: glassRow.titleFont
        font.pixelSize: glassRow.titleSize * glassRow.unit
        font.hintingPreference: Font.PreferNoHinting
        Behavior on color { ColorAnimation { duration: glassRow.colorDuration } }
    }

    Text {
        x: glassRow.leftInset * glassRow.unit
        y: (glassRow.titleTop + 28) * glassRow.unit
        width: glassRow.width - (glassRow.leftInset + glassRow.rightReserve) * glassRow.unit
        height: 21 * glassRow.unit
        visible: glassRow.twoLines && !glassRow.iconOnly
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: glassRow.subtitle
        color: glassRow.tone === "warning" ? (glassRow.focused ? GlassStyle.warningFocused : GlassStyle.warning) :
               (glassRow.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail)
        font.family: glassRow.valueFont
        font.pixelSize: glassRow.subtitleSize * glassRow.unit
        font.hintingPreference: Font.PreferNoHinting
        Behavior on color { ColorAnimation { duration: glassRow.colorDuration } }
    }

    // Value at the right, before the mark: in the middle of the whole row, also under a
    // second line. A slider keeps it level with its title.
    Text {
        id: valueText
        anchors.right: parent.right
        anchors.rightMargin: (glassRow.slider ? 20 : glassRow.markSpace) * glassRow.unit
        y: (glassRow.slider ? glassRow.titleTop : 0) * glassRow.unit
        width: Math.min(implicitWidth, glassRow.width * 0.5)
        height: (glassRow.slider ? glassRow.titleHeight : glassRow.logicalHeight) * glassRow.unit
        visible: !glassRow.iconOnly && !glassRow.hasToggle && glassRow.value !== ""
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: glassRow.value
        opacity: glassRow.disabled ? GlassStyle.disabledOpacity : 1
        color: glassRow.sideColor
        font.family: glassRow.valueFont
        font.pixelSize: 18 * glassRow.unit
        font.hintingPreference: Font.PreferNoHinting
        Behavior on color { ColorAnimation { duration: glassRow.colorDuration } }
    }

    // Chevron, ↗ or choice tick, 18 px, in the middle of the row.
    Repeater {
        model: !glassRow.busy && (glassRow.mark === "chevron" || glassRow.mark === "down" ||
                                  glassRow.mark === "external" || glassRow.mark === "choice") ? ["", "-dark"] : []
        Image {
            anchors.right: parent.right
            anchors.rightMargin: 20 * glassRow.unit
            y: (glassRow.height - 18 * glassRow.unit) / 2
            width: 18 * glassRow.unit
            height: width
            opacity: ((index === 1) === glassRow.focused ? 1 : 0) * (glassRow.disabled ? GlassStyle.disabledOpacity : 1)
            // "down": the chevron turned, a choice that opens below its row.
            rotation: glassRow.mark === "down" ? 90 : 0
            source: Qt.resolvedUrl("icons/" + (glassRow.mark === "down" ? "chevron" : glassRow.mark) + "-18" +
                                   modelData + ".png")
            Behavior on opacity { NumberAnimation { duration: glassRow.colorDuration } }
        }
    }

    // Check of the active value in a selection page: the surface shows only the focus.
    Repeater {
        model: glassRow.mark === "check" ? ["", "-dark"] : []
        Image {
            anchors.right: parent.right
            anchors.rightMargin: 17 * glassRow.unit
            anchors.verticalCenter: parent.verticalCenter
            width: 24 * glassRow.unit
            height: width
            opacity: (index === 1) === glassRow.focused ? 1 : 0
            source: Qt.resolvedUrl("icons/check-24" + modelData + ".png")
            Behavior on opacity { NumberAnimation { duration: glassRow.colorDuration } }
        }
    }

    Spinner {
        anchors.right: parent.right
        anchors.rightMargin: 20 * glassRow.unit
        anchors.verticalCenter: parent.verticalCenter
        visible: glassRow.busy
        size: 26 * glassRow.unit
        lineWidth: 3 * glassRow.unit
        dark: glassRow.focused
        running: visible
    }

    Spinner {
        x: 22 * glassRow.unit
        anchors.verticalCenter: parent.verticalCenter
        visible: glassRow.iconBusy
        size: 26 * glassRow.unit
        lineWidth: 3 * glassRow.unit
        dark: glassRow.focused
        running: visible
    }

    // Switch, 64 × 36 with a 28 px knob. Off keeps its grey on the white focus surface,
    // where the white knob would vanish on a lighter tone.
    GlassSwitch {
        anchors.right: parent.right
        anchors.rightMargin: 20 * glassRow.unit
        anchors.verticalCenter: parent.verticalCenter
        visible: glassRow.hasToggle
        unit: glassRow.unit
        on: glassRow.toggle === true
        disabled: glassRow.disabled
    }

    // Slider track under the title, at 74 px as in the panel's 104 px slider rows. A second
    // line under the title ends just above it.
    GlassSlider {
        readonly property real inset: glassRow.hasEnds ? 20 + 40 + 14 : 20
        x: inset * glassRow.unit
        y: glassRow.sliderY * glassRow.unit
        width: glassRow.width - 2 * inset * glassRow.unit
        visible: glassRow.slider
        unit: glassRow.unit
        share: glassRow.sliderShare
        origin: Math.max(0, glassRow.sliderOrigin)
        zeroLine: glassRow.sliderOrigin >= 0
        knob: glassRow.sliderOrigin >= 0
        focused: glassRow.focused
        disabled: glassRow.disabled
    }

    // The end circles, 40 px, centred on the track.
    Repeater {
        model: glassRow.slider && glassRow.hasEnds ? glassRow.sliderEnds : []
        Rectangle {
            x: index === 0 ? 20 * glassRow.unit : glassRow.width - (20 + 40) * glassRow.unit
            y: (glassRow.sliderY + 3 - 20) * glassRow.unit
            width: 40 * glassRow.unit
            height: width
            radius: width / 2
            opacity: glassRow.disabled ? GlassStyle.disabledOpacity : 1
            color: glassRow.focused ? GlassStyle.endCapFocused : GlassStyle.endCapFill
            Behavior on color { ColorAnimation { duration: glassRow.colorDuration } }

            Text {
                anchors.centerIn: parent
                text: modelData
                color: glassRow.mainColor
                font.family: glassRow.titleFont
                font.pixelSize: GlassStyle.endCapSize * glassRow.unit
                font.hintingPreference: Font.PreferNoHinting
                Behavior on color { ColorAnimation { duration: glassRow.colorDuration } }
            }
        }
    }
}
