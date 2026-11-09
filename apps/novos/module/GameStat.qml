import QtQuick 2.12
import "."

// One live value of the game bar (K3-Spiel-A-HUD): a capital label, below it the value
// in 34 px with its unit in small type on the same baseline. It takes no focus. Its width grows with
// the value, never below minWidth, so the bar does not jump while a number changes.
Item {
    id: stat

    property real unit: 1
    property string label: ""
    property string value: ""
    property string suffix: ""              // unit after the value, for example "fps"
    property real minWidth: 128

    readonly property real gap: 8 * unit

    width: Math.max(minWidth * unit, labelRow.width, valueRow.width)
    height: labelRow.height + gap + valueText.height

    Row {
        id: labelRow
        spacing: stat.gap

        SectionTitle {
            unit: stat.unit
            text: stat.label
            color: GlassStyle.textSecondary
        }
    }

    Row {
        id: valueRow
        y: labelRow.height + stat.gap
        spacing: 6 * stat.unit

        Text {
            id: valueText
            text: stat.value
            color: GlassStyle.textPrimary
            font.family: GlassStyle.titleFont
            font.pixelSize: GlassStyle.statSize * stat.unit
            font.letterSpacing: -0.02 * GlassStyle.statSize * stat.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            anchors.baseline: valueText.baseline
            visible: stat.suffix !== ""
            text: stat.suffix
            color: GlassStyle.textSecondary
            font.family: GlassStyle.rowFont
            font.pixelSize: GlassStyle.statUnitSize * stat.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }
}
