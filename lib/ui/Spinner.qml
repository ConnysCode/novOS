import QtQuick 2.12

// Ring with a bright quarter, 900 ms per turn as in the hand-off.
Item {
    id: spinner

    property real size: 44
    property real lineWidth: 4
    property bool running: false
    property bool dark: false
    width: size
    height: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: spinner.lineWidth
        border.color: spinner.dark ? "#240b0c10" : "#38ffffff"
    }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl(spinner.dark ? "icons/spinner-44-dark.png" : "icons/spinner-44.png")
        smooth: true

        RotationAnimation on rotation {
            running: spinner.running
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }
}
