import QtQuick 2.12
import "."

// Fill and edge light of a small glass control. Every control carries the same top
// light and contour as the panel, sized to its own radius.
Item {
    id: control

    property real unit: 1
    property int radius: 26
    property color fill: GlassStyle.fillControl
    property string edge: "edge-" + radius

    Rectangle {
        anchors.fill: parent
        radius: control.radius * control.unit
        color: control.fill
        antialiasing: true
    }

    BorderImage {
        anchors.fill: parent
        opacity: Math.min(1, GlassStyle.edgeGain)
        source: Qt.resolvedUrl("icons/" + control.edge + ".png")
        border.left: control.radius + 1
        border.right: control.radius + 1
        border.top: control.radius + 1
        border.bottom: control.radius + 1
    }

    // A second pass carries the edge light beyond the strength of the texture.
    BorderImage {
        anchors.fill: parent
        opacity: Math.min(1, GlassStyle.edgeGain - 1)
        visible: opacity > 0
        source: Qt.resolvedUrl("icons/" + control.edge + ".png")
        border.left: control.radius + 1
        border.right: control.radius + 1
        border.top: control.radius + 1
        border.bottom: control.radius + 1
    }
}
