import QtQuick 2.12
import "."

// Card with the state of a longer task, at the top of a page (K3-NovUpdate-2 … 8): a symbol
// in a 64 px circle, a title, a line below, optionally a progress bar with a text at each
// end, and a row of buttons. The card is one entry of a list; Left and Right move between
// its buttons, and the focused button draws its own white plate (the list's surface stays
// away from the card).
//
//   icon     "check" (accent circle), "download", "history", "alert" (red), "spinner"
//   progress 0 … 1, or -1 for none
//   buttons  [{ label, disabled, danger }]
Item {
    id: card

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property string icon: "check"
    property string title: ""
    property string text: ""
    property real progress: -1
    property string progressText: ""
    property string progressValue: ""
    property var buttons: []
    property int focusIndex: -1         // the focused button, -1 when the card has no focus
    signal buttonClicked(int index)

    readonly property real padX: 28
    readonly property real padY: 26
    readonly property real indent: 88   // the circle and its gap: bar and buttons start below the title

    GlassControl {
        anchors.fill: parent
        unit: card.unit
        radius: 30
        fill: GlassStyle.cardFill
    }

    Rectangle {
        id: circle
        x: card.padX * card.unit
        y: card.padY * card.unit
        width: 64 * card.unit
        height: width
        radius: width / 2
        color: card.icon === "check" ? GlassStyle.accent :
               card.icon === "alert" ? GlassStyle.dangerCircle : GlassStyle.circleFill

        Image {
            anchors.centerIn: parent
            width: 32 * card.unit
            height: width
            visible: card.icon !== "spinner"
            smooth: true
            source: card.icon === "spinner" ? "" : Qt.resolvedUrl("icons/status-" + card.icon + "-32.png")
        }

        Spinner {
            anchors.centerIn: parent
            visible: card.icon === "spinner"
            running: visible
            size: 30 * card.unit
            lineWidth: 3 * card.unit
        }
    }

    Column {
        x: circle.x + (64 + 24) * card.unit
        width: card.width - x - card.padX * card.unit
        anchors.verticalCenter: circle.verticalCenter
        spacing: 4 * card.unit

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: card.title
            color: GlassStyle.textPrimary
            font.family: card.titleFont
            font.pixelSize: 28 * card.unit
            font.letterSpacing: -0.28 * card.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            text: card.text
            color: GlassStyle.textSecondary
            font.family: card.valueFont
            font.pixelSize: 19 * card.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    Item {
        id: progressBlock
        x: (card.padX + card.indent) * card.unit
        y: circle.y + circle.height + 18 * card.unit
        width: card.width - x - card.padX * card.unit
        height: (10 + 10 + 24) * card.unit
        visible: card.progress >= 0

        ProgressBar {
            width: parent.width
            unit: card.unit
            barHeight: 10
            value: Math.max(0, card.progress)
        }

        Text {
            y: 20 * card.unit
            text: card.progressText
            color: GlassStyle.textSecondary
            font.family: card.valueFont
            font.pixelSize: 18 * card.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            y: 20 * card.unit
            anchors.right: parent.right
            text: card.progressValue
            color: GlassStyle.textPrimary
            font.family: card.titleFont
            font.pixelSize: 18 * card.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    Row {
        x: (card.padX + card.indent) * card.unit
        y: (progressBlock.visible ? progressBlock.y + progressBlock.height : circle.y + circle.height) + 22 * card.unit
        spacing: 12 * card.unit
        visible: card.buttons.length > 0

        Repeater {
            model: card.buttons
            FooterButton {
                unit: card.unit
                size: 60
                fontFamily: card.rowFont
                label: modelData.label || ""
                disabled: modelData.disabled === true
                danger: modelData.danger === true
                ownFocus: true
                focused: card.focusIndex === index
                onClicked: card.buttonClicked(index)
            }
        }
    }
}
