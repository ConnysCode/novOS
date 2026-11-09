import QtQuick 2.12
import SystemUIComponent 1.0
import "module"
import "module/Slides.js" as Slides

// The setup of novOS: installing, updating and removing it.
//
// As the setup, the window drives novos-setupd serve (Wizard). The launch parameter
// "flow" picks install (default), update or remove; "setup": "reopened" marks the launch
// by the service after an install restarted surface-manager.
//
// With startSlide set (preview-on-tv.sh), it shows every screen as a debug slide instead,
// visual only, with the states drawn on the boards:
//   Left / Right, Page up / down (channel keys)   previous or next slide
//   Back                                          close
// The preview script switches slides from the Mac by writing a slide id into
// /tmp/novos-setup-slide, which the window reads a few times a second.
//
// For tests from the Mac, the setup also takes keys from /tmp/novos-setup-keys: a line
// "<serial> <key>" (ok, back, left, right, up, down) is pressed once per new serial.
StarfishSystemUIWindow {
    id: rootWindow
    objectName: "starfishSystemUIWindow"

    property string startSlide: ""
    readonly property bool slides: startSlide !== ""
    property string controlFile: "/tmp/novos-setup-slide"
    property string keysFile: "/tmp/novos-setup-keys"

    function leave() {
        if (wizardLoader.item) wizardLoader.item.finish();
        rootWindow.exit();
    }

    Connections {
        target: rootWindow.lifeCycleStatus
        onLaunch: {
            webOSShell.setWindowProperty("_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
            var params = payload && payload.params ? payload.params : {};
            setup.flow = params.flow || "install";
            setup.reopened = params.setup === "reopened";
            setup.launched = true;
            rootWindow.show();
            setup.forceActiveFocus();
        }
        onClose: rootWindow.exit()
    }

    FocusScope {
        id: setup
        anchors.fill: parent
        focus: true

        readonly property real unit: Math.min(width / 1920, height / 1080)
        property string flow: "install"
        property bool reopened: false
        property bool launched: false

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        // ---- the setup ------------------------------------------------------------------
        Loader {
            id: wizardLoader
            anchors.fill: parent
            active: !rootWindow.slides && setup.launched
            sourceComponent: Wizard {
                unit: setup.unit
                flow: setup.flow
                reopened: setup.reopened
                onClose: rootWindow.leave()
            }
        }

        // ---- debug slides ---------------------------------------------------------------
        property int slide: Math.max(0, Slides.indexOf(rootWindow.startSlide))
        readonly property var current: Slides.list[slide]
        property string lastControl: ""

        function go(index) {
            slide = (index + Slides.list.length) % Slides.list.length;
        }

        Loader {
            anchors.fill: parent
            active: rootWindow.slides
            sourceComponent: Item {
                SetupStage {
                    anchors.fill: parent
                    unit: setup.unit
                    slideId: setup.current.id
                }

                DebugBadge {
                    x: 40 * setup.unit
                    y: parent.height - height - 40 * setup.unit
                    unit: setup.unit
                    label: (setup.slide + 1) + " / " + Slides.list.length + "  ·  " + setup.current.board
                }
            }
        }

        Keys.onPressed: {
            if (!rootWindow.slides) {
                if (wizardLoader.item && wizardLoader.item.handleKey(event.key)) event.accepted = true;
                return;
            }
            if (Remote.isBack(event.key)) {
                rootWindow.exit();
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown || event.key === Qt.Key_ChannelDown) {
                go(slide + 1);
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp || event.key === Qt.Key_ChannelUp) {
                go(slide - 1);
            } else {
                return;
            }
            event.accepted = true;
        }

        property string lastKey: ""
        property bool keysRead: false
        readonly property var keyNames: ({ ok: Qt.Key_Return, back: Qt.Key_Escape, left: Qt.Key_Left,
                                           right: Qt.Key_Right, up: Qt.Key_Up, down: Qt.Key_Down })

        Timer {
            interval: 250
            repeat: true
            running: !rootWindow.slides && wizardLoader.item !== null
            onTriggered: {
                var line = "";
                try {
                    var request = new XMLHttpRequest();
                    request.open("GET", "file://" + rootWindow.keysFile, false);
                    request.send();
                    line = String(request.responseText || "").trim();
                } catch (error) {
                    return;
                }
                // What the file holds at the first read is left over from an earlier run.
                if (!setup.keysRead) {
                    setup.keysRead = true;
                    setup.lastKey = line;
                    return;
                }
                if (line === "" || line === setup.lastKey) return;
                setup.lastKey = line;
                var key = setup.keyNames[line.split(" ")[1]];
                if (key !== undefined) wizardLoader.item.handleKey(key);
            }
        }

        Timer {
            interval: 250
            repeat: true
            running: rootWindow.slides
            onTriggered: {
                var wanted = "";
                try {
                    var request = new XMLHttpRequest();
                    request.open("GET", "file://" + rootWindow.controlFile, false);
                    request.send();
                    wanted = String(request.responseText || "").trim();
                } catch (error) {
                    return;
                }
                if (wanted === "" || wanted === setup.lastControl) return;
                setup.lastControl = wanted;
                var index = Slides.indexOf(wanted);
                if (index >= 0) setup.go(index);
            }
        }
    }
}
