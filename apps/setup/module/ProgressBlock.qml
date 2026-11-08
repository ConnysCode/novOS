import QtQuick 2.12

// What runs, how far, and how long it still takes: label and percentage on one line,
// a 12 px bar 12 px below, the remaining time 10 px under it. 94 px high.
Item {
    id: block

    property real unit: 1
    property string label: ""
    property real value: 0
    property string remaining: ""

    height: 94 * unit

    Text {
        anchors.baseline: percent.baseline
        text: block.label
        color: "#d1ffffff"
        font.family: GlassStyle.valueFont
        font.pixelSize: 20 * block.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Text {
        id: percent
        x: parent.width - width
        height: 36 * block.unit
        verticalAlignment: Text.AlignVCenter
        text: Math.round(block.value * 100) + " %"
        color: GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: 32 * block.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    ProgressBar {
        y: 48 * block.unit
        width: parent.width
        unit: block.unit
        value: block.value
    }

    Text {
        y: 70 * block.unit
        text: block.remaining
        color: GlassStyle.textSecondary
        font.family: GlassStyle.valueFont
        font.pixelSize: 18 * block.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
