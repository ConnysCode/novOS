import QtQuick 2.12
import "."

// A large choice card: a drawing at the top (the default content), title and second
// line at the bottom. selected draws a white ring and a check badge; focused turns the
// card into the white focus surface at 103 %.
Item {
    id: card

    property real unit: 1
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    property bool focused: false
    default property alias content: drawing.data

    scale: focused ? GlassStyle.focusScale : 1

    Behavior on scale {
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }

    SoftShadow {
        visible: card.focused
        anchors.centerIn: parent
        unit: card.unit
        radius: 30
    }

    Rectangle {
        anchors.fill: parent
        radius: 30 * card.unit
        color: card.focused ? GlassStyle.focusFill : (card.selected ? "#29ffffff" : "#0fffffff")
        border.width: card.selected && !card.focused ? 2 * card.unit : 0
        border.color: "#8cffffff"
        antialiasing: true
    }

    Item {
        id: drawing
        x: 28 * card.unit
        y: 28 * card.unit
        width: parent.width - 56 * card.unit
        height: parent.height - 56 * card.unit
    }

    Rectangle {
        visible: card.selected
        x: parent.width - width - 24 * card.unit
        y: 24 * card.unit
        width: 36 * card.unit
        height: 36 * card.unit
        radius: width / 2
        color: card.focused ? GlassStyle.focusText : "#ffffff"

        Image {
            anchors.centerIn: parent
            width: 20 * card.unit
            height: 20 * card.unit
            source: Qt.resolvedUrl(card.focused ? "icons/check-20.png" : "icons/check-20-dark.png")
        }
    }

    Text {
        id: titleText
        x: 28 * card.unit
        y: subtitleText.y - 4 * card.unit - height
        text: card.title
        color: card.focused ? GlassStyle.focusText : GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: 26 * card.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Text {
        id: subtitleText
        x: 28 * card.unit
        y: card.height - 28 * card.unit - height
        text: card.subtitle
        color: card.focused ? GlassStyle.focusSecondary : "#c2ffffff"
        font.family: GlassStyle.valueFont
        font.pixelSize: 19 * card.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
