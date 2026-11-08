import QtQuick 2.12

// One key of the on-screen keyboard. The white focus surface belongs to the owner,
// so a focused key only drops its own fill.
Item {
    id: cap

    property var board
    property string keyId: ""
    property string label: ""
    readonly property bool focused: board.focusedKey === keyId
    readonly property bool latched: (board.symbols && keyId === "symbols") ||
                                    (board.shifted && keyId === "shift")
    opacity: board.isEnabled(keyId) ? 1 : 0.4
    scale: board.pressScaleOf(keyId)

    Behavior on scale {
        NumberAnimation { duration: cap.board.pressDuration; easing.type: Easing.OutQuad }
    }

    GlassControl {
        anchors.fill: parent
        visible: !cap.focused
        unit: cap.board.unit
        radius: 16
        fill: cap.latched ? "#47ffffff" : "#1affffff"
    }

    Text {
        anchors.centerIn: parent
        visible: cap.keyId !== "shift"
        text: cap.label
        color: cap.focused ? GlassStyle.focusText : "#ffffff"
        font.family: cap.board.keyFont
        font.pixelSize: (cap.keyId.indexOf("k-") === 0 ? 22 : 19) * cap.board.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Image {
        anchors.centerIn: parent
        visible: cap.keyId === "shift"
        source: Qt.resolvedUrl(cap.focused ? "icons/shift-24-dark.png" : "icons/shift-24.png")
    }

    MouseArea {
        anchors.fill: parent
        onPressed: cap.board.pressKey(cap.keyId)
        onClicked: cap.board.keyClicked(cap.keyId)
    }
}
