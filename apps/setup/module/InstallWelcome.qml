import QtQuick 2.12

// K3-Install-1-Willkommen: what novOS is, in three cards.
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
        step: 1
        title: tr("welcome.title")
        lead: tr("welcome.lead")
        contentHeight: 274
        leftButtons: [{ label: tr("button.cancel") }]
        rightButtons: [{ label: tr("button.start"), focused: true }]

        Row {
            y: 8 * screen.unit
            spacing: 20 * screen.unit

            Repeater {
                model: [
                    { icon: "setup-home-36", title: tr("welcome.interface_title"), body: tr("welcome.interface_body") },
                    { icon: "setup-apps-36", title: tr("welcome.keep_title"), body: tr("welcome.keep_body") },
                    { icon: "setup-refresh-36", title: tr("welcome.undo_title"), body: tr("welcome.undo_body") }
                ]
                InsetCard {
                    width: 376 * screen.unit
                    height: 266 * screen.unit
                    unit: screen.unit

                    Image {
                        x: 28 * screen.unit
                        y: 28 * screen.unit
                        width: 36 * screen.unit
                        height: width
                        source: Qt.resolvedUrl("icons/" + modelData.icon + ".png")
                    }

                    Column {
                        x: 28 * screen.unit
                        y: 88 * screen.unit
                        width: 320 * screen.unit
                        spacing: 10 * screen.unit

                        Text {
                            width: parent.width
                            text: modelData.title
                            wrapMode: Text.WordWrap
                            color: GlassStyle.textPrimary
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 30 * screen.unit
                            font.family: GlassStyle.titleFont
                            font.pixelSize: 24 * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Text {
                            width: parent.width
                            text: modelData.body
                            wrapMode: Text.WordWrap
                            color: "#c2ffffff"
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 27 * screen.unit
                            font.family: GlassStyle.valueFont
                            font.pixelSize: 19 * screen.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }
        }
    }
}
