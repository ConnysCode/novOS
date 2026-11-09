import QtQuick 2.12
import "."

// What is new in a version (K3-NovUpdate-*): one dot per entry with a title and a line
// below. The list is one block the focus enters, so that it can be read with the remote;
// on the focus surface the texts turn dark.
Item {
    id: list

    property real unit: 1
    property string titleFont: ""
    property string valueFont: ""
    property var items: []          // [{ title, text }]
    property bool focused: false

    readonly property real padX: 24
    readonly property real padY: 20

    Column {
        x: list.padX * list.unit
        y: list.padY * list.unit
        width: list.width - 2 * list.padX * list.unit
        spacing: 16 * list.unit

        Repeater {
            model: list.items
            Item {
                width: parent.width
                height: entry.height

                Rectangle {
                    y: 11 * list.unit
                    width: 8 * list.unit
                    height: width
                    radius: width / 2
                    color: list.focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
                }

                Column {
                    id: entry
                    x: 26 * list.unit
                    width: parent.width - x
                    spacing: 2 * list.unit

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: modelData.title || ""
                        color: list.focused ? GlassStyle.focusText : GlassStyle.textPrimary
                        font.family: list.titleFont
                        font.pixelSize: 21 * list.unit
                        lineHeight: 28 * list.unit
                        lineHeightMode: Text.FixedHeight
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                        text: modelData.text || ""
                        color: list.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                        font.family: list.valueFont
                        font.pixelSize: 18 * list.unit
                        lineHeight: 26 * list.unit
                        lineHeightMode: Text.FixedHeight
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }
            }
        }
    }
}
