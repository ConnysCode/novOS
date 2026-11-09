import QtQuick 2.12
import QtGraphicalEffects 1.0
import "."
import "ShutdownScreens.js" as ShutdownScreens

// The picture on a tile of Oberfläche › Ausschalt-Video (K3-Ausschalt-2 and -7): what the
// entry shows in the middle of its run, small, with rounded corners. item is the entry of
// the host list "shutdownScreens" (SettingsData): kind, and for own entries the entry of
// ShutdownScreens.js (frames, framing).
//   "add"   the last tile, "Video hinzufügen": a ring with a plus
Item {
    id: thumb

    property real unit: 1
    property var item: ({})
    property bool focused: false
    readonly property string kind: item && item.kind ? item.kind : ""
    readonly property var entry: item && item.entry ? item.entry : ({})

    // The boot look: light and wordmark, larger than on the screen so that it reads.
    BootGlow {
        anchors.fill: parent
        visible: thumb.kind === "glow"
        radius: 20 * thumb.unit
        spread: 1780
        strength: 1.15
    }

    Wordmark {
        anchors.centerIn: parent
        visible: thumb.kind === "glow"
        unit: thumb.unit
        size: 30
        opacity: 0.6
    }

    // LG's logo, and own pictures and videos, on black.
    Rectangle {
        id: plate
        anchors.fill: parent
        visible: thumb.kind === "lg" || thumb.kind === "video" || thumb.kind === "image"
        radius: 20 * thumb.unit
        color: "#000000"

        Image {
            anchors.centerIn: parent
            visible: thumb.kind === "lg"
            width: 120 * thumb.unit
            height: width
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: visible ? "file:///usr/lib/qml/MasterBrand/LG_logo_2k.png" : ""
        }

        // The first frame of the part that plays, or the picture, framed as on the screen.
        ShutdownFraming {
            id: framed
            anchors.fill: parent
            visible: false
            zoom: thumb.entry.zoom || 1
            panX: thumb.entry.x || 0
            panY: thumb.entry.y || 0
            mediaWidth: picture.implicitWidth || 16
            mediaHeight: picture.implicitHeight || 9

            Image {
                id: picture
                anchors.fill: parent
                sourceSize: Qt.size(640, 640)
                asynchronous: true
                cache: false
                source: thumb.kind === "image" || thumb.kind === "video" ?
                        ShutdownScreens.frameUrl(thumb.entry, ShutdownScreens.frameAt(thumb.entry, thumb.entry.start || 0)) : ""
            }
        }

        Rectangle {
            id: corners
            anchors.fill: parent
            radius: plate.radius
            visible: false
        }

        OpacityMask {
            anchors.fill: parent
            visible: picture.status === Image.Ready
            source: framed
            maskSource: corners
        }
    }

    // "Video hinzufügen": a ring and a plus, dark on the focus surface.
    Rectangle {
        anchors.fill: parent
        visible: thumb.kind === "add"
        radius: 20 * thumb.unit
        color: "#00ffffff"
        border.width: 2 * thumb.unit
        border.color: thumb.focused ? "#400b0c10" : "#47ffffff"

        Image {
            anchors.centerIn: parent
            width: 40 * thumb.unit
            height: width
            source: Qt.resolvedUrl(thumb.focused ? "icons/plus-28-dark.png" : "icons/plus-28.png")
        }
    }
}
