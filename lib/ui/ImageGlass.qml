import QtQuick 2.12
import QtGraphicalEffects 1.12
import "."

// The glass colour for surfaces over a picture rather than video: the part of the
// picture behind the glass, blurred and graded on a tiny image, as in LiveBackdrop.
Item {
    id: glass

    property Item sourceItem
    property real unit: 1
    property rect area: Qt.rect(0, 0, 0, 0)
    property real margin: 56 * unit
    // A uniform dark layer between sourceItem and the glass, see GlassStyle.gradeShader.
    // Scrims that vary across the screen belong into sourceItem instead.
    property real veil: 0

    readonly property variant texture: graded
    readonly property rect crop: Qt.rect(area.x - margin, area.y - margin,
                                         area.width + 2 * margin, area.height + 2 * margin)
    readonly property int downscale: 8

    width: Math.ceil(crop.width / downscale)
    height: Math.ceil(crop.height / downscale)

    ShaderEffectSource {
        id: cropped
        anchors.fill: parent
        visible: false
        sourceItem: glass.sourceItem
        sourceRect: glass.crop
        textureSize: Qt.size(width, height)
        live: true
        hideSource: true
        smooth: true
    }

    GaussianBlur {
        id: blurred
        anchors.fill: parent
        visible: false
        source: cropped
        deviation: GlassStyle.blur * glass.unit / glass.downscale
        radius: Math.ceil(deviation * 2.6)
        samples: 2 * radius + 1
        transparentBorder: false
        cached: false
    }

    ShaderEffectSource {
        id: blurredTexture
        anchors.fill: parent
        visible: false
        sourceItem: blurred
        textureSize: Qt.size(width, height)
        live: true
    }

    ShaderEffect {
        id: grade
        anchors.fill: parent
        visible: false
        property variant source: blurredTexture
        property real veil: glass.veil
        fragmentShader: GlassStyle.gradeShader
    }

    ShaderEffectSource {
        id: graded
        anchors.fill: parent
        visible: false
        sourceItem: grade
        textureSize: Qt.size(width, height)
        live: true
        smooth: true
    }
}
