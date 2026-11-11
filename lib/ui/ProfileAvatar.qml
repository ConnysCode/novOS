import QtQuick 2.12
import "."

// A profile's avatar as LG keeps it: a circle in the profile colour with one initial, no
// photo. The initial is dark on the light colours (GlassStyle.profileLightColors). Size is
// logical (32 in rows of the panel, 40 in profile lists, 64 in a card, 144 when switching).
Item {
    id: avatar

    property real unit: 1
    property real size: 32
    property string initial: ""
    property string tint: GlassStyle.profileColors[0]

    readonly property bool lightTint: GlassStyle.profileLightColors.indexOf(String(tint).toUpperCase()) >= 0

    width: size * unit
    height: size * unit

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: avatar.tint
    }

    // The inner light along the top edge, as in the design (inset 0 1px 0 white 28 %).
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, avatar.unit)
        border.color: GlassStyle.profileRing
        opacity: 0.5
    }

    Text {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: String(avatar.initial).charAt(0).toUpperCase()
        color: avatar.lightTint ? GlassStyle.profileInkDark : GlassStyle.profileInkLight
        font.family: GlassStyle.rowFont
        font.pixelSize: avatar.size * GlassStyle.profileInitialShare * avatar.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
