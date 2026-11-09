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
//   "video" a video the user added: in from the picture, played for its length (at most
//           15 s), with sound if it has a sound track and sound is on, then to black.
//   "image" a picture the user added, the same way for its length.
Item {
    id: screen

    property real unit: 1
    property string screenId: ShutdownScreens.fallback
    property bool sound: true             // NovosSettings.shutdownSound
    property var own: ShutdownScreens.ownEntries()
    readonly property var entry: ShutdownScreens.entry(screenId, own)
    readonly property string kind: entry.kind

    // How long the whole run takes, in ms, from the entry. The power service waits this long.
    readonly property int duration: kind === "lg" ? lgFade + lgShow + lgHide :
                                    kind === "glow" ? entry.duration :
                                    GlassStyle.shutdownInDuration + entry.length + GlassStyle.shutdownOutDuration
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
        if (kind === "video" && video.item) video.item.play();
    }

    function stop() {
        glowRun.stop();
        lgRun.stop();
        if (video.item) video.item.stop();
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

    // The user's own picture, whole on black.
    Image {
        anchors.fill: parent
        visible: screen.kind === "image"
        source: visible ? "file://" + screen.entry.file : ""
        sourceSize: Qt.size(1920, 1080)
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        opacity: screen.look
    }

    // The user's own video; it fades in and out with the look.
    Loader {
        id: video
        anchors.fill: parent
        active: screen.kind === "video"
        opacity: screen.look
        sourceComponent: Component {
            ShutdownVideo {
                source: "file://" + screen.entry.file
                sound: screen.sound && screen.entry.sound === true
                volume: screen.look        // the sound fades with the picture
            }
        }
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
        ScriptAction {
            script: {
                if (video.item) video.item.stop();
                screen.finished();
            }
        }
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
