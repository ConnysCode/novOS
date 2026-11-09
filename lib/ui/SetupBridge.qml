import QtQuick 2.12
import Qt.labs.settings 1.0

// A window's side of novos-setupd serve: commands go into <folder>/command.ini, the
// service's state comes back from <folder>/state.json, read a few times a second while
// active. Windows run inside surface-manager and can neither start programs nor delete
// files; writing an ini file and reading a file is all they need. The setup's wizard uses
// /tmp/novos-setup, novOS' settings /tmp/novos-update (its supervisor starts the service).
Item {
    id: bridge

    property string folder: "/tmp/novos-setup"
    property bool active: true

    property var info: ({})          // state.json as read last
    property string infoText: ""     // its text, so that an unchanged file changes nothing
    readonly property string phase: info.phase || "idle"
    readonly property bool serving: info.serving === true
    readonly property int percent: info.percent || 0
    readonly property var steps: info.steps || []
    readonly property var result: info.result || null
    readonly property string error: info.error || ""
    readonly property var choices: info.choices || ({})
    readonly property var tv: info.tv || ({})
    readonly property string answeredId: info.id || ""
    property string sentId: ""
    // The answer to the last command sent from this window is in.
    readonly property bool answered: sentId !== "" && answeredId === sentId &&
                                     (phase === "done" || phase === "error")
    readonly property bool busy: sentId !== "" && !answered

    function send(command, values) {
        var id = String(Date.now());
        outbox.source = values && values.source || "";
        outbox.keyboard = values && values.keyboard || "";
        outbox.autoUpdate = values && values.autoUpdate || "";
        outbox.blockUpdates = values && values.blockUpdates || "";
        outbox.keepState = values && values.keepState ? "true" : "";
        outbox.version = values && values.version || "";
        outbox.manifest = values && values.manifest || "";
        outbox.target = values && values.target || "";
        outbox.params = values && values.params || "";
        outbox.command = command;
        outbox.serial = id;      // last: serve acts on a new serial
        sentId = id;
    }

    function stageSteps(key) {
        var found = [];
        for (var i = 0; i < steps.length; ++i) {
            if (steps[i].key === key) found.push(steps[i]);
        }
        return found;
    }

    function hasStage(key) {
        return stageSteps(key).length > 0;
    }

    Settings {
        id: outbox
        fileName: bridge.folder + "/command.ini"
        property string command: ""
        property string serial: ""
        property string source: ""
        property string keyboard: ""
        property string autoUpdate: ""
        property string blockUpdates: ""
        property string keepState: ""
        property string version: ""         // restore, tonight
        property string manifest: ""        // restore: the signed release of that version
        property string target: ""          // the entry a command is about (power-off videos)
        property string params: ""          // its values, as "name:value name:value"
    }

    Timer {
        interval: 300
        repeat: true
        running: bridge.active
        triggeredOnStart: true
        onTriggered: {
            try {
                var request = new XMLHttpRequest();
                request.open("GET", "file://" + bridge.folder + "/state.json", false);
                request.send();
                var text = String(request.responseText || "");
                if (text !== "" && text !== bridge.infoText) {
                    bridge.info = JSON.parse(text);
                    bridge.infoText = text;
                }
            } catch (error) {
                // The service writes the file anew; the next read gets it whole.
            }
        }
    }
}
