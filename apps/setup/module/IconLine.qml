import QtQuick 2.12

// An entry with a picture: icon at the top left, title and an optional second line.
// 28 px icon with 21 / 18 px text in the change lists, 30 px with 22 / 19 in the update.
Item {
    id: line

    property real unit: 1
    property string icon: ""
    property real iconSize: 28
    property string title: ""
    property string detail: ""
    property real titleSize: 21
    property real detailSize: 18
    property real gap: 16

    height: (detail !== "" ? titleSize * 1.28 + 2 + detailSize * 1.33 : Math.max(iconSize, titleSize * 1.28)) * unit

    Image {
        width: line.iconSize * line.unit
        height: width
        source: Qt.resolvedUrl("icons/" + line.icon + ".png")
    }

    Column {
        x: (line.iconSize + line.gap) * line.unit
        width: parent.width - x
        spacing: 2 * line.unit

        Text {
            width: parent.width
            height: line.titleSize * 1.28 * line.unit
            verticalAlignment: Text.AlignVCenter
            text: line.title
            elide: Text.ElideRight
            color: GlassStyle.textPrimary
            font.family: GlassStyle.rowFont
            font.pixelSize: line.titleSize * line.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            visible: line.detail !== ""
            width: parent.width
            height: line.detailSize * 1.33 * line.unit
            verticalAlignment: Text.AlignVCenter
            text: line.detail
            elide: Text.ElideRight
            color: "#bdffffff"
            font.family: GlassStyle.valueFont
            font.pixelSize: line.detailSize * line.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }
}
