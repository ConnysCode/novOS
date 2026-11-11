import QtQuick 2.12
import WebOSServices 1.0
import "."

// The volume of a sender on HDMI (ARC) while "Hörgerät gleichzeitig" is HDMI (ARC) (BF-1).
// LG's own control has only steps: audio/master volumeUp and volumeDown with the output
// external_arc. Its level comes from audio/master getVolume for that output, as long as the
// TV answers with one; until then volume stays -1 and the row shows "–".
Item {
    id: output

    property bool active: false
    property int volume: -1
    readonly property string audioUri: "luna://com.webos.service.audio/master"

    function apply(response) {
        var status = response && response.volumeStatus ? response.volumeStatus : response;
        if (!status || status.returnValue === false) return;
        if (status.soundOutput !== undefined && status.soundOutput !== "external_arc") return;
        if (typeof status.volume === "number") volume = status.volume;
    }

    function step(direction) {
        stepper.call(audioUri, direction > 0 ? "/volumeUp" : "/volumeDown",
                     JSON.stringify({ soundOutput: "external_arc" }));
    }

    onActiveChanged: if (!active) volume = -1

    Service {
        id: stepper
        appId: "com.webos.app.quicksettings"
        onResponse: output.apply(JSON.parse(payload))
    }

    // Destroying the service ends the subscription.
    Instantiator {
        active: output.active
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call(output.audioUri, "/getVolume",
                                        JSON.stringify({ subscribe: true, soundOutput: "external_arc" }))
            onResponse: output.apply(JSON.parse(payload))
        }
    }
}
