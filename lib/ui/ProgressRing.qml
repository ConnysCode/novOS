import QtQuick 2.12
import "."

// Small round progress: a 22 % track and a white arc with round ends that starts at
// twelve o'clock and runs clockwise. 30 px with a 3.5 px line in the setup's status pill.
Canvas {
    id: ring

    property real unit: 1
    property real size: 30
    property real lineWidth: 3.5
    property real value: 0

    width: size * unit
    height: size * unit
    onValueChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var line = lineWidth * unit;
        var radius = (width - line) / 2 - 0.5 * unit;
        ctx.lineWidth = line;
        ctx.strokeStyle = "rgba(255, 255, 255, 0.22)";
        ctx.beginPath();
        ctx.arc(width / 2, height / 2, radius, 0, 2 * Math.PI);
        ctx.stroke();
        if (value <= 0) return;
        ctx.strokeStyle = "#ffffff";
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.arc(width / 2, height / 2, radius, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, value));
        ctx.stroke();
    }
}
