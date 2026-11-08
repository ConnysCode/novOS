import QtQuick 2.12
import "."

// The window side of PerfProbe: counts animation ticks, so that a blocked GUI thread shows
// as a gap between two frames, and runs the steps of the script file once `start` turns
// true. Does nothing while the probe is off.
//
// target is the window's key handling: pressKey(key, autoRepeat), releaseKey(key), and
// optionally bump() (rebuild everything that follows the settings, without writing) and
// close().
//
// Steps, one per line (times in ms):
//   phase <name>                   starts a phase of its own in the frame statistics
//   wait <ms>
//   key <name> [ms]                press and release, then wait ms (default 400)
//   hold <name> <ms> [repeat]      held key: auto-repeat every repeat ms (default 100)
//   bump <count> <ms>              bump() count times, ms apart
//   gc                             a full garbage collection, timed as cost "gc"
//   call <function>                calls target.<function>() without arguments, timed
//   close
// Key names: up, down, left, right, ok, back.
Item {
    id: meter

    property var target: null
    property bool start: false

    readonly property int keyGap: 400
    readonly property int repeatGap: 100

    property real tick: 0
    property real lastTick: 0
    property var steps: []
    property int step: 0
    property bool started: false

    // Hold and bump run in several turns.
    property string heldKey: ""
    property real holdUntil: 0
    property int bumpsLeft: 0

    width: 0
    height: 0

    NumberAnimation on tick {
        from: 0
        to: 1
        duration: 1000
        loops: Animation.Infinite
        running: PerfProbe.enabled
    }

    onTickChanged: {
        var time = Date.now();
        if (lastTick > 0) PerfProbe.frame(time - lastTick);
        lastTick = time;
    }

    onStartChanged: {
        if (!start || started || !PerfProbe.enabled) return;
        started = true;
        steps = PerfProbe.loadScript();
        PerfProbe.mark("script", steps.length + " steps");
        next();
    }

    function keyOf(name) {
        var keys = { up: Qt.Key_Up, down: Qt.Key_Down, left: Qt.Key_Left, right: Qt.Key_Right,
                     ok: Qt.Key_Return, back: Qt.Key_Escape };
        return keys[name] !== undefined ? keys[name] : -1;
    }

    function after(ms) {
        runner.interval = Math.max(1, ms);
        runner.restart();
    }

    function next() {
        if (!target) return;
        if (step >= steps.length) {
            PerfProbe.finish("script");
            return;
        }
        var words = steps[step++].split(/\s+/);
        var command = words[0];
        if (command === "phase") {
            PerfProbe.beginPhase(words[1]);
            after(1);
        } else if (command === "wait") {
            after(Number(words[1]));
        } else if (command === "key") {
            target.pressKey(keyOf(words[1]), false);
            target.releaseKey(keyOf(words[1]));
            after(words.length > 2 ? Number(words[2]) : keyGap);
        } else if (command === "hold") {
            heldKey = words[1];
            holdUntil = Date.now() + Number(words[2]);
            repeater.interval = words.length > 3 ? Number(words[3]) : repeatGap;
            target.pressKey(keyOf(heldKey), false);
            repeater.restart();
        } else if (command === "bump") {
            bumpsLeft = Number(words[1]);
            bumper.interval = Number(words[2]);
            bumper.restart();
        } else if (command === "gc") {
            var started = PerfProbe.now();
            gc();
            PerfProbe.cost("gc", started);
            after(1);
        } else if (command === "call") {
            var begun = PerfProbe.now();
            if (typeof target[words[1]] === "function") target[words[1]]();
            PerfProbe.cost("call." + words[1], begun);
            after(1);
        } else if (command === "close") {
            if (target.close) target.close();
        } else {
            PerfProbe.mark("script.unknown", command);
            after(1);
        }
    }

    Timer {
        id: runner
        onTriggered: meter.next()
    }

    Timer {
        id: repeater
        repeat: true
        onTriggered: {
            if (Date.now() < meter.holdUntil) {
                meter.target.pressKey(meter.keyOf(meter.heldKey), true);
                return;
            }
            stop();
            meter.target.releaseKey(meter.keyOf(meter.heldKey));
            meter.after(meter.keyGap);
        }
    }

    Timer {
        id: bumper
        repeat: true
        onTriggered: {
            if (meter.bumpsLeft <= 0) {
                stop();
                meter.after(1);
                return;
            }
            meter.bumpsLeft--;
            meter.target.bump();
        }
    }
}
