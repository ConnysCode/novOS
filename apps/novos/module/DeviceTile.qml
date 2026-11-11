import QtQuick 2.12
import "."

// One device on the hub's shelf, after K3-Home-A: 224 × 184, radius 32, icon top left,
// switch top right when OK switches the device, name and state below. Brighter when
// the device is on, the white focus surface when focused.
Item {
    id: tile

    property real unit: 1
    property bool focused: false
    property string kind: "device"
    property string name: ""
    property string stateLine: ""
    property bool active: false
    property bool reachable: true
    property bool hasSwitch: false
    property string titleFamily: ""
    property string rowFamily: ""
    readonly property var standardCurve: GlassStyle.curve

    width: 224 * unit
    height: 184 * unit
    scale: focused ? GlassStyle.focusScale : 1
    opacity: reachable ? 1 : GlassStyle.iconDimmed

    Behavior on scale {
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: tile.standardCurve }
    }

    Rectangle {
        anchors.fill: parent
        radius: 32 * tile.unit
        color: tile.focused ? GlassStyle.focusFill : (tile.active ? GlassStyle.fillSelected : GlassStyle.fillSoft)

        Behavior on color { ColorAnimation { duration: 180 } }
    }

    BorderImage {
        anchors.fill: parent
        visible: !tile.focused
        opacity: Math.min(1, GlassStyle.edgeGain)
        source: Qt.resolvedUrl("icons/edge-32.png")
        border { left: 33; top: 33; right: 33; bottom: 33 }
    }

    Image {
        x: 20 * tile.unit
        y: 20 * tile.unit
        width: 36 * tile.unit
        height: 36 * tile.unit
        opacity: tile.focused || tile.active ? 1 : GlassStyle.iconQuiet
        source: Qt.resolvedUrl("icons/device-" + tile.kind + (tile.focused ? "-dark.png" : ".png"))
    }

    // The switch: 64 × 36 with a white knob, blue when on.
    GlassSwitch {
        visible: tile.hasSwitch
        x: parent.width - width - 20 * tile.unit
        y: 20 * tile.unit
        unit: tile.unit
        on: tile.active
    }

    Column {
        x: 20 * tile.unit
        width: parent.width - 40 * tile.unit
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18 * tile.unit
        spacing: 3 * tile.unit

        Text {
            width: parent.width
            text: tile.name
            elide: Text.ElideRight
            color: tile.focused ? GlassStyle.focusText : "#ffffff"
            font.family: tile.titleFamily
            font.pixelSize: 22 * tile.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            width: parent.width
            text: tile.stateLine
            elide: Text.ElideRight
            color: tile.focused ? GlassStyle.focusSecondary : (tile.active ? GlassStyle.textSecondary : GlassStyle.textFaint)
            font.family: tile.rowFamily
            font.pixelSize: 17 * tile.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }
}
