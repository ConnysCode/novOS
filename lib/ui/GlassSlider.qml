import QtQuick 2.12
import "."

// Slider track of novOS: 6 px high, round ends, white fill on glass and dark fill on the
// focus surface. share is 0..1. The owner places it and gives its width.
Rectangle {
    id: slider

    property real unit: 1
    property real share: 0
    property bool focused: false
    property bool disabled: false

    height: 6 * unit
    radius: 3 * unit
    opacity: disabled ? 0.5 : 1
    color: focused ? GlassStyle.trackFocused : GlassStyle.trackFill

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, slider.share))
        height: parent.height
        radius: parent.radius
        color: slider.focused ? GlassStyle.focusText : "#ffffff"
        Behavior on width { NumberAnimation { duration: GlassStyle.colorDuration } }
    }
}
