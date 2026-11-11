import QtQuick 2.12
import "."

// Switch QWERTZ | T9 at the top right of an entry modal (K3-Tastatur-QWERTZ, -T9). The
// owner's white focus surface sits on a segment, segmentRect() gives its place. The
// chosen mode keeps a light fill of its own.
Item {
    id: modeSwitch

    property real unit: 1
    property string labelFont: ""
    property string mode: "qwertz"
    property string focusedSegment: ""   // "qwertz", "t9" or ""

    signal chosen(string choice)

    readonly property var segments: [
        { mode: "qwertz", icon: "keyboard-24", label: I18n.t("keyboard", "mode.qwertz") },
        { mode: "t9", icon: "t9-22", label: I18n.t("keyboard", "mode.t9") }
    ]

    width: segmentRow.width + 8 * unit
    height: 64 * unit

    // Position of a segment inside the switch's parent.
    function segmentRect(name) {
        var item = segmentRepeater.itemAt(name === "t9" ? 1 : 0);
        if (!item) return Qt.rect(x, y, 0, 0);
        return Qt.rect(x + segmentRow.x + item.x, y + segmentRow.y, item.width, item.height);
    }

    GlassControl {
        anchors.fill: parent
        unit: modeSwitch.unit
        radius: 32
        fill: GlassStyle.fillRest
    }

    Row {
        id: segmentRow
        x: 4 * modeSwitch.unit
        y: 4 * modeSwitch.unit
        spacing: 4 * modeSwitch.unit

        Repeater {
            id: segmentRepeater
            model: modeSwitch.segments

            Item {
                readonly property bool focused: modeSwitch.focusedSegment === modelData.mode
                readonly property bool selected: modeSwitch.mode === modelData.mode
                width: content.width + 44 * modeSwitch.unit
                height: 56 * modeSwitch.unit

                Rectangle {
                    anchors.fill: parent
                    radius: 28 * modeSwitch.unit
                    color: GlassStyle.fillStrong
                    visible: parent.selected && !parent.focused
                    antialiasing: true
                }

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 10 * modeSwitch.unit
                    opacity: parent.selected || parent.focused ? 1 : 0.78

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl("icons/" + modelData.icon + (parent.parent.focused ? "-dark" : "") + ".png")
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: parent.parent.focused ? GlassStyle.focusText : "#ffffff"
                        font.family: modeSwitch.labelFont
                        font.pixelSize: 19 * modeSwitch.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: modeSwitch.chosen(modelData.mode)
                }
            }
        }
    }
}
