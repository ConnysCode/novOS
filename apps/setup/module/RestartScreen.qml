import QtQuick 2.12

// Full screen in black while the TV restarts, over the "glow" or "black" scene:
//   "install"   K3-Install-8-Neustart: wordmark, a bar at 88 %, two lines
//   "update"    K3-Update-5-Neustart: wordmark, one segment per restart, two lines
//   "farewell"  K3-Entfernen-4-Fertig: dimmed wordmark and two lines, nothing else
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: "install"

    function tr(key, params) { return I18n.t("setup", key, params); }

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
            value: 0.88
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
                text: screen.farewell ? tr("remove.done_title") :
                      screen.variant === "update" ? tr("restart.update_title") : tr("restart.install_title")
                color: GlassStyle.textPrimary
                font.family: GlassStyle.titleFont
                font.pixelSize: (screen.farewell ? 24 : 22) * screen.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: screen.farewell ? tr("remove.done_detail") :
                      screen.variant === "update" ? tr("restart.update_detail", { step: 1, count: 2 }) :
                      tr("restart.install_detail")
                color: GlassStyle.textSecondary
                font.family: GlassStyle.valueFont
                font.pixelSize: (screen.farewell ? 20 : 19) * screen.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }
    }
}
