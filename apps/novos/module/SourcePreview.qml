import QtQuick 2.12
import "."

// Last picture of the source that has the focus, above its tile. The TV decodes only
// one HDMI input at a time, so this is a still from the last visit, never live video.
// One image per tile stays loaded, which makes moving the focus instant.
Item {
    id: preview

    property real unit: 1
    property string shadowShader: ""
    property var paths: []                  // one entry per tile, "" for no picture
    property int tiles: 0
    property int index: -1
    property bool wanted: false
    property int glideDuration: 220
    property var glideCurve: GlassStyle.curve

    property int shownIndex: -1
    property bool available: false
    readonly property bool shown: wanted && available

    width: 384 * unit
    height: 216 * unit
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 180 }
    }
    Behavior on x {
        enabled: preview.visible
        NumberAnimation {
            duration: preview.glideDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: preview.glideCurve
        }
    }

    // The last picture stays in place while the box fades out.
    function refresh() {
        var tile = stills.itemAt(index);
        available = !!tile && tile.ready;
        if (available) shownIndex = index;
    }

    onIndexChanged: refresh()

    SoftShadow {
        unit: preview.unit
        boxWidth: preview.width
        boxHeight: preview.height
        radius: 24
        softness: 20
        drop: 16
        strength: 0.45
        pad: 70
    }

    Repeater {
        id: stills
        model: preview.tiles

        Item {
            readonly property bool ready: picture.status === Image.Ready
            anchors.fill: parent
            onReadyChanged: preview.refresh()

            Image {
                id: picture
                visible: false
                asynchronous: true
                cache: false
                smooth: true
                source: preview.paths[index] ? "file://" + preview.paths[index] : ""
            }

            // Picture, rounded corners and edge light in one pass.
            ShaderEffect {
                anchors.fill: parent
                visible: index === preview.shownIndex
                property variant source: picture
                property rect sourceRect: Qt.rect(0, 0, 1, 1)
                property size boxSize: Qt.size(width, height)
                property real cornerRadius: 24 * preview.unit
                property real topLightWidth: 1.5 * preview.unit
                property real contourWidth: 1.25 * preview.unit
                property real edgeGain: GlassStyle.edgeGain
                fragmentShader: GlassStyle.pictureShader
            }
        }
    }
}
