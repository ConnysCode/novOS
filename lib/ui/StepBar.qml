import QtQuick 2.12
import "."

// Steps of a flow as short bars: the done and the current one bright, the rest dim.
// 36 × 6 px each with 6 px between them, as in the setup's headers.
Row {
    id: bar

    property real unit: 1
    property int count: 6
    property int reached: 1                 // bars lit, the current one included

    spacing: 6 * unit

    Repeater {
        model: bar.count
        Rectangle {
            width: 36 * bar.unit
            height: 6 * bar.unit
            radius: 3 * bar.unit
            color: index < bar.reached ? "#ebffffff" : "#38ffffff"
        }
    }
}
