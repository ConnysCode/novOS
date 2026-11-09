import QtQuick 2.12

// A dialog around a list of steps with their state:
//   "install-2"   the check before the installation runs (K3-Install-2-Pruefung)
//   "install-2b"  root access is missing (K3-Install-2b-Fehlt)
//   "install-x"   the installation stopped and everything was reset (K3-Install-X-Fehler)
//   "update-lg"   after a firmware update by LG (K3-Update-LG)
// Values are the boards' demo values.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: "install-2"
    // Values and focus of the running setup (Wizard); null shows the board's demo state.
    property var live: null

    function tr(key, params) { return I18n.t("setup", key, params); }

    readonly property var spec: ({
        "install-2": {
            label: tr("header.install"), step: 2, title: tr("check.title"), lead: tr("check.lead"),
            rows: [
                { status: "done", label: tr("check.tv"), value: "LG 55QNED816RE" },
                { status: "done", label: tr("check.webos"), value: tr("check.webos_value", { version: "10.3.2" }) },
                { status: "done", label: tr("check.root"), value: tr("check.root_found") },
                { status: "running", label: tr("check.storage"), value: tr("check.checking") },
                { status: "pending", label: tr("check.internet") }
            ],
            left: [{ label: tr("button.back") }],
            right: [{ label: tr("button.next"), disabled: true }]
        },
        "install-2b": {
            label: tr("header.install"), step: 2, title: tr("missing.title"), lead: tr("missing.lead"),
            rows: [
                { status: "done", label: tr("check.tv"), value: "LG 55QNED816RE" },
                { status: "done", label: tr("check.webos"), value: tr("check.webos_value", { version: "10.3.2" }) },
                { status: "error", label: tr("check.root"), value: tr("check.root_missing") },
                { status: "pending", label: tr("check.storage") },
                { status: "pending", label: tr("check.internet") }
            ],
            left: [{ label: tr("button.quit") }],
            right: [{ label: tr("button.check_again"), icon: "refresh-22", focused: true }]
        },
        "install-x": {
            label: tr("header.install"), step: 0, title: tr("error.title"), lead: tr("error.lead"),
            rows: [
                { status: "done", label: tr("progress.download"), value: "34 MB" },
                { status: "done", label: tr("progress.verify") },
                { status: "error", label: tr("progress.files"),
                  value: tr("error.code", { code: 12, reason: tr("error.file_busy") }) },
                { status: "reset", label: tr("error.reset"), value: tr("error.lg_active") }
            ],
            left: [{ label: tr("button.close") }],
            right: [{ label: tr("button.retry"), icon: "refresh-22", focused: true }]
        },
        "update-lg": {
            label: tr("header.after_lg"), step: 0, title: tr("lg.title"),
            lead: tr("lg.lead", { from: "10.3.2", to: "10.4.1" }),
            rows: [
                { status: "done", label: tr("lg.detected"), value: "10.4.1" },
                { status: "done", label: tr("lg.compared"), value: tr("lg.unchanged", { same: 9, count: 10 }) },
                { status: "done", label: tr("lg.found"), value: "novOS 0.9.1 · 12 MB" },
                { status: "pending", label: tr("lg.set_up"), value: tr("lg.restart_one") }
            ],
            left: [{ label: tr("button.later") }],
            right: [{ label: tr("button.set_up_now"), focused: true }]
        }
    })
    readonly property var current: live || spec[variant] || spec["install-2"]

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        label: screen.current.label
        step: screen.current.step
        title: screen.current.title
        lead: screen.current.lead
        contentHeight: list.logicalHeight
        leftButtons: screen.current.left
        rightButtons: screen.current.right

        StatusList {
            id: list
            width: parent.width
            unit: screen.unit
            rows: screen.current.rows
        }
    }
}
