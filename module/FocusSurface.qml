import QtQuick 2.12
import "."

// The single focus surface of novOS: a nearly white plate with a soft shadow that glides to
// the focused element (docs/design-system.md, "Fokus und Bedienung"). The owner sets x, y,
// width and height in px and the radius in logical px; the surface brings the motion, the
// colour and the shadow. pressScale gives the short pulse of a key press (0.93 for 40 ms).
Item {
    id: surface

    property real unit: 1
    property real radius: 26
    property bool animated: true         // false jumps, for example when a list is rebuilt
    property real focusScale: 1          // GlassStyle.focusScale for elements that grow
    property real pressScale: 1

    scale: focusScale * pressScale

    Behavior on scale {
        NumberAnimation { duration: GlassStyle.pressDuration; easing.type: Easing.OutQuad }
    }
    Behavior on x {
        enabled: surface.animated
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }
    Behavior on y {
        enabled: surface.animated
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }
    Behavior on width {
        enabled: surface.animated
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }
    Behavior on height {
        enabled: surface.animated
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }

    // 0 14px 32px rgba(0, 0, 0, .30), as in the hand-off.
    SoftShadow {
        unit: surface.unit
        radius: surface.radius
    }

    Rectangle {
        anchors.fill: parent
        radius: surface.radius * surface.unit
        color: GlassStyle.focusFill
        antialiasing: true
    }
}
