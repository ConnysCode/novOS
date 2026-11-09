import QtQuick 2.12
import "."
import "ShutdownScreens.js" as ShutdownScreens

// A video the user added, played from its frames at their rate (15 a second), framed like
// the screen frames it. Two pictures take turns: one shows, the other loads the next frame
// in the background, so decoding never holds up a frame (225 frames in 1280 x 720 played
// without one late on the TV). Without play() it shows the first frame of the part.
Item {
    id: player

    property var entry: ({})
    readonly property int first: ShutdownScreens.frameAt(entry, entry.start || 0)
    readonly property int count: Math.max(1, ShutdownScreens.frameAt(entry, entry.length || 0))
    property int shown: first
    property int front: 0
    property real started: 0
    readonly property bool playing: clock.running

    function frame(n) { return ShutdownScreens.frameUrl(entry, Math.min(n, first + count - 1)); }

    function play() {
        clock.stop();
        shown = first;
        front = 0;
        one.source = frame(first);
        two.source = frame(first + 1);
        started = Date.now();
        clock.start();
    }

    function stop() {
        clock.stop();
    }

    onFirstChanged: if (!clock.running) one.source = frame(first)
    Component.onCompleted: one.source = frame(first)

    ShutdownFraming {
        anchors.fill: parent
        zoom: player.entry.zoom || 1
        panX: player.entry.x || 0
        panY: player.entry.y || 0
        mediaWidth: one.implicitWidth || 16
        mediaHeight: one.implicitHeight || 9

        Image {
            id: one
            anchors.fill: parent
            visible: player.front === 0
            asynchronous: player.playing
            cache: false
            smooth: true
        }

        Image {
            id: two
            anchors.fill: parent
            visible: player.front === 1
            asynchronous: true
            cache: false
            smooth: true
        }
    }

    // Shows the next frame once it is due and loaded, and starts loading the one after.
    Timer {
        id: clock
        interval: 16
        repeat: true
        onTriggered: {
            var due = player.first + Math.floor((Date.now() - player.started) * (player.entry.fps || 15) / 1000);
            if (player.shown >= player.first + player.count - 1) return;
            var waiting = player.front === 0 ? two : one;
            if (due > player.shown && waiting.status === Image.Ready) {
                player.front = player.front === 0 ? 1 : 0;
                player.shown += 1;
                (player.front === 0 ? two : one).source = player.frame(Math.max(due, player.shown) + 1);
            }
        }
    }
}
