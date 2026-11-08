import QtQuick 2.12

// The notice at the bottom while the picture keeps running:
//   "available"  K3-Update-1-Hinweis: a new version is there
//   "installed"  K3-Update-6-Fertig: the update went through
Item {
    id: screen

    property real unit: 1
    property Item backdrop
    property string variant: "available"

    function tr(key, params) { return I18n.t("setup", key, params); }

    readonly property bool installed: variant === "installed"

    ImageGlass {
        id: glass
        sourceItem: screen.backdrop
        unit: screen.unit
        area: Qt.rect(bar.x, bar.y, bar.width, bar.height)
        visible: false
    }

    NoticeBar {
        id: bar
        x: Math.round((screen.width - width) / 2)
        y: screen.height - height - 56 * screen.unit
        unit: screen.unit
        titleFont: GlassStyle.titleFont
        valueFont: GlassStyle.valueFont
        glassShader: GlassStyle.glassShader
        backdrop: glass.texture
        backdropMargin: glass.margin
        backdropArea: glass.area
        hasBackdrop: 1
        shown: true
        focusIndex: screen.installed ? 1 : 0
        notice: screen.installed ? {
            title: tr("update.done_title", { version: "1.0" }), detail: tr("update.done_detail"),
            icon: "notice-update", buttons: [{ label: tr("button.news") }, { label: tr("button.ok") }]
        } : {
            title: tr("update.notice_title", { version: "1.0" }),
            detail: tr("update.notice_detail", { size: "41 MB" }),
            icon: "notice-update", buttons: [{ label: tr("button.view") }, { label: tr("button.later") }]
        }
    }
}
