import QtQuick 2.12

// The channel to install from, right after the welcome and before the check, which then
// looks in that channel: Stabil or Beta, as Einstellungen › novOS-Update › Testversionen
// erhalten later. novos-setupd keeps it for every later update.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: ""
    // Values and focus of the running setup (Wizard); null shows a demo state.
    property var live: null

    function tr(key) { return I18n.t("setup", key); }
    readonly property string channel: live ? live.channel : "stable"

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        focusKey: screen.live ? (screen.live.focus || "") : ""
        label: tr("header.install")
        step: 2
        title: tr("channel.title")
        lead: tr("channel.lead")
        contentHeight: 240
        leftButtons: [{ label: tr("button.back"), focused: (screen.live !== null && screen.live.focus === "back") }]
        rightButtons: [{ label: tr("button.next"), focused: (screen.live !== null && screen.live.focus === "next") }]

        Repeater {
            model: [
                { id: "stable", icon: "setup-shield-44", title: tr("channel.stable_title"), detail: tr("channel.stable_detail") },
                { id: "beta", icon: "setup-flask-44", title: tr("channel.beta_title"), detail: tr("channel.beta_detail") }
            ]
            OptionCard {
                id: channelCard
                readonly property bool focusedHere: screen.live ? screen.live.focus === modelData.id : modelData.id === "beta"
                ownFocus: false
                x: index * 594 * screen.unit
                width: 574 * screen.unit
                height: 240 * screen.unit
                unit: screen.unit
                title: modelData.title
                subtitle: modelData.detail
                selected: screen.channel === modelData.id
                focused: focusedHere

                Image {
                    width: 44 * screen.unit
                    height: width
                    smooth: true
                    source: Qt.resolvedUrl("icons/" + modelData.icon + (channelCard.focusedHere ? "-dark" : "") + ".png")
                }
            }
        }
    }
}
