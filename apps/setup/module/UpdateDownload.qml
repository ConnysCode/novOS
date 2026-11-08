import QtQuick 2.12

// K3-Update-3-Laden: the download runs in the background, shown in a small pill at the
// top right while the picture keeps running.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: ""

    function tr(key, params) { return I18n.t("setup", key, params); }

    ImageGlass {
        id: glass
        sourceItem: screen.backdrop
        unit: screen.unit
        area: Qt.rect(pill.x, pill.y, pill.width, pill.height)
        visible: false
    }

    Item {
        id: pill
        x: screen.width - width - 56 * screen.unit
        y: 56 * screen.unit
        width: content.width + 44 * screen.unit
        height: 64 * screen.unit

        SoftShadow {
            anchors.centerIn: parent
            unit: screen.unit
            radius: 32
            softness: 8
            drop: 8
            strength: 0.30
        }

        GlassCard {
            anchors.fill: parent
            unit: screen.unit
            cornerRadius: 32 * screen.unit
            backdrop: glass.texture
            glassShader: GlassStyle.glassShader
            backdropMargin: glass.margin
            backdropArea: glass.area
            hasBackdrop: 1
            shadow: ""
        }

        Row {
            id: content
            x: 20 * screen.unit
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14 * screen.unit

            ProgressRing {
                anchors.verticalCenter: parent.verticalCenter
                unit: screen.unit
                value: 0.42
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tr("update.loading", { version: "1.0" })
                color: GlassStyle.textPrimary
                font.family: GlassStyle.titleFont
                font.pixelSize: 20 * screen.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "42 %"
                color: "#c7ffffff"
                font.family: GlassStyle.valueFont
                font.pixelSize: 20 * screen.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }
    }
}
