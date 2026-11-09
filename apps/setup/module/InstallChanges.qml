import QtQuick 2.12

// K3-Install-3-Aenderungen: what novOS replaces and what stays as it is.
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
        label: tr("header.install")
        step: 4
        title: tr("change.title")
        contentHeight: 342
        leftButtons: [{ label: tr("button.back"), focused: (screen.live !== null && screen.live.focus === "back") }]
        rightButtons: [{ label: tr("button.next"), focused: (screen.live ? screen.live.focus === "next" : true) }]

        Row {
            spacing: 20 * screen.unit

            Repeater {
                model: [
                    { heading: tr("change.replaced"), items: [
                        { icon: "setup-home-28", title: tr("change.home_title"), detail: tr("change.home_detail") },
                        { icon: "setup-sliders-28", title: tr("change.quick_title"), detail: tr("change.quick_detail") },
                        { icon: "setup-sun-28", title: tr("change.settings_title"), detail: tr("change.settings_detail") },
                        { icon: "setup-bell-28", title: tr("change.notices_title"), detail: tr("change.notices_detail") }] },
                    { heading: tr("change.kept"), items: [
                        { icon: "setup-apps-28", title: tr("change.apps_title"), detail: tr("change.apps_detail") },
                        { icon: "setup-input-28", title: tr("change.sources_title"), detail: tr("change.sources_detail") },
                        { icon: "setup-monitor-28", title: tr("change.picture_title"), detail: tr("change.picture_detail") },
                        { icon: "setup-lock-28", title: tr("change.pin_title"), detail: tr("change.pin_detail") }] }
                ]
                ListCard {
                    width: 574 * screen.unit
                    height: 342 * screen.unit
                    unit: screen.unit
                    heading: modelData.heading
                    items: modelData.items
                }
            }
        }
    }
}
