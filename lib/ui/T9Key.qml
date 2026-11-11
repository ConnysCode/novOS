import QtQuick 2.12
import "."

// One key of the T9 pad (K3-Tastatur-T9). A digit key shows the digit over its letters,
// the other keys an icon and a label in one line. As with KeyCap the white focus surface
// belongs to the owner, so a focused key only drops its own fill.
Item {
    id: cap

    property var board
    property string keyId: ""
    property string digit: ""            // "" for Shift, Symbols and Delete
    property string letters: ""
    property string label: ""
    property string icon: ""             // base name in icons/, with a -dark variant
    property bool latched: false
    readonly property bool focused: board.focusedKey === keyId
    readonly property real u: board.unit
    scale: board.pressScaleOf(keyId)

    Behavior on scale {
        NumberAnimation { duration: cap.board.pressDuration; easing.type: Easing.OutQuad }
    }

    GlassControl {
        anchors.fill: parent
        visible: !cap.focused
        unit: cap.u
        radius: 20
        fill: cap.latched ? GlassStyle.fillLatchedStrong : GlassStyle.fillRest
    }

    Column {
        anchors.centerIn: parent
        visible: cap.digit !== ""

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 34 * cap.u
            verticalAlignment: Text.AlignVCenter
            text: cap.digit
            color: cap.focused ? GlassStyle.focusText : "#ffffff"
            font.family: cap.board.keyFont
            font.pixelSize: 30 * cap.u
            font.hintingPreference: Font.PreferNoHinting
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(lettersText.width, spaceIcon.width)
            height: 20 * cap.u

            Text {
                id: lettersText
                anchors.centerIn: parent
                visible: cap.digit !== "0"
                text: cap.letters
                color: cap.focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
                font.family: cap.board.keyFont
                font.pixelSize: 16 * cap.u
                font.letterSpacing: 1.28 * cap.u
                font.hintingPreference: Font.PreferNoHinting
            }

            // 0 types a space first.
            Image {
                id: spaceIcon
                anchors.centerIn: parent
                visible: cap.digit === "0"
                source: Qt.resolvedUrl(cap.focused ? "icons/space-22-dark.png" : "icons/space-22.png")
            }
        }
    }

    Row {
        anchors.centerIn: parent
        visible: cap.digit === ""
        spacing: 10 * cap.u

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: cap.icon !== ""
            source: cap.icon !== "" ? Qt.resolvedUrl("icons/" + cap.icon + (cap.focused ? "-dark" : "") + ".png") : ""
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: cap.label
            color: cap.focused ? GlassStyle.focusText : "#ffffff"
            font.family: cap.board.keyFont
            font.pixelSize: 19 * cap.u
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: cap.board.pressKey(cap.keyId)
        onClicked: cap.board.keyClicked(cap.keyId)
    }
}
