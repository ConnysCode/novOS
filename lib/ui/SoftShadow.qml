import QtQuick 2.12
import "."

// Soft outer shadow of a rounded box, as CSS draws "0 <drop> <2·softness> rgba(0,0,0,<strength>)".
// Place it as a child of the box it belongs to; it spills out by pad on every side. The
// focus surface, popovers, the notice bar and the picker's cards all use this one shader.
// Inputs are logical px; the shader's own uniforms below follow from them.
ShaderEffect {
    id: shadow

    property real unit: 1
    property real boxWidth: parent ? parent.width : 0      // in px, usually the parent's size
    property real boxHeight: parent ? parent.height : 0
    property real radius: 26
    property real softness: 16
    property real drop: 14
    property real strength: 0.30
    property real pad: 60

    x: -pad * unit
    y: -pad * unit
    width: boxWidth + 2 * pad * unit
    height: boxHeight + 2 * pad * unit

    property size itemSize: Qt.size(width, height)
    property size boxSize: Qt.size(boxWidth, boxHeight)
    property real boxRadius: radius * unit
    property real sigma: softness * unit
    property real offsetY: drop * unit
    property color shadowColor: "#000000"

    fragmentShader: GlassStyle.shadowShader
}
