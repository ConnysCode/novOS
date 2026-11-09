import QtQuick 2.12

// K3-Update-2-Details: what is new, with size, duration and restarts.
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
        label: tr("header.update")
        title: tr("update.title", { version: screen.live ? screen.live.version : "1.0" })
        // The board pulls the cards 8 px up under the title.
        contentHeight: 297
        leftButtons: [{ label: tr("button.later"), focused: (screen.live !== null && screen.live.focus === "later") }]
        rightButtons: [{ label: tr("button.tonight"), focused: (screen.live !== null && screen.live.focus === "tonight"), disabled: screen.live !== null },
                       { label: tr("button.update_now"), focused: (screen.live ? screen.live.focus === "now" : true),
                         disabled: screen.live !== null && screen.live.canUpdate !== true }]

        InsetCard {
            y: -8 * screen.unit
            width: 764 * screen.unit
            height: 305 * screen.unit
            unit: screen.unit

            SectionTitle {
                x: 28 * screen.unit
                y: 28 * screen.unit
                unit: screen.unit
                text: tr("update.new")
                color: GlassStyle.textSecondary
                font.letterSpacing: 1.28 * screen.unit
            }

            Column {
                x: 28 * screen.unit
                y: 68 * screen.unit
                width: parent.width - 56 * screen.unit
                spacing: 22 * screen.unit

                Repeater {
                    model: screen.live ? screen.live.news : [
                        { icon: "setup-gamepad-30", title: tr("update.games_title"), detail: tr("update.games_detail") },
                        { icon: "setup-search-30", title: tr("update.search_title"), detail: tr("update.search_detail") },
                        { icon: "setup-sparkle-30", title: tr("update.faster_title"), detail: tr("update.faster_detail") }
                    ]
                    IconLine {
                        width: parent.width
                        unit: screen.unit
                        icon: modelData.icon
                        iconSize: 30
                        gap: 18
                        titleSize: 22
                        detailSize: 19
                        title: modelData.title
                        detail: modelData.detail
                    }
                }
            }
        }

        FactList {
            x: 788 * screen.unit
            y: -8 * screen.unit
            width: 380 * screen.unit
            height: 305 * screen.unit
            unit: screen.unit
            rowGap: 0
            rows: screen.live ? screen.live.facts : [
                { label: tr("update.size"), value: "41 MB" },
                { label: tr("update.duration"), value: tr("update.duration_value", { count: 3 }) },
                { label: tr("update.restarts"), value: "2" },
                { label: tr("update.settings"), value: tr("update.settings_kept") }
            ]
        }
    }
}
