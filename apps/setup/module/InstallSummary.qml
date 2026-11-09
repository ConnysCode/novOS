import QtQuick 2.12

// K3-Install-6-Bereit: what will be installed, before anything changes.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: ""
    // Values and focus of the running setup (Wizard); null shows the board's demo state.
    property var live: null

    function tr(key, params) { return I18n.t("setup", key, params); }

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        focusKey: screen.live ? (screen.live.focus || "") : ""
        label: tr("header.install")
        step: 6
        title: tr("summary.title")
        lead: tr("summary.lead")
        contentHeight: facts.logicalHeight
        leftButtons: [{ label: tr("button.back"), focused: (screen.live !== null && screen.live.focus === "back") }]
        rightButtons: [{ label: tr("button.install"), focused: (screen.live ? screen.live.focus === "install" : true) }]

        FactList {
            id: facts
            width: parent.width
            unit: screen.unit
            rows: screen.live ? screen.live.rows : [
                { label: tr("summary.version"), value: tr("summary.version_value", { version: "0.9", size: "34 MB" }) },
                { label: tr("summary.duration"), value: tr("summary.duration_value") },
                { label: tr("summary.privacy"), value: tr("summary.privacy_value", { count: 4 }) },
                { label: tr("summary.keyboard"), value: tr("keyboard.qwertz_title") },
                { label: tr("summary.auto_update"), value: tr("summary.on") }
            ]
        }
    }
}
