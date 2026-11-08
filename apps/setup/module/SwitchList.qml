import QtQuick 2.12

// Switches in an inner card: rows of 80 px with a second line, 68 px without, 4 px apart
// in 8 px of padding. The focused row is the white focus surface. rows: [{ title,
// detail, on, focused }].
InsetCard {
    id: list

    property var rows: []
    readonly property real logicalHeight: {
        var total = 16 + 4 * Math.max(0, rows.length - 1);
        for (var i = 0; i < rows.length; ++i) total += rows[i].detail ? 80 : 68;
        return total;
    }

    height: logicalHeight * unit

    Column {
        x: 8 * list.unit
        y: 8 * list.unit
        width: parent.width - 16 * list.unit
        spacing: 4 * list.unit

        Repeater {
            model: list.rows
            Item {
                width: parent.width
                height: (modelData.detail ? 80 : 68) * list.unit

                FocusSurface {
                    anchors.fill: parent
                    visible: modelData.focused === true
                    unit: list.unit
                    radius: 26
                    animated: false
                }

                GlassRow {
                    anchors.fill: parent
                    unit: list.unit
                    titleFont: GlassStyle.rowFont
                    valueFont: GlassStyle.valueFont
                    focused: modelData.focused === true
                    title: modelData.title
                    subtitle: modelData.detail || ""
                    toggle: modelData.on === true
                }
            }
        }
    }
}
