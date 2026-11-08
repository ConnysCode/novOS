import QtQuick 2.12
import "."

// The panel's dialogs, name entry and Wi-Fi (WifiSetup), bound to the panel. Its own file so
// that the panel loads it by URL on first use: Qt then compiles it in its loader thread, not
// with the panel at the first opening after a restart (docs/performance-plan.md).
// host is the panel, glass its LiveBackdrop; both come with Loader.setSource().
WifiSetup {
    property var host: null
    property var glass: null

    unit: host ? host.unit : 1
    titleFont: host ? host.titleFamily : ""
    rowFont: host ? host.rowFamily : ""
    valueFont: host ? host.valueFamily : ""
    backdrop: glass ? glass.texture : null
    glassShader: glass ? glass.glassShader : ""
    shadowShader: glass ? glass.shadowShader : ""
    backdropMargin: host ? host.backdropMargin : 0
    backdropArea: host ? host.modalArea : Qt.rect(0, 0, 0, 0)
    hasBackdrop: glass && glass.hasFrame ? 1 : 0
    focusCurve: host ? host.standardCurve : GlassStyle.curve

    onActiveChanged: if (host) host.modalChanged()
    onDialogConfirmed: host.runDialogAction(action)
    onTextSaved: host.saveTvName(value)
    onDeviceNameSaved: host.saveDeviceName(value)
    onNetworkChanged: host.flowNetworkChanged()
}
