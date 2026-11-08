import QtQuick 2.12

// A dialog while something runs, without buttons: what runs and how far, then its steps.
//   "install"  K3-Install-7-Laeuft
//   "update"   K3-Update-4-Installieren
//   "remove"   K3-Entfernen-3-Laeuft
// Values are the boards' demo values.
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: "install"

    function tr(key, params) { return I18n.t("setup", key, params); }

    readonly property var spec: ({
        install: {
            label: tr("header.install"), title: tr("progress.install_title"), lead: tr("progress.install_lead"),
            task: tr("progress.files"), value: 0.64, remaining: tr("progress.minute_one"),
            rows: [
                { status: "done", label: tr("progress.download"), value: "34 MB" },
                { status: "done", label: tr("progress.verify"), value: tr("progress.signature_ok") },
                { status: "running", label: tr("progress.files"), value: tr("progress.of", { done: 7, count: 10 }) },
                { status: "pending", label: tr("progress.settings") },
                { status: "pending", label: tr("progress.restart") }
            ]
        },
        update: {
            label: tr("header.update"), title: tr("update.install_title", { version: "1.0" }),
            lead: tr("update.install_lead"),
            task: tr("update.installing"), value: 0.58, remaining: tr("progress.minute_other", { count: 2 }),
            rows: [
                { status: "done", label: tr("update.loaded"), value: "41 MB" },
                { status: "done", label: tr("update.backup", { version: "0.9" }), value: tr("update.backup_detail") },
                { status: "running", label: tr("update.installing"), value: "58 %" },
                { status: "pending", label: tr("update.restart_swap") },
                { status: "pending", label: tr("update.restart_finish") }
            ]
        },
        remove: {
            label: tr("header.remove"), title: tr("remove.running_title"), lead: tr("remove.running_lead"),
            task: tr("remove.data_title"), value: 0.72, remaining: tr("progress.almost"),
            rows: [
                { status: "done", label: tr("remove.originals"), value: tr("progress.of", { done: 10, count: 10 }) },
                { status: "done", label: tr("remove.privacy_kept"), value: tr("remove.off_count", { count: 4 }) },
                { status: "running", label: tr("remove.data_title") },
                { status: "pending", label: tr("progress.restart") }
            ]
        }
    })
    readonly property var current: spec[variant] || spec.install

    WizardDialog {
        anchors.fill: parent
        unit: screen.unit
        backdrop: screen.backdrop
        label: screen.current.label
        title: screen.current.title
        lead: screen.current.lead
        contentHeight: 94 + 28 + list.logicalHeight

        ProgressBlock {
            width: parent.width
            unit: screen.unit
            label: screen.current.task
            value: screen.current.value
            remaining: screen.current.remaining
        }

        StatusList {
            id: list
            y: 122 * screen.unit
            width: parent.width
            unit: screen.unit
            rows: screen.current.rows
        }
    }
}
