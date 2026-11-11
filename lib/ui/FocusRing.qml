import QtQuick 2.12
import "."

// The ring of "Kontrast für Fokus" (QS-2, K3-Einst-FokusBetonung): 3 px dark right at the edge
// of a focus plate, 3 px white outside it, so that it stands on bright, dark and busy pictures.
// It belongs to the plate: the owner lays it over the plate (anchors.fill), gives the plate's
// radius in px and shows it while the plate shows the focus; it moves, scales and pulses with
// the plate. Only with GlassStyle.focusEmphasis; it fades in on the current focus when the
// switch goes on. No glow, no blur, no motion of its own.
Item {
    id: ring

    property real unit: 1
    property real radius: 0              // the plate's radius in px
    property bool shown: true
    readonly property real stroke: GlassStyle.focusRingWidth * unit
    readonly property real gap: GlassStyle.focusRingGap * unit

    opacity: GlassStyle.focusEmphasis && shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -(ring.gap + ring.stroke)
        radius: ring.radius + ring.gap + ring.stroke
        color: "transparent"
        border.width: ring.stroke
        border.color: GlassStyle.focusRingInner
        antialiasing: true
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -(ring.gap + 2 * ring.stroke)
        radius: ring.radius + ring.gap + 2 * ring.stroke
        color: "transparent"
        border.width: ring.stroke
        border.color: GlassStyle.focusRingColor
        antialiasing: true
    }
}
