import QtQuick 2.12
import "."

// Progress across several stages, one segment each: levels holds the white opacity of
// every segment (0.92 done, 0.55 current, 0.18 to come), as for restarts in an update.
Row {
    id: bar

    property real unit: 1
    property var levels: [0.92, 0.55, 0.18]
    property real segmentWidth: 116
    property real segmentHeight: 6

    spacing: 8 * unit

    Repeater {
        model: bar.levels
        Rectangle {
            width: bar.segmentWidth * bar.unit
            height: bar.segmentHeight * bar.unit
            radius: height / 2
            color: Qt.rgba(1, 1, 1, modelData)
        }
    }
}
