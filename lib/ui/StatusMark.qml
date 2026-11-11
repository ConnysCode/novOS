import QtQuick 2.12
import "."

// The state of one step in a check or progress list, 32 px:
//   status "done"     blue disc with a white tick
//   "running"  turning ring with a bright quarter
//   "pending"  thin ring
//   "error"    red disc with "!"
//   "reset"    grey disc with a turning-back arrow
Item {
    id: mark

    property real unit: 1
    property string status: "pending"

    width: 32 * unit
    height: 32 * unit

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: mark.status !== "running"
        color: mark.status === "done" ? GlassStyle.accent :
               mark.status === "error" ? GlassStyle.dangerFocused :
               mark.status === "reset" ? GlassStyle.fillActiveStrong : "transparent"
        border.width: mark.status === "pending" ? 2 * mark.unit : 0
        border.color: GlassStyle.lineMark
    }

    Image {
        anchors.centerIn: parent
        visible: mark.status === "done" || mark.status === "reset"
        width: 18 * mark.unit
        height: 18 * mark.unit
        source: Qt.resolvedUrl(mark.status === "reset" ? "icons/refresh-18.png" : "icons/check-18.png")
    }

    Text {
        anchors.centerIn: parent
        visible: mark.status === "error"
        text: "!"
        color: GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: 20 * mark.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Spinner {
        anchors.fill: parent
        visible: mark.status === "running"
        size: 32 * mark.unit
        lineWidth: 3 * mark.unit
        running: visible
    }
}
