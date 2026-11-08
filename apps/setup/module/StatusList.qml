import QtQuick 2.12

// Steps with their state in an inner card: rows of 60 px, 2 px apart, 8 px above and
// below. rows: [{ status, label, value }]. Its height in logical px is 16 + 62 n - 2.
InsetCard {
    id: list

    property var rows: []
    readonly property real logicalHeight: 14 + 62 * rows.length

    height: logicalHeight * unit

    Column {
        y: 8 * list.unit
        width: parent.width
        spacing: 2 * list.unit

        Repeater {
            model: list.rows
            StatusRow {
                width: parent.width
                unit: list.unit
                status: modelData.status
                label: modelData.label
                value: modelData.value || ""
            }
        }
    }
}
