import QtQuick 2.12

// Name of the current slide in a quiet pill at the bottom left, for debug builds.
Rectangle {
    id: badge

    property real unit: 1
    property string label: ""

    width: text.width + 32 * unit
    height: 40 * unit
    radius: height / 2
    color: "#99000000"

    Text {
        id: text
        anchors.centerIn: parent
        text: badge.label
        color: "#d9ffffff"
        font.family: GlassStyle.valueFont
        font.pixelSize: 17 * badge.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
