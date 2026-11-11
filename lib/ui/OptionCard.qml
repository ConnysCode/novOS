import QtQuick 2.12
import "."

// A large choice card: a drawing at the top (the default content), title and second
// line at the bottom. selected draws a white ring and a check badge; focused turns the
// card into the white focus surface at 103 %. With ownFocus false the card draws no white
// of its own and is a focus target for its owner's single gliding surface.
// media: a tile as in K3-Ausschalt-2: the drawing is a framed picture of mediaHeight at
// the top with the check badge in its corner, title and second line below it, and no
// plate of its own until it has the focus.
Item {
    id: card

    property real unit: 1
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    property bool focused: false
    property bool ownFocus: true
    property bool media: false
    property real mediaHeight: 203
    readonly property real inset: media ? 8 : 28
    readonly property bool focusTarget: !ownFocus
    readonly property real plateRadius: media ? 28 : 30
    readonly property real plateScale: GlassStyle.focusScale
    default property alias content: drawing.data

    scale: focused ? GlassStyle.focusScale : 1

    Behavior on scale {
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }

    SoftShadow {
        visible: card.focused && card.ownFocus
        anchors.centerIn: parent
        unit: card.unit
        radius: 30
    }

    Rectangle {
        anchors.fill: parent
        radius: card.plateRadius * card.unit
        color: card.focused ? (card.ownFocus ? GlassStyle.focusFill : "#00ffffff")
                            : (card.media ? "#00ffffff" : (card.selected ? GlassStyle.fillActive : GlassStyle.fillGhost))
        // Its own focus carries the ring; a chosen card keeps its light ring below.
        FocusRing {
            anchors.fill: parent
            unit: card.unit
            radius: parent.radius
            shown: card.ownFocus && card.focused
        }

        Behavior on color {
            enabled: !card.ownFocus
            ColorAnimation { duration: GlassStyle.focusDuration }
        }
        border.width: card.selected && !card.focused && !card.media ? 2 * card.unit : 0
        border.color: GlassStyle.optionRing
        antialiasing: true
    }

    Item {
        id: drawing
        x: card.inset * card.unit
        y: card.inset * card.unit
        width: parent.width - 2 * card.inset * card.unit
        height: card.media ? card.mediaHeight * card.unit : parent.height - 2 * card.inset * card.unit
    }

    // The thin frame of a media tile's picture.
    Rectangle {
        visible: card.media
        x: drawing.x
        y: drawing.y
        width: drawing.width
        height: drawing.height
        radius: 20 * card.unit
        color: "#00ffffff"
        border.width: Math.max(1, card.unit)
        border.color: GlassStyle.lineSoft
        antialiasing: true
    }

    Rectangle {
        visible: card.selected
        x: parent.width - width - (card.media ? 20 : 24) * card.unit
        y: (card.media ? 20 : 24) * card.unit
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
        x: (card.media ? 18 : 28) * card.unit
        y: card.media ? drawing.y + drawing.height + 12 * card.unit
                      : subtitleText.y - 4 * card.unit - height
        width: card.media ? parent.width - 2 * x : implicitWidth
        elide: Text.ElideRight
        text: card.title
        color: card.focused ? GlassStyle.focusText : GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: (card.media ? 21 : 26) * card.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Text {
        id: subtitleText
        x: (card.media ? 18 : 28) * card.unit
        y: card.media ? titleText.y + titleText.height + 2 * card.unit
                      : card.height - 28 * card.unit - height
        width: card.media ? parent.width - 2 * x : implicitWidth
        elide: Text.ElideRight
        text: card.subtitle
        color: card.focused ? GlassStyle.focusSecondary : (card.media ? GlassStyle.textCaptionMedia : GlassStyle.textCaption)
        font.family: GlassStyle.valueFont
        font.pixelSize: (card.media ? 17 : 19) * card.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
