import QtQuick 2.12

// Pill button of the content modals, 64 px high. Sized by its label.
// The owner usually draws the focus surface behind a focused button; ownFocus lets the
// button draw its own white plate at 103 %, for screens without a moving focus.
// danger colours the label (red on glass, darker red on white), disabled dims to 40 %.
Item {
    id: button

    property real unit: 1
    property string fontFamily: ""
    property string label: ""
    property string icon: ""
    property bool focused: false
    property bool ownFocus: false
    property bool danger: false
    property bool disabled: false
    signal clicked()

    width: content.width + 56 * unit
    height: 64 * unit
    opacity: disabled ? GlassStyle.dimmedOpacity : 1
    scale: ownFocus && focused ? GlassStyle.focusScale : 1

    FocusSurface {
        anchors.fill: parent
        visible: button.ownFocus && button.focused
        unit: button.unit
        radius: 32
        animated: false
    }

    GlassControl {
        anchors.fill: parent
        visible: !button.focused
        unit: button.unit
        radius: 32
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 10 * button.unit

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.icon !== ""
            source: button.icon === "" ? "" :
                    Qt.resolvedUrl("icons/" + button.icon + (button.focused ? "-dark.png" : ".png"))
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.label
            color: button.danger ? (button.focused ? GlassStyle.dangerFocused : GlassStyle.danger)
                                 : (button.focused ? GlassStyle.focusText : "#ffffff")
            font.family: button.fontFamily
            font.pixelSize: 20 * button.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
