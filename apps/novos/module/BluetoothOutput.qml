import QtQuick 2.12
import WebOSServices 1.0
import "."
import "DeviceList.js" as DeviceList

// The Bluetooth headphones and speakers outside the settings: the panel offers the connected
// one as output (K3-Einst-Bluetooth-Audio-16), the volume pill names it and knows whether it
// takes the TV's volume (AVRCP, -17) or keeps its own (-18). Read as LG's settings read them:
// btaudiosrc/getPairedDevices as a subscription while active. With readsVolume (the hearing
// aid on the panel's sound page, K3-Einst-Hoergeraet-11) also the connected device's volume,
// which setVolume changes once the key rests.
Item {
    id: output

    property bool active: false
    property var devices: []            // { address, name, kind, state, avrcp, atmos }
    // Preview only (PREVIEW_MODULE_SED): a connected device instead of LG's answer.
    property bool demo: false
    readonly property var connected: firstConnected(devices)
    property bool readsVolume: false
    property int volume: -1
    readonly property int volumeDelay: 120         // the volume goes out once the key rests
    readonly property string audioUri: "luna://com.webos.service.btaudiosrc"

    function setVolume(value) {
        if (!connected || !connected.avrcp) return;
        volume = Math.max(0, Math.min(100, value));
        volumeTimer.restart();
    }

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
    onReadsVolumeChanged: if (!readsVolume) volume = -1

    Timer {
        id: volumeTimer
        interval: output.volumeDelay
        onTriggered: {
            if (output.connected) volumeService.call(output.audioUri, "/setDeviceVolume",
                JSON.stringify({ address: output.connected.address, deviceVolume: output.volume }));
        }
    }

    Service {
        id: volumeService
        appId: "com.webos.app.quicksettings"
    }

    // getDeviceVolume {subscribe, address}, only with AVRCP, as LG's settings read it.
    Instantiator {
        active: output.readsVolume && !output.demo && !!output.connected && output.connected.avrcp
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call(output.audioUri, "/getDeviceVolume",
                                        JSON.stringify({ subscribe: true, address: output.connected.address }))
            onResponse: {
                var response = JSON.parse(payload);
                if (response.returnValue && typeof response.deviceVolume === "number" && !volumeTimer.running) {
                    output.volume = response.deviceVolume;
                }
            }
        }
    }
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
