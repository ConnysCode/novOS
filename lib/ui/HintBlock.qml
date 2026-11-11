import QtQuick 2.12
import "."

// The empty and hint state of a list, centred: a spinner while it searches, otherwise a
// symbol in a circle, below a line and a hint. The Wi-Fi list (searching, nothing found,
// not available) and the device lists of the settings (K3-Einst-Geraeteliste: "Keine Geräte
// gefunden") share it. The owner places the block and gives its width; the height follows
// the content.
Column {
    id: block

    property real unit: 1
    property string titleFont: GlassStyle.rowFont
    property string valueFont: GlassStyle.valueFont
    property bool spinner: false          // a search runs: the turning ring instead of the circle
    property bool running: true
    property string icon: ""              // icons/<name>.png inside the circle
    property real circleSize: 72          // 72 in the Wi-Fi list, 64 in the device lists
    property real spinnerSize: 44
    property string title: ""
    property string text: ""
    property real textWidth: 520
    property real titleGap: 20

    spacing: 0

    Item {
        width: parent.width
        height: (block.spinner ? block.spinnerSize : block.circleSize) * block.unit

        Spinner {
            anchors.centerIn: parent
            size: block.spinnerSize * block.unit
            lineWidth: 4 * block.unit
            running: block.spinner && block.running && block.visible
            visible: block.spinner
        }

        GlassControl {
            anchors.centerIn: parent
            visible: !block.spinner
            width: block.circleSize * block.unit
            height: width
            unit: block.unit
            radius: block.circleSize / 2
            fill: GlassStyle.hintCircle

            Image {
                anchors.centerIn: parent
                visible: block.icon !== ""
                source: block.icon !== "" ? Qt.resolvedUrl("icons/" + block.icon + ".png") : ""
            }
        }
    }

    Item { width: 1; height: block.titleGap * block.unit }

    Text {
        width: parent.width
        height: 30 * block.unit
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: block.title
        color: GlassStyle.textPrimary
        font.family: block.titleFont
        font.pixelSize: GlassStyle.hintTitleSize * block.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Item { width: 1; height: 6 * block.unit; visible: block.text !== "" }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: block.textWidth * block.unit
        visible: block.text !== ""
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        lineHeight: 1.4
        text: block.text
        color: GlassStyle.textSecondary
        font.family: block.valueFont
        font.pixelSize: GlassStyle.valueSize * block.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
