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
//   "video" a video the user added: in from the picture, its frames for its length (at
//           most 15 s) with its sound if it has one and sound is on, then to black, or cut
//           to black when the user turned the fade off.
//   "image" a picture the user added, the same way for its length.
// changes holds values of the edit page that are not stored yet; the preview shows them.
Item {
    id: screen

    property real unit: 1
    property string screenId: ShutdownScreens.fallback
    property bool sound: true             // NovosSettings.shutdownSound
    property var own: ShutdownScreens.ownEntries()
    property var changes: null
    readonly property var stored: ShutdownScreens.entry(screenId, own)
    readonly property var entry: changes ? ShutdownScreens.withChanges(stored, changes) : stored
    readonly property string kind: entry.kind
    readonly property bool ownEntry: kind === "video" || kind === "image"
    // play.wav holds the stored part; a changed part plays without sound until it is stored.
    readonly property bool withSound: kind === "video" && sound && entry.sound === true &&
                                      entry.start === stored.start && entry.length === stored.length
    readonly property int outDuration: ownEntry && entry.fade === false ? 0 : GlassStyle.shutdownOutDuration

    // How long the whole run takes, in ms, from the entry. The power service waits this long.
    readonly property int duration: kind === "lg" ? lgFade + lgShow + lgHide :
                                    kind === "glow" ? entry.duration :
                                    GlassStyle.shutdownInDuration + entry.length + outDuration
    readonly property int hold: Math.max(0, duration - GlassStyle.shutdownInDuration - outDuration)
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
    property real look: 0       // light and wordmark, LG's logo, or the user's picture

    signal finished()

    function play() {
        stop();
        if (kind === "lg") lgRun.start();
        else glowRun.start();
        if (kind === "video" && frames.item) frames.item.play();
        if (withSound && voice.item) voice.item.play();
    }

    function stop() {
        glowRun.stop();
        lgRun.stop();
        if (frames.item) frames.item.stop();
        if (voice.item) voice.item.stop();
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

    // The user's own picture, framed as chosen.
    ShutdownFraming {
        anchors.fill: parent
        visible: screen.kind === "image"
        opacity: screen.look
        zoom: screen.entry.zoom || 1
        panX: screen.entry.x || 0
        panY: screen.entry.y || 0
        mediaWidth: picture.implicitWidth || 16
        mediaHeight: picture.implicitHeight || 9

        Image {
            id: picture
            anchors.fill: parent
            source: screen.kind === "image" ? ShutdownScreens.frameUrl(screen.entry, 0) : ""
            sourceSize: Qt.size(1920, 1920)
            asynchronous: false
            smooth: true
        }
    }

    // The user's own video: its frames, and its sound fading with the picture.
    Loader {
        id: frames
        anchors.fill: parent
        active: screen.kind === "video"
        opacity: screen.look
        sourceComponent: Component {
            ShutdownFrames {
                entry: screen.entry
            }
        }
    }

    Loader {
        id: voice
        active: screen.kind === "video" && screen.entry.sound === true
        sourceComponent: Component {
            ShutdownSound {
                source: "file://" + screen.entry.soundFile
                volume: screen.look
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
            duration: screen.outDuration
        }
        ScriptAction {
            script: {
                if (frames.item) frames.item.stop();
                if (voice.item) voice.item.stop();
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
