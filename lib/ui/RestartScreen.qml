import QtQuick 2.12
import "."

// Full screen in black while the TV or novOS restarts, over the "glow" or "black" scene
// (BootGlow); the owner paints the scene:
//   "install"   K3-Install-8-Neustart: wordmark, a bar (progress, 88 % unless given), two lines
//   "update"    K3-Update-5-Neustart: wordmark, one segment per restart, two lines
//   "farewell"  K3-Entfernen-4-Fertig: dimmed wordmark and two lines, nothing else
// title and detail replace the variant's own lines: novOS names its update this way.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: "install"
    property string title: ""
    property string detail: ""
    property real progress: 0.88

    function tr(key, params) { return I18n.t("restart", key, params); }

    readonly property bool farewell: variant === "farewell"

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((screen.height - height) / 2)
        spacing: (screen.farewell ? 24 : 28) * screen.unit

        Wordmark {
            anchors.horizontalCenter: parent.horizontalCenter
            unit: screen.unit
            size: screen.farewell ? 80 : 88
            opacity: screen.farewell ? 0.55 : 1
        }

        ProgressBar {
            visible: screen.variant === "install"
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360 * screen.unit
            unit: screen.unit
            barHeight: 6
            value: screen.progress
        }

        SegmentBar {
            visible: screen.variant === "update"
            anchors.horizontalCenter: parent.horizontalCenter
            unit: screen.unit
            levels: [0.92, 0.92, 0.55, 0.18]
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: (screen.farewell ? 24 : 6) * screen.unit

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: screen.title !== "" ? screen.title : tr("title." + screen.variant)
                color: GlassStyle.textPrimary
                font.family: GlassStyle.titleFont
                font.pixelSize: (screen.farewell ? 24 : 22) * screen.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: screen.detail !== "" ? screen.detail :
                      tr("detail." + screen.variant, { step: 1, count: 2 })
                color: GlassStyle.textSecondary
                font.family: GlassStyle.valueFont
                font.pixelSize: (screen.farewell ? 20 : 19) * screen.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }
    }
}
