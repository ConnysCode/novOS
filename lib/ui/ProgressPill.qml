import QtQuick 2.12
import "."

// Small glass pill for work that runs in the background (board Update-3): a progress ring,
// a label and a value such as "42 %". 64 px high; the owner places it, novOS at the top
// right, 56 px from the edges. It takes no keys.
Item {
    id: pill

    property real unit: 1
    property string titleFont: ""
    property string valueFont: ""
    property string glassShader: ""
    property variant backdrop
    property real backdropMargin: 0
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property string label: ""
    property string value: ""
    property real progress: 0
    property bool shown: false

    width: content.width + 44 * unit
    height: 64 * unit
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: GlassStyle.popoverDuration }
    }

    SoftShadow {
        unit: pill.unit
        radius: 32
        softness: 16
        drop: 8
        strength: 0.30
        pad: 60
    }

    GlassCard {
        anchors.fill: parent
        unit: pill.unit
        cornerRadius: 32 * pill.unit
        backdrop: pill.backdrop
        glassShader: pill.glassShader
        backdropMargin: pill.backdropMargin
        backdropArea: pill.backdropArea
        hasBackdrop: pill.hasBackdrop
        shadow: ""
    }

    Row {
        id: content
        x: 20 * pill.unit
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14 * pill.unit

        ProgressRing {
            anchors.verticalCenter: parent.verticalCenter
            unit: pill.unit
            value: pill.progress
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            color: GlassStyle.textPrimary
            font.family: pill.titleFont
            font.pixelSize: GlassStyle.pillTextSize * pill.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.value !== ""
            text: pill.value
            color: GlassStyle.textSecondary
            font.family: pill.valueFont
            font.pixelSize: GlassStyle.pillTextSize * pill.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }
}
