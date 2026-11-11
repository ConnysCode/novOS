import QtQuick 2.12
import "."

// A bar that fills from the left. 12 px with a white fill on a 16 % track in dialogs,
// 6 px on an 18 % track on the restart screens. value is 0 … 1.
Rectangle {
    id: bar

    property real unit: 1
    property real value: 0
    property real barHeight: 12

    height: barHeight * unit
    radius: height / 2
    color: barHeight > 8 ? GlassStyle.fillActive : GlassStyle.fillActiveStrong
    clip: true

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, bar.value))
        height: parent.height
        radius: barHeight > 8 ? parent.radius : 0
        color: GlassStyle.textPrimary

        Behavior on width {
            NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
        }
    }
}
