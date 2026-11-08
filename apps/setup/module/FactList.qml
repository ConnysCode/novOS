import QtQuick 2.12

// Facts as label and value in an inner card, 56 px rows without lines between them:
// label quiet at the left, value at the right. rows: [{ label, value }].
InsetCard {
    id: list

    property var rows: []
    property real rowGap: 2
    readonly property real logicalHeight: 16 + 56 * rows.length + rowGap * Math.max(0, rows.length - 1)

    height: logicalHeight * unit

    Column {
        x: 8 * list.unit
        y: 8 * list.unit
        width: parent.width - 16 * list.unit
        spacing: list.rowGap * list.unit

        Repeater {
            model: list.rows
            Item {
                width: parent.width
                height: 56 * list.unit

                Text {
                    x: 20 * list.unit
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: GlassStyle.textSecondary
                    font.family: GlassStyle.valueFont
                    font.pixelSize: 22 * list.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    x: parent.width - width - 20 * list.unit
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.value
                    color: GlassStyle.textPrimary
                    font.family: GlassStyle.rowFont
                    font.pixelSize: 22 * list.unit
                    font.hintingPreference: Font.PreferNoHinting
                }
            }
        }
    }
}
