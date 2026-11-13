import QtQuick 2.12

// Pill button of the content modals, 64 px high (size: 60 in a StatusCard). Sized by its label.
// The owner usually draws the focus surface behind a focused button; ownFocus lets the
// button draw its own white plate at 103 %, for screens without a moving focus.
// danger colours the label (red on glass, darker red on white), disabled dims to 40 %.
// Over a picture rather than over a glass card, the button is a glass pill of its own: give
// glassShader and the backdrop of an ImageGlass or LiveBackdrop (as NoticeBar takes them).
// It fades like the plain fill, so the owner's surface still glides beneath it.
Item {
    id: button

    property real unit: 1
    property string fontFamily: ""
    property string label: ""
    property string icon: ""
    property bool focused: false
    property bool ownFocus: false
    // A focus target for an owner's single gliding surface (see apps/setup WizardDialog).
    readonly property bool focusTarget: !ownFocus && !disabled
    property real size: 64
    readonly property real plateRadius: size / 2
    readonly property real plateScale: GlassStyle.focusScale
    property bool danger: false
    property bool disabled: false
    property real textSize: GlassStyle.pillTextSize
    property real sidePadding: 28            // logical px left and right of the label
    property string glassShader: ""
    property variant backdrop
    property real backdropMargin: 0
    property rect backdropArea: Qt.rect(0, 0, 0, 0)    // around this button's parent, as GlassCard
    property real hasBackdrop: 0
    readonly property bool glass: glassShader !== ""
    signal clicked()

    width: content.width + 2 * sidePadding * unit
    height: size * unit
    opacity: disabled ? GlassStyle.dimmedOpacity : 1
    scale: ownFocus && focused ? GlassStyle.focusScale : 1

    FocusSurface {
        anchors.fill: parent
        visible: button.ownFocus && button.focused
        unit: button.unit
        radius: button.plateRadius
        animated: false
    }

    // Fades as the owner's surface arrives, instead of leaving a gap until it is there.
    GlassControl {
        anchors.fill: parent
        opacity: button.focused ? 0 : 1
        visible: !button.glass && opacity > 0
        unit: button.unit
        radius: button.plateRadius

        Behavior on opacity {
            NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
        }
    }

    // The glass variant: it samples the picture behind it, in the parent's frame.
    GlassCard {
        anchors.fill: parent
        opacity: button.focused ? 0 : 1
        visible: button.glass && opacity > 0
        unit: button.unit
        cornerRadius: button.plateRadius * button.unit
        backdrop: button.backdrop
        glassShader: button.glassShader
        backdropMargin: button.backdropMargin
        backdropArea: Qt.rect(button.backdropArea.x - button.x, button.backdropArea.y - button.y,
                              button.backdropArea.width, button.backdropArea.height)
        hasBackdrop: button.hasBackdrop
        shadow: ""

        Behavior on opacity {
            NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
        }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 10 * button.unit

        Item {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.icon !== ""
            width: lightIcon.width
            height: lightIcon.height

            Image {
                id: lightIcon
                source: button.icon === "" ? "" : Qt.resolvedUrl("icons/" + button.icon + ".png")
                opacity: button.focused ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
            }
            Image {
                source: button.icon === "" ? "" : Qt.resolvedUrl("icons/" + button.icon + "-dark.png")
                opacity: button.focused ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.label
            color: button.danger ? (button.focused ? GlassStyle.dangerFocused : GlassStyle.danger)
                                 : (button.focused ? GlassStyle.focusText : "#ffffff")
            font.family: button.fontFamily
            font.pixelSize: button.textSize * button.unit
            font.hintingPreference: Font.PreferNoHinting
            Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
