import QtQuick 2.12
import "."
import "ShutdownScreens.js" as ShutdownScreens

// The picture on a tile of Oberfläche › Ausschalt-Video (K3-Ausschalt-2): what the entry
// shows in the middle of its run, small, with rounded corners.
Item {
    id: thumb

    property real unit: 1
    property string screenId: ""
    readonly property var entry: ShutdownScreens.entry(screenId)

    // The boot look: light and wordmark, larger than on the screen so that it reads.
    BootGlow {
        anchors.fill: parent
        visible: thumb.entry.kind === "glow"
        radius: 20 * thumb.unit
        spread: 1780
        strength: 1.15
    }

    Wordmark {
        anchors.centerIn: parent
        visible: thumb.entry.kind === "glow"
        unit: thumb.unit
        size: 30
        opacity: 0.6
    }

    // LG's logo on black, from LG's own folder.
    Rectangle {
        anchors.fill: parent
        visible: thumb.entry.kind === "lg"
        radius: 20 * thumb.unit
        color: "#000000"

        Image {
            anchors.centerIn: parent
            width: 120 * thumb.unit
            height: width
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: parent.visible ? "file:///usr/lib/qml/MasterBrand/LG_logo_2k.png" : ""
        }
    }
}
