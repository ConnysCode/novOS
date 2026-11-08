import QtQuick 2.12

// The scrolling app list of the settings panel. A fixed pool of rows, so that a new
// list only changes their text. The panel owns focus and scroll position; its focus
// surface glides behind this list.
Item {
    id: page

    property real unit: 1
    property string rowFont: ""
    property string valueFont: ""
    property var apps: []
    property int focusedIndex: -1
    property int scroll: 0
    property int limit: 0
    property int pitch: 100
    property int duration: GlassStyle.focusDuration
    property var curve: GlassStyle.curve
    readonly property int maxApps: 60

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
            model: page.maxApps

            Item {
                id: appRow
                readonly property var app: page.apps[index] || ({ title: "", detail: "", iconPath: "" })
                readonly property bool focused: page.focusedIndex === index
                visible: index < page.apps.length
                x: 28 * page.unit
                y: index * page.pitch * page.unit
                width: 544 * page.unit
                height: 96 * page.unit
                scale: focused ? GlassStyle.focusScale : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: page.duration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: page.curve
                    }
                }

                AppIcon {
                    x: 20 * page.unit
                    y: 12 * page.unit
                    width: 72 * page.unit
                    height: 72 * page.unit
                    cornerRadius: 18 * page.unit
                    source: appRow.app.iconPath
                    focused: appRow.focused
                }

                Text {
                    x: 108 * page.unit
                    y: (appRow.app.detail === "" ? 34 : 22) * page.unit
                    width: 382 * page.unit
                    height: 28 * page.unit
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: appRow.app.title
                    color: appRow.focused ? GlassStyle.focusText : "#ffffff"
                    font.family: page.rowFont
                    font.pixelSize: 22 * page.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    x: 108 * page.unit
                    y: 52 * page.unit
                    width: 382 * page.unit
                    height: 22 * page.unit
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: appRow.app.detail
                    color: appRow.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                    font.family: page.valueFont
                    font.pixelSize: 17 * page.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Image {
                    x: 506 * page.unit
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(appRow.focused ? "icons/chevron-18-dark.png" : "icons/chevron-18.png")
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.rowClicked(index)
                }
            }
        }
    }
}
