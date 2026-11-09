import QtQuick 2.12
import "."

// Glass surface for modals. Same material as the panel, sampled from the backdrop
// crop around the screen centre. Width and height glide between the steps of a
// flow, which only moves two uniforms and costs no new textures.
Item {
    id: card

    property real unit: 1
    property variant backdrop
    property string glassShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)    // on the screen, without margin
    property real hasBackdrop: 0
    property int glideDuration: 240
    property bool glides: true          // false: width and height follow without motion
    property var glideCurve: GlassStyle.curve
    property string shadow: "shadow-modal"
    property real cornerRadius: 48 * unit

    default property alias content: contentLayer.data

    Behavior on width {
        enabled: card.glides
        NumberAnimation {
            duration: card.glideDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: card.glideCurve
        }
    }
    Behavior on height {
        enabled: card.glides
        NumberAnimation {
            duration: card.glideDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: card.glideCurve
        }
    }

    // Soft outer shadow, as a nine-patch for the GPU's sake.
    BorderImage {
        x: -180 * card.unit
        y: -180 * card.unit
        width: card.width + 360 * card.unit
        height: card.height + 360 * card.unit
        visible: card.shadow !== ""
        source: card.shadow === "" ? "" : Qt.resolvedUrl("icons/" + card.shadow + ".png")
        border.left: 240
        border.right: 240
        border.top: 240
        border.bottom: 240
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        property variant backdrop: card.backdrop
        property size panelSize: Qt.size(width, height)
        property real cornerRadius: card.cornerRadius
        property real topLightWidth: 1.5 * card.unit
        property real contourWidth: 1.25 * card.unit
        property real glowHeight: 16 * card.unit
        property real backdropMargin: card.backdropMargin
        property point backdropOrigin: Qt.point(card.x - card.backdropArea.x, card.y - card.backdropArea.y)
        property size backdropArea: Qt.size(card.backdropArea.width, card.backdropArea.height)
        property real dim: 0
        property real hasBackdrop: card.hasBackdrop
        property real edgeGain: GlassStyle.edgeGain
        vertexShader: GlassStyle.glassVertexShader
        fragmentShader: card.glassShader
    }

    Item {
        id: contentLayer
        anchors.fill: parent
    }
}
