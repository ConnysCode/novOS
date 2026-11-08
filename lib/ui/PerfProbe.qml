pragma Singleton
import QtQuick 2.12

// Measuring probe for the performance work (docs/performance-plan.md). It is off in every
// build; apps/novos/perf-on-tv.sh switches it on in an uploaded preview copy only.
//
// It notes three things, each as one line with the time in ms:
//   mark <name> [detail]           a point in time, e.g. the window exists, the glass has its picture
//   cost <name> <ms> [detail]      a code path that took slowCost ms or more
//   segment <phase> …               frames of a phase: count, fps, largest gap, gaps over 34/50/100 ms
// At the end of an opening the totals of every cost and count follow. The lines go to
// /tmp/novos-perf.ini, which the script reads after the run.
//
//     var started = PerfProbe.now();
//     doWork();
//     PerfProbe.cost("panel.work", started);
//
// Switched off, now() returns 0 and every call returns at once.
QtObject {
    id: probe

    readonly property bool enabled: false
    readonly property string logFile: "/tmp/novos-perf.ini"
    readonly property string scriptFile: "/tmp/novos-perf-script.txt"
    readonly property int slowCost: 8          // ms: a single cost from here on gets its own line
    readonly property int longGap: 50          // ms between two frames: listed with its phase

    property string phase: ""
    property real phaseStart: 0
    property var frames: null                  // counters of the running phase
    property var costs: ({})
    property var counts: ({})
    property var lines: null
    property var out: null

    function now() {
        return enabled ? Date.now() : 0;
    }

    function note(text) {
        if (lines === null) {
            out = Qt.createQmlObject('import Qt.labs.settings 1.0; Settings { fileName: "' + logFile +
                                     '"; property string log: "" }', probe);
            // The window may be built anew for every opening: keep what earlier ones wrote.
            lines = out.log !== "" ? out.log.split("\n") : [];
        }
        lines.push(Date.now() + " " + text);
        flushTimer.restart();
    }

    function mark(name, detail) {
        if (!enabled) return 0;
        note("mark " + name + (detail !== undefined && detail !== "" ? " " + detail : ""));
        return Date.now();
    }

    function cost(name, since, detail) {
        if (!enabled || !since) return;
        var ms = Date.now() - since;
        var entry = costs[name];
        if (!entry) entry = costs[name] = { n: 0, total: 0, max: 0 };
        entry.n++;
        entry.total += ms;
        if (ms > entry.max) entry.max = ms;
        if (ms >= slowCost) note("cost " + name + " " + ms + (detail !== undefined ? " " + detail : ""));
    }

    function count(name, amount) {
        if (!enabled) return;
        counts[name] = (counts[name] || 0) + (amount === undefined ? 1 : amount);
    }

    // One animation tick of PerfMeter, gap in ms since the one before.
    function frame(gap) {
        if (!enabled || frames === null) return;
        frames.n++;
        if (gap > frames.max) frames.max = gap;
        if (gap > 34) frames.over34++;
        if (gap > 50) frames.over50++;
        if (gap > 100) frames.over100++;
        if (gap >= longGap) note("gap " + gap + " " + phase);
    }

    function beginPhase(name) {
        if (!enabled) return;
        endPhase();
        phase = name;
        phaseStart = Date.now();
        frames = { n: 0, max: 0, over34: 0, over50: 0, over100: 0 };
        note("phase " + name);
    }

    function endPhase() {
        if (frames === null) return;
        var duration = Math.max(1, Date.now() - phaseStart);
        note("segment " + phase + " ms=" + duration + " frames=" + frames.n +
             " fps=" + (frames.n * 1000 / duration).toFixed(1) + " maxgap=" + frames.max +
             " over34=" + frames.over34 + " over50=" + frames.over50 + " over100=" + frames.over100);
        frames = null;
    }

    // End of an opening: the phase and every total, then the file.
    function finish(reason) {
        if (!enabled) return;
        endPhase();
        for (var name in costs) {
            var entry = costs[name];
            note("total " + name + " n=" + entry.n + " sum=" + entry.total + " max=" + entry.max +
                 " avg=" + (entry.total / entry.n).toFixed(1));
        }
        for (var counted in counts) note("count " + counted + " " + counts[counted]);
        costs = {};
        counts = {};
        note("end " + reason);
        flush();
    }

    function flush() {
        if (out !== null) out.log = lines.join("\n");
    }

    // The steps PerfMeter runs, one per line; empty lines and # comments are skipped.
    function loadScript() {
        if (!enabled) return [];
        try {
            var request = new XMLHttpRequest();
            request.open("GET", "file://" + scriptFile, false);
            request.send();
            var steps = [];
            var all = request.responseText.split("\n");
            for (var i = 0; i < all.length; i++) {
                var line = all[i].trim();
                if (line !== "" && line.charAt(0) !== "#") steps.push(line);
            }
            return steps;
        } catch (error) {
            return [];
        }
    }

    property Timer flushTimer: Timer {
        interval: 200
        onTriggered: probe.flush()
    }
}
