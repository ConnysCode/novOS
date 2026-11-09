import QtQuick 2.12
import "."
import "ShutdownScreens.js" as ShutdownScreens

// Plays one entry of ShutdownScreens.js over the whole screen, from the picture to black.
// The overlay of LG's MasterBrand.qml shows it at power off, the settings modal as a
// preview. finished() comes once the screen is black; it then stays black.
//   "glow"  K3-Shutdown-Schein: the boot look with light and wordmark at 55 %, its light
//           breathing, then both to black.
//   "lg"    LG's logo with LG's own times from MasterBrand.qml. Only the preview draws
//           it: at power off LG's file runs unchanged for this entry.
Item {
    id: screen

    property real unit: 1
    property string screenId: ShutdownScreens.fallback
    readonly property var entry: ShutdownScreens.entry(screenId)
    readonly property string kind: entry.kind

    // How long the whole run takes, in ms, from the entry. The power service waits this long.
    readonly property int duration: kind === "lg" ? lgFade + lgShow + lgHide : entry.duration
    readonly property int hold: Math.max(0, duration - GlassStyle.shutdownInDuration -
                                            GlassStyle.shutdownOutDuration)
    readonly property bool running: glowRun.running || lgRun.running

    // LG's times in MasterBrand.qml: the black half in, then the logo in while the black
    // completes, then the logo out.
    readonly property int lgFade: 500
    readonly property int lgShow: 1000
    readonly property int lgHide: 1500
    // LG's logo files next to its MasterBrand.qml, never part of novOS.
    readonly property string lgLogo: "file:///usr/lib/qml/MasterBrand/LG_logo_" +
                                     (unit >= 2 ? "4k" : "2k") + ".png"

    property real cover: 0      // the black over the picture
    property real look: 0       // light and wordmark, or LG's logo

    signal finished()

    function play() {
        stop();
        if (kind === "lg") lgRun.start();
        else glowRun.start();
    }

    function stop() {
        glowRun.stop();
        lgRun.stop();
        cover = 0;
        look = 0;
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: screen.cover
    }

    Item {
        anchors.fill: parent
        visible: screen.kind === "glow"
        opacity: screen.look

        BootGlow {
            anchors.fill: parent
            strength: GlassStyle.shutdownDim
            pulsing: screen.running
        }

        // Empty: the boot screen's bar has its place here, so the wordmark stands where it
        // stands when starting. Switching off shows no bar.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((screen.height - height) / 2)
            spacing: 28 * screen.unit

            Wordmark {
                anchors.horizontalCenter: parent.horizontalCenter
                unit: screen.unit
                size: 88
                opacity: GlassStyle.shutdownDim
            }

            Item {
                width: 1
                height: 6 * screen.unit
            }
        }
    }

    Image {
        anchors.centerIn: parent
        visible: screen.kind === "lg"
        source: visible ? screen.lgLogo : ""
        opacity: screen.look
    }

    SequentialAnimation {
        id: glowRun

        NumberAnimation {
            target: screen
            properties: "cover,look"
            from: 0
            to: 1
            duration: GlassStyle.shutdownInDuration
        }
        PauseAnimation { duration: screen.hold }
        NumberAnimation {
            target: screen
            property: "look"
            to: 0
            duration: GlassStyle.shutdownOutDuration
        }
        ScriptAction { script: screen.finished() }
    }

    SequentialAnimation {
        id: lgRun

        NumberAnimation { target: screen; property: "cover"; from: 0; to: 0.5; duration: screen.lgFade }
        ParallelAnimation {
            NumberAnimation { target: screen; property: "cover"; to: 1; duration: screen.lgFade }
            NumberAnimation { target: screen; property: "look"; from: 0; to: 1; duration: screen.lgShow }
        }
        NumberAnimation { target: screen; property: "look"; to: 0; duration: screen.lgHide }
        ScriptAction { script: screen.finished() }
    }
}
