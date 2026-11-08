import QtQuick 2.12

// The scrolling language list. The panel owns focus and scroll position; its focus
// surface glides behind this list, like on the apps page.
Item {
    id: page

    property real unit: 1
    property string rowFont: ""
    property string valueFont: ""
    property var languages: []
    property string selected: ""
    property int focusedIndex: -1
    property int scroll: 0
    property int limit: 0
    property int pitch: 72
    property int duration: GlassStyle.focusDuration
    property var curve: GlassStyle.curve

    signal rowClicked(int row)

    layer.enabled: true
    layer.effect: EdgeFade {
        topFade: 56 / page.height * page.unit
        bottomFade: 96 / page.height * page.unit
        bottomGap: 8 / page.height * page.unit
        topAmount: page.scroll > 0 ? 1 : 0
        bottomAmount: page.scroll < page.limit ? 1 : 0
    }

    Item {
        width: parent.width
        y: -page.scroll * page.unit

        Behavior on y {
            NumberAnimation {
                duration: page.duration
                easing.type: Easing.Bezier
                easing.bezierCurve: page.curve
            }
        }

        Repeater {
            model: page.languages

            Item {
                id: languageRow
                readonly property bool focused: page.focusedIndex === index
                x: 28 * page.unit
                y: index * page.pitch * page.unit
                width: 544 * page.unit
                height: 68 * page.unit

                Text {
                    x: 20 * page.unit
                    y: 8 * page.unit
                    height: 28 * page.unit
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                    color: languageRow.focused ? GlassStyle.focusText : "#ffffff"
                    font.family: page.rowFont
                    font.pixelSize: 22 * page.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    x: 20 * page.unit
                    y: 37 * page.unit
                    height: 21 * page.unit
                    verticalAlignment: Text.AlignVCenter
                    visible: modelData.german !== modelData.name
                    text: modelData.german
                    color: languageRow.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                    font.family: page.valueFont
                    font.pixelSize: 17 * page.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Image {
                    x: parent.width - 44 * page.unit
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.selected === modelData.code
                    source: Qt.resolvedUrl(languageRow.focused ? "icons/check-24-dark.png" : "icons/check-24.png")
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.rowClicked(index)
                }
            }
        }
    }
}
