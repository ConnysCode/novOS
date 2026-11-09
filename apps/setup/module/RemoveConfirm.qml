import QtQuick 2.12

// K3-Entfernen-2-Bestaetigen: what comes back, what stays, two last choices. The focus
// starts on Abbrechen; Entfernen is the quiet button in red.
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
        focusKey: screen.live ? (screen.live.focus || "") : ""
        label: tr("header.remove")
        title: tr("remove.title")
        lead: tr("remove.lead")
        contentHeight: 184 + 20 + choices.logicalHeight
        leftButtons: [{ label: tr("button.cancel"), focused: (screen.live ? screen.live.focus === "cancel" : true) }]
        rightButtons: [{ label: tr("button.remove"), danger: true, focused: (screen.live !== null && screen.live.focus === "remove") }]

        Row {
            spacing: 20 * screen.unit

            Repeater {
                model: [
                    { heading: tr("remove.returns"), items: [
                        { icon: "setup-home-28", title: tr("remove.lg_home_title"), detail: tr("remove.lg_home_detail") },
                        { icon: "setup-sliders-28", title: tr("remove.lg_menus_title") }] },
                    { heading: tr("remove.stays"), items: [
                        { icon: "setup-apps-28", title: tr("remove.apps_title") },
                        { icon: "setup-lock-28", title: tr("remove.pin_title") }] }
                ]
                ListCard {
                    width: 574 * screen.unit
                    height: 184 * screen.unit
                    unit: screen.unit
                    heading: modelData.heading
                    items: modelData.items
                }
            }
        }

        SwitchList {
            id: choices
            y: 204 * screen.unit
            width: parent.width
            unit: screen.unit
            rows: [
                { title: tr("remove.privacy_title"), detail: tr("remove.privacy_detail"), on: true,
                  disabled: screen.live !== null, focused: (screen.live !== null && screen.live.focus === "privacy") },
                { title: tr("remove.data_title"), detail: tr("remove.data_detail"),
                  on: screen.live ? screen.live.deleteData : true, focused: (screen.live !== null && screen.live.focus === "data") }
            ]
        }
    }
}
