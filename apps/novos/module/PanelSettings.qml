import QtQuick 2.12
import "."

// The large settings modal (SettingsModal), bound to the panel. Its own file so that the
// panel loads it by URL on first use: Qt then compiles it in its loader thread, not with the
// panel at the first opening after a restart (docs/performance-plan.md).
// host is the panel, glass its LiveBackdrop; both come with Loader.setSource().
SettingsModal {
    property var host: null
    property var glass: null

    settingsStore: host ? host.sharedSettings : null
    unit: host ? host.unit : 1
    titleFont: host ? host.titleFamily : ""
    rowFont: host ? host.rowFamily : ""
    valueFont: host ? host.valueFamily : ""
    backdrop: glass ? glass.texture : null
    glassShader: glass ? glass.glassShader : ""
    shadowShader: glass ? glass.shadowShader : ""
    backdropMargin: host ? host.backdropMargin : 0
    backdropArea: host ? host.settingsArea : Qt.rect(0, 0, 0, 0)
    hasBackdrop: glass && glass.hasFrame ? 1 : 0
    focusCurve: host ? host.standardCurve : GlassStyle.curve
    hostState: host ? host.settingsHostState : ({})

    onActiveChanged: if (host) host.modalChanged()
    onHostAction: host.settingsHostAction(name, params)
    onLaunchApp: host.openLink(app)
}
