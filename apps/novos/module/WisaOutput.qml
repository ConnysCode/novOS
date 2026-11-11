import QtQuick 2.12
import WebOSServices 1.0
import "."

// The WiSA speakers outside the settings: the panel names their number under the output
// "WiSA-Lautsprecher" (K3-Einst-WiSA-WOWCAST-20). Read only, as LG's settings read them:
// wisa/getSelectedSpeakerState as a subscription while active. Without LG's WiSA dongle the
// service does not run and nothing answers; count stays -1 then.
Item {
    id: output

    property bool active: false
    property int count: -1                 // speakers that are not missing

    function apply(response) {
        if (!response || !Array.isArray(response.SelectedSpeakerlist)) return;
        count = response.SelectedSpeakerlist.filter(function (speaker) {
            return String(speaker.SPEAKER_STATUS || "") !== "SPEAKER_STATUS_MISSING";
        }).length;
    }

    onActiveChanged: if (!active) count = -1

    // Destroying the service ends the subscription.
    Instantiator {
        active: output.active
        delegate: Service {
            appId: "com.webos.app.quicksettings"
            Component.onCompleted: call("luna://com.webos.service.wisa", "/getSelectedSpeakerState",
                                        JSON.stringify({ subscribe: true }))
            onResponse: output.apply(JSON.parse(payload))
        }
    }
}
