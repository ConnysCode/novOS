pragma Singleton
import QtQuick 2.12
import Qt.labs.settings 1.0

// Values only novOS keeps, next to the shared ones in lib/ui's GlassStyle. Both live in
// the same settings file; each keeps its own keys.
QtObject {
    id: novos

    property alias hideInputBanner: values.hideInputBanner
    property alias demoDevices: values.demoDevices

    // LG's Home starts its preview with this role, and its input apps then leave out their
    // banner. It lasts until the next launch of that input, and touches a few of LG's
    // checks there, so the debug page can turn it off. banner-relay.py reads the same value.
    function launchRequest(appId) {
        var request = { id: appId };
        if (hideInputBanner && appId.indexOf("com.webos.app.hdmi") === 0) {
            request.params = { appViewRole: "appViewGuest" };
        }
        return JSON.stringify(request);
    }

    property Settings values: Settings {
        id: values
        fileName: "/tmp/novos-debug.ini"
        property bool hideInputBanner: true
        property bool demoDevices: false     // the smart home hub's made-up home
    }
}
