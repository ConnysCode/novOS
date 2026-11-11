import QtQuick 2.12
import SystemUIComponent 1.0
import "module"

// Preview of the volume pill as a system window, for preview-on-tv.sh. The real pill
// lives in the compositor (volume-view.qml) and reads LS.audioService, which a window
// does not have. Here a script plays one of the K3-Laut boards, chosen with
//   PREVIEW_SED='s/property string demo: "level"/property string demo: "chip"/'
// Values are demo values, not the TV's volume.
StarfishSystemUIWindow {
    id: rootWindow
    objectName: "starfishSystemUIWindow"

    property string demo: "level"

    function speaker(volume) {
        return { volume: volume, maximum: 100, muted: false, output: "tv_speaker" };
    }

    function bluetooth(volume, avrcp) {
        return { volume: volume, maximum: 100, muted: false, output: "bt_soundbar", cause: "volumeUp",
                 bluetooth: avrcp ? { name: "Sony WH-1000XM5", kind: "headphones", avrcp: true }
                                  : { name: "LG Soundbar S90TY", kind: "soundbar", avrcp: false } };
    }

    function muted(volume) {
        return { volume: volume, maximum: 100, muted: true, output: "tv_speaker" };
    }

    // [delay in ms, state, keep the pill open]
    readonly property var scripts: ({
        level: [[0, speaker(40)], [300, speaker(41)], [420, speaker(42), true]],
        quiet: [[0, speaker(9)], [300, speaker(8), true]],
        max: [[0, speaker(99)], [300, speaker(100), true]],
        mute: [[0, muted(42), true]],
        muted: [[0, muted(42)], [600, muted(42), true]],
        chip: [[0, muted(42)]],
        unmute: [[0, muted(42)], [3200, speaker(42)]],
        soundbar: [[0, { volume: 27, maximum: 100, output: "external_arc" }, true]],
        headphones: [[0, { volume: 60, maximum: 100, output: "headphone" }, true]],
        exterior: [[0, { volume: 0, maximum: 100, output: "external_optical", exterior: true,
                        cause: "volumeUp" }, true]],
        // K3-Einst-Bluetooth-Audio-17 and -18: a Bluetooth device with and without AVRCP.
        bluetooth: [[0, bluetooth(34, true)], [300, bluetooth(35, true), true]],
        bluetoothDevice: [[0, bluetooth(20, false), true]],
        // K3-Einst-WiSA-WOWCAST-21 and -22: WiSA speakers take the TV's volume, WOWCAST keeps its own.
        wisa: [[0, { volume: 39, maximum: 100, output: "wisa_speaker" }],
               [300, { volume: 40, maximum: 100, output: "wisa_speaker" }, true]],
        wowcast: [[0, { volume: 0, maximum: 100, output: "wow_cast", exterior: true, cause: "volumeUp" }, true]]
    })
    property int step: 0

    Connections {
        target: rootWindow.lifeCycleStatus
        onLaunch: {
            rootWindow.show();
            rootWindow.step = 0;
            player.restart();
        }
        onClose: rootWindow.exit()
    }

    FontLoader { id: titleFont; source: Qt.resolvedUrl("novos-inter-title.ttf") }
    FontLoader { id: valueFont; source: Qt.resolvedUrl("novos-inter-value.ttf") }

    VolumePill {
        id: pill
        anchors.fill: parent
        titleFamily: titleFont.name
        valueFamily: valueFont.name
    }

    Timer {
        id: player
        interval: rootWindow.scripts[rootWindow.demo][0][0] + 1
        onTriggered: {
            var script = rootWindow.scripts[rootWindow.demo];
            var entry = script[rootWindow.step];
            pill.update(entry[1]);
            if (entry[2]) pill.hold(true);
            rootWindow.step += 1;
            if (rootWindow.step < script.length) {
                interval = script[rootWindow.step][0];
                restart();
            }
        }
    }
}
