import QtQuick 2.12
import SystemUIComponent 1.0
import "module"
import "module/Slides.js" as Slides

// The setup of novOS: installing, updating and removing it. For now a debug build that
// shows every screen as a slide, visual only, with the states drawn on the boards.
//
//   Left / Right, Page up / down (channel keys)   previous or next slide
//   Back                                          close
//
// The preview script switches slides from the Mac through a control file: it writes a
// slide id into /tmp/novos-setup-slide, the window reads it a few times a second.
StarfishSystemUIWindow {
    id: rootWindow
    objectName: "starfishSystemUIWindow"

    property string startSlide: ""
    property bool debug: true
    property string controlFile: "/tmp/novos-setup-slide"

    Connections {
        target: rootWindow.lifeCycleStatus
        onLaunch: {
            webOSShell.setWindowProperty("_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
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
        property int slide: Math.max(0, Slides.indexOf(rootWindow.startSlide))
        readonly property var current: Slides.list[slide]
        property string lastControl: ""

        function go(index) {
            slide = (index + Slides.list.length) % Slides.list.length;
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        SetupStage {
            anchors.fill: parent
            unit: setup.unit
            slideId: setup.current.id
        }

        DebugBadge {
            visible: rootWindow.debug
            x: 40 * setup.unit
            y: setup.height - height - 40 * setup.unit
            unit: setup.unit
            label: (setup.slide + 1) + " / " + Slides.list.length + "  ·  " + setup.current.board
        }

        Keys.onPressed: {
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

        Timer {
            interval: 250
            repeat: true
            running: rootWindow.debug
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
