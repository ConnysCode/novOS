import QtQuick 2.12

// What lies behind the setup's glass:
//   "picture"  one of the launcher's pictures (lib/backgrounds), as Home and the hub show them
//   "glow"     black with a soft light in the middle (restart screens, K3-Boot-Schein)
//   "black"    plain black (farewell after the removal)
// The design canvas draws its own scenes; on the TV the setup uses the same pictures as
// the launcher, so that it looks like the novOS it installs.
Item {
    id: scene

    property real unit: 1
    property string kind: "picture"
    property url pictureSource: ""

    Rectangle {
        anchors.fill: parent
        color: scene.kind === "picture" ? "#02040a" : "#000000"
    }

    Image {
        anchors.fill: parent
        visible: scene.kind === "picture"
        source: visible ? scene.pictureSource : ""
        sourceSize: Qt.size(1920, 1080)
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    // The light of the boot look, shared with novOS' shutdown screen.
    BootGlow {
        anchors.fill: parent
        visible: scene.kind === "glow"
    }
}
