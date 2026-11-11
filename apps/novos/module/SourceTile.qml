import QtQuick 2.12
import "."

// One tile of the source picker. The white focus surface belongs to the picker, so a
// focused tile only drops its own fill. It reads everything from a plain object.
Item {
    id: tile

    property real unit: 1
    property string titleFont: ""
    property string valueFont: ""
    property var source: ({ title: "", detail: "", icon: "source-box" })
    property bool focused: false
    property bool busy: false
    property string busyText: ""

    opacity: source.disabled === true ? 0.4 : 1
    scale: focused ? GlassStyle.focusScale : 1

    Behavior on scale {
        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
    }

    GlassControl {
        anchors.fill: parent
        visible: !tile.focused
        unit: tile.unit
        radius: 32
        fill: GlassStyle.fillRest
    }

    Image {
        x: 20 * tile.unit
        y: 20 * tile.unit
        visible: !tile.busy && tile.source.isApp !== true
        opacity: tile.source.off === true ? GlassStyle.iconDimmed : 1
        source: tile.source.isApp ? "" : Qt.resolvedUrl("icons/" + tile.source.icon + (tile.focused ? "-dark.png" : ".png"))
    }

    // An app in the row of sources carries its own icon.
    AppIcon {
        x: 20 * tile.unit
        y: 20 * tile.unit
        width: 56 * tile.unit
        height: 56 * tile.unit
        cornerRadius: 14 * tile.unit
        focused: tile.focused
        visible: !tile.busy && tile.source.isApp === true
        source: tile.source.isApp ? tile.source.iconPath : ""
    }

    Spinner {
        x: 22 * tile.unit
        y: 22 * tile.unit
        size: 36 * tile.unit
        lineWidth: 4 * tile.unit
        running: tile.busy
        visible: tile.busy
        dark: tile.focused
    }

    // A badge marks the running source.
    GlassControl {
        x: parent.width - width - 20 * tile.unit
        y: 20 * tile.unit
        width: runningRow.width + 22 * tile.unit
        height: 30 * tile.unit
        visible: tile.source.running === true && !tile.busy
        unit: tile.unit
        radius: 15
        fill: tile.focused ? GlassStyle.fillOnFocus : GlassStyle.fillActiveStrong

        // The row spans the badge's full height; the Row only sets x, so the text
        // can sit by its own baseline.
        Row {
            id: runningRow
            x: 10 * tile.unit
            height: parent.height
            spacing: 6 * tile.unit

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8 * tile.unit
                height: width
                radius: width / 2
                color: GlassStyle.accent
            }

            // Centred on the capitals, not on the line box: on the TV, Qt's line box
            // put the word about 5 px above the badge's centre. Inter's cap height is
            // 1490/2048 of the size.
            Text {
                y: Math.round(parent.height / 2 + font.pixelSize * 1490 / 2048 / 2 - baselineOffset)
                text: I18n.t("source", "badge.running")
                color: tile.focused ? GlassStyle.focusText : "#ffffff"
                font.family: tile.titleFont
                font.pixelSize: 16 * tile.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }
    }

    Text {
        x: 20 * tile.unit
        y: 113 * tile.unit
        width: parent.width - 40 * tile.unit
        height: 28 * tile.unit
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: tile.source.title
        color: tile.focused ? GlassStyle.focusText : "#ffffff"
        font.family: tile.titleFont
        font.pixelSize: 22 * tile.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Text {
        x: 20 * tile.unit
        y: 144 * tile.unit
        width: parent.width - 40 * tile.unit
        height: 22 * tile.unit
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: tile.busy ? tile.busyText : tile.source.detail
        color: tile.focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
        font.family: tile.valueFont
        font.pixelSize: 17 * tile.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
