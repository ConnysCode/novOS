import QtQuick 2.12
import "."

// The switch of novOS: 64 × 36 with a 28 px white knob, blue when on. Off keeps its grey
// also on the white focus surface, where a lighter tone would hide the knob. The owner
// places it; its size is fixed by the design.
Rectangle {
    id: glassSwitch

    property real unit: 1
    property bool on: false
    property bool disabled: false

    width: 64 * unit
    height: 36 * unit
    radius: 18 * unit
    opacity: disabled ? GlassStyle.disabledOpacity : 1
    color: on ? GlassStyle.accent : GlassStyle.switchOff

    Behavior on color {
        ColorAnimation { duration: GlassStyle.colorDuration }
    }

    Rectangle {
        x: (glassSwitch.on ? 32 : 4) * glassSwitch.unit
        y: 4 * glassSwitch.unit
        width: 28 * glassSwitch.unit
        height: width
        radius: width / 2
        color: "#ffffff"
        Behavior on x {
            NumberAnimation { duration: GlassStyle.switchDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.switchCurve }
        }
    }
}
