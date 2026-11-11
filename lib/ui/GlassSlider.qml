import QtQuick 2.12
import "."

// Slider track of novOS: 6 px high, round ends, white fill on glass and dark fill on the
// focus surface. share is 0..1. The owner places it and gives its width.
// Vertical variant (the bands of BandEditor): 8 px wide, the owner gives the height, share 1
// is at the top. origin is the share the fill starts from: 0.5 with zeroLine fills up or down
// from a mark in the middle, as an equalizer band around 0. knob adds a 30 px knob.
Rectangle {
    id: slider

    property real unit: 1
    property real share: 0
    property bool focused: false
    property bool disabled: false
    property bool vertical: false
    property real origin: 0
    property bool zeroLine: false
    property bool knob: false

    readonly property real thickness: vertical ? 8 : 6
    readonly property real clamped: Math.max(0, Math.min(1, share))
    readonly property real fillStart: Math.min(origin, clamped)
    readonly property real fillEnd: Math.max(origin, clamped)
    readonly property real length: vertical ? height : width
    readonly property color fillColor: focused ? GlassStyle.focusText : "#ffffff"

    width: thickness * unit
    height: thickness * unit
    radius: thickness / 2 * unit
    opacity: disabled ? 0.5 : 1
    color: focused ? GlassStyle.trackFocused : GlassStyle.trackFill

    Rectangle {
        x: slider.vertical ? 0 : slider.fillStart * slider.length
        y: slider.vertical ? (1 - slider.fillEnd) * slider.length : 0
        width: slider.vertical ? parent.width : (slider.fillEnd - slider.fillStart) * slider.length
        height: slider.vertical ? (slider.fillEnd - slider.fillStart) * slider.length : parent.height
        radius: parent.radius
        color: slider.fillColor
        Behavior on x { NumberAnimation { duration: GlassStyle.colorDuration } }
        Behavior on y { NumberAnimation { duration: GlassStyle.colorDuration } }
        Behavior on width { NumberAnimation { duration: GlassStyle.colorDuration } }
        Behavior on height { NumberAnimation { duration: GlassStyle.colorDuration } }
    }

    // The mark of the origin: 40 px across the track, 2 px along it.
    Rectangle {
        visible: slider.zeroLine
        x: slider.vertical ? (slider.width - width) / 2 : slider.origin * slider.length - width / 2
        y: slider.vertical ? (1 - slider.origin) * slider.length - height / 2 : (slider.height - height) / 2
        width: (slider.vertical ? 40 : 2) * slider.unit
        height: (slider.vertical ? 2 : 40) * slider.unit
        radius: slider.unit
        color: slider.focused ? GlassStyle.zeroLineFocused : GlassStyle.zeroLine
    }

    Item {
        visible: slider.knob
        x: (slider.vertical ? slider.width / 2 : slider.clamped * slider.length) - width / 2
        y: (slider.vertical ? (1 - slider.clamped) * slider.length : slider.height / 2) - height / 2
        width: 30 * slider.unit
        height: width
        Behavior on x { NumberAnimation { duration: GlassStyle.colorDuration } }
        Behavior on y { NumberAnimation { duration: GlassStyle.colorDuration } }

        // 0 3px 10px rgba(0, 0, 0, .35), as in the hand-off.
        SoftShadow {
            unit: slider.unit
            radius: 15
            softness: 5
            drop: 3
            strength: 0.35
            pad: 16
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: slider.fillColor
            antialiasing: true
        }
    }
}
