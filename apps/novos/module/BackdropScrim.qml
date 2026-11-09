import QtQuick 2.12
import "."

// The scrims of launcher and hub over their picture: from the left behind the stage, and
// from the top behind the clock. Each page draws it twice: once inside the item its
// ImageGlass samples, so the glass lies on the dimmed picture, and once on screen, since
// the glass hides what it samples.
Item {
    id: scrims

    property real unit: 1

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: GlassStyle.scrim(0.62) }
            GradientStop { position: 0.55; color: GlassStyle.scrim(0.30) }
            GradientStop { position: 1; color: GlassStyle.scrim(0.20) }
        }
    }

    Rectangle {
        width: parent.width
        height: 220 * scrims.unit
        gradient: Gradient {
            GradientStop { position: 0; color: GlassStyle.scrim(0.45) }
            GradientStop { position: 1; color: GlassStyle.scrim(0) }
        }
    }
}
