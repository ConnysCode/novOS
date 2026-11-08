import QtQuick 2.12
import "."

// One step of a check or progress list, 60 px: state mark, label and an optional value
// at the right. A pending step steps back to 72 %; an error colours its value.
Item {
    id: row

    property real unit: 1
    property string status: "pending"
    property string label: ""
    property string value: ""

    height: 60 * unit
    opacity: status === "pending" ? 0.72 : 1

    StatusMark {
        id: mark
        x: 20 * row.unit
        anchors.verticalCenter: parent.verticalCenter
        unit: row.unit
        status: row.status
    }

    Text {
        x: mark.x + mark.width + 18 * row.unit
        width: valueText.x - x - 18 * row.unit
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        elide: Text.ElideRight
        color: GlassStyle.textPrimary
        font.family: GlassStyle.rowFont
        font.pixelSize: 22 * row.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Text {
        id: valueText
        x: row.width - width - 20 * row.unit
        anchors.verticalCenter: parent.verticalCenter
        text: row.value
        color: row.status === "error" ? GlassStyle.danger : GlassStyle.textSecondary
        font.family: GlassStyle.valueFont
        font.pixelSize: 19 * row.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
