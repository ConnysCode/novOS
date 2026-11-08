import QtQuick 2.12

// K3-Install-4-Datenschutz: LG's ads and tracking, switched off by novOS.
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
        step: 4
        title: tr("privacy.title")
        lead: tr("privacy.lead")
        contentHeight: list.logicalHeight
        leftButtons: [{ label: tr("button.back") }]
        rightButtons: [{ label: tr("button.next") }]

        SwitchList {
            id: list
            width: parent.width
            unit: screen.unit
            rows: [
                { title: tr("privacy.ads_title"), detail: tr("privacy.ads_detail"), on: false, focused: true },
                { title: tr("privacy.home_ads_title"), on: false },
                { title: tr("privacy.history_title"), detail: tr("privacy.history_detail"), on: false },
                { title: tr("privacy.recommendations_title"), on: false }
            ]
        }
    }
}
