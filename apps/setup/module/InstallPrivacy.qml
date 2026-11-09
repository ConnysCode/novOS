import QtQuick 2.12

// K3-Install-4-Datenschutz: LG's ads and tracking, switched off by novOS.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: ""
    // Values and focus of the running setup (Wizard); null shows the board's demo state.
    property var live: null

    function tr(key) { return I18n.t("setup", key); }
    function value(index) { return screen.live ? screen.live.values[index] === true : false; }

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        focusKey: screen.live ? (screen.live.focus || "") : ""
        label: tr("header.install")
        step: 5
        title: tr("privacy.title")
        lead: tr("privacy.lead")
        contentHeight: list.logicalHeight
        leftButtons: [{ label: tr("button.back"), focused: (screen.live !== null && screen.live.focus === "back") }]
        rightButtons: [{ label: tr("button.next"), focused: (screen.live !== null && screen.live.focus === "next") }]

        SwitchList {
            id: list
            width: parent.width
            unit: screen.unit
            rows: [
                { title: tr("privacy.ads_title"), detail: tr("privacy.ads_detail"), on: screen.value(0), focused: (screen.live ? screen.live.focus === "row0" : true) },
                { title: tr("privacy.home_ads_title"), on: screen.value(1), focused: (screen.live !== null && screen.live.focus === "row1") },
                { title: tr("privacy.history_title"), detail: tr("privacy.history_detail"), on: screen.value(2), focused: (screen.live !== null && screen.live.focus === "row2") },
                { title: tr("privacy.recommendations_title"), on: screen.value(3), focused: (screen.live !== null && screen.live.focus === "row3") }
            ]
        }
    }
}
