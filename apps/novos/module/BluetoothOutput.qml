import QtQuick 2.12
import WebOSServices 1.0
import "."
import "DeviceList.js" as DeviceList

// The Bluetooth headphones and speakers outside the settings: the panel offers the connected
// one as output (K3-Einst-Bluetooth-Audio-16), the volume pill names it and knows whether it
// takes the TV's volume (AVRCP, -17) or keeps its own (-18). Read only, as LG's settings
// read them: btaudiosrc/getPairedDevices as a subscription while active.
Item {
    id: output

    property bool active: false
    property var devices: []            // { address, name, kind, state, avrcp, atmos }
    // Preview only (PREVIEW_MODULE_SED): a connected device instead of LG's answer.
    property bool demo: false
    readonly property var connected: firstConnected(devices)

    function firstConnected(list) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].state === "connected") return list[i];
        }
        return null;
    }

    function apply(response) {
        if (!response || response.devices === undefined) return;
        var list = [];
        for (var i = 0; i < response.devices.length; i++) {
            var device = response.devices[i];
            if (device.display === false) continue;
            list.push({ address: device.address, name: device.name || device.address, state: device.state || "",
                        kind: DeviceList.audioKind(device.name), avrcp: device.avrcpConnected === true,
                        atmos: !!device.ATMOSDevice });
        }
        devices = list;
    }

    onActiveChanged: if (!active) devices = []
    Component.onCompleted: {
        if (demo) devices = [{ address: "demo", name: "Sony WH-1000XM5", state: "connected", kind: "headphones",
                               avrcp: true, atmos: false }];
    }

    // Destroying the service ends the subscription.
    Instantiator {
        active: output.active && !output.demo
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call("luna://com.webos.service.btaudiosrc", "/getPairedDevices",
                                        JSON.stringify({ subscribe: true }))
            onResponse: output.apply(JSON.parse(payload))
        }
    }
}
