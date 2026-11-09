import QtQuick 2.12

// A picture framed the way the power-off screen shows it: whole at zoom 1, larger with
// zoom, and moved by panX, panY (-1 … 1) within the part that does not fit. The tile, the
// edit page and the screen itself use it, so all three show the same part. The children
// fill the picture; mediaWidth and mediaHeight give its proportions.
Item {
    id: framing

    property real zoom: 1
    property real panX: 0
    property real panY: 0
    property real mediaWidth: 16
    property real mediaHeight: 9
    default property alias content: media.data

    readonly property real fit: Math.min(width / Math.max(1, mediaWidth), height / Math.max(1, mediaHeight))
    readonly property real shownWidth: mediaWidth * fit * zoom
    readonly property real shownHeight: mediaHeight * fit * zoom
    // Whether moving sideways or up and down changes anything.
    readonly property bool movesX: shownWidth > width + 0.5
    readonly property bool movesY: shownHeight > height + 0.5

    clip: true

    Item {
        id: media
        width: framing.shownWidth
        height: framing.shownHeight
        x: (framing.width - width) / 2 - framing.panX * Math.max(0, width - framing.width) / 2
        y: (framing.height - height) / 2 - framing.panY * Math.max(0, height - framing.height) / 2
    }
}
