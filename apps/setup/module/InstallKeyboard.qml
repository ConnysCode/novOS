import QtQuick 2.12

// K3-Install-5-Tastatur: QWERTZ or T9, and automatic updates.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: ""
    // Values and focus of the running setup (Wizard); null shows the board's demo state.
    property var live: null

    function tr(key) { return I18n.t("setup", key); }

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        label: tr("header.install")
        step: 5
        title: tr("keyboard.title")
        lead: tr("keyboard.lead")
        contentHeight: 290 + 20 + updates.logicalHeight
        leftButtons: [{ label: tr("button.back"), focused: (screen.live !== null && screen.live.focus === "back") }]
        rightButtons: [{ label: tr("button.next"), focused: (screen.live !== null && screen.live.focus === "next") }]

        OptionCard {
            width: 574 * screen.unit
            height: 290 * screen.unit
            unit: screen.unit
            title: tr("keyboard.qwertz_title")
            subtitle: tr("keyboard.qwertz_detail")
            selected: screen.live ? screen.live.keyboard === "qwertz" : true
            focused: (screen.live !== null && screen.live.focus === "qwertz")

            // A small keyboard: two rows of ten keys, one of nine, then space with its neighbours.
            Column {
                spacing: 6 * screen.unit
                Repeater {
                    model: [[10, 22], [10, 22], [9, 22], [0, 0]]
                    Row {
                        spacing: 6 * screen.unit
                        Repeater {
                            model: modelData[0] > 0 ? modelData[0] : [50, 150, 50]
                            Rectangle {
                                width: (typeof modelData === "number" && modelData > 22 ? modelData : 22) * screen.unit
                                height: 14 * screen.unit
                                radius: 4 * screen.unit
                                color: "#4dffffff"
                            }
                        }
                    }
                }
            }
        }

        OptionCard {
            x: 594 * screen.unit
            width: 574 * screen.unit
            height: 290 * screen.unit
            unit: screen.unit
            title: tr("keyboard.t9_title")
            subtitle: tr("keyboard.t9_detail")
            selected: screen.live !== null && screen.live.keyboard === "t9"
            focused: (screen.live ? screen.live.focus === "t9" : true)

            // The number pad: three columns of four keys.
            Grid {
                columns: 3
                spacing: 6 * screen.unit
                Repeater {
                    model: 12
                    Rectangle {
                        width: 44 * screen.unit
                        height: 26 * screen.unit
                        radius: 4 * screen.unit
                        color: "#380b0c10"
                    }
                }
            }
        }

        SwitchList {
            id: updates
            y: 310 * screen.unit
            width: parent.width
            unit: screen.unit
            rows: [{ title: tr("keyboard.auto_update_title"), detail: tr("keyboard.auto_update_detail"),
                     on: screen.live ? screen.live.autoUpdate : true, focused: (screen.live !== null && screen.live.focus === "auto") },
                   { title: tr("keyboard.block_updates_title"), detail: tr("keyboard.block_updates_detail"),
                     on: screen.live ? screen.live.blockUpdates : true, focused: (screen.live !== null && screen.live.focus === "block") }]
        }
    }
}
