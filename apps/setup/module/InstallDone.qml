import QtQuick 2.12

// K3-Install-9-Fertig: the three keys worth knowing.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: ""

    function tr(key) { return I18n.t("setup", key); }

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        label: tr("header.install")
        title: tr("done.title")
        lead: tr("done.lead")
        contentHeight: 201
        rightButtons: [{ label: tr("button.to_home"), focused: true }]

        Row {
            spacing: 20 * screen.unit

            Repeater {
                model: [
                    { key: tr("done.home_key"), title: tr("done.home_title"), body: tr("done.home_body") },
                    { key: tr("done.gear_key"), title: tr("done.gear_title"), body: tr("done.gear_body") },
                    { key: tr("done.input_key"), title: tr("done.input_title"), body: tr("done.input_body") }
                ]
                InsetCard {
                    width: 376 * screen.unit
                    height: 201 * screen.unit
                    unit: screen.unit

                    Rectangle {
                        id: chip
                        x: 26 * screen.unit
                        y: 26 * screen.unit
                        width: keyText.width + 32 * screen.unit
                        height: 40 * screen.unit
                        radius: height / 2
                        color: "transparent"
                        border.width: 2 * screen.unit
                        border.color: "#8cffffff"

                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData.key
                            color: GlassStyle.textPrimary
                            font.family: GlassStyle.titleFont
                            font.pixelSize: 18 * screen.unit
                            font.letterSpacing: 0.36 * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }

                    Text {
                        x: 26 * screen.unit
                        y: chip.y + chip.height + 18 * screen.unit
                        height: 29 * screen.unit
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.title
                        color: GlassStyle.textPrimary
                        font.family: GlassStyle.titleFont
                        font.pixelSize: 23 * screen.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        x: 26 * screen.unit
                        y: chip.y + chip.height + 55 * screen.unit
                        width: 324 * screen.unit
                        text: modelData.body
                        wrapMode: Text.WordWrap
                        color: "#c2ffffff"
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 26 * screen.unit
                        font.family: GlassStyle.valueFont
                        font.pixelSize: 19 * screen.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }
        }
    }
}
