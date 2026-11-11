import QtQuick 2.12
import "."

// Black screen while LG's apps and services follow a profile switch (K3-Profil-Wechsel):
// avatar, name, behind them the boot light in the profile's colour with the same slow
// breath. After 2 s a bar fades in where room was kept for it (K3-Profil-Wechsel-Lang); it
// runs towards LG's deadline and only shows that something is still happening.
Item {
    id: screen

    property real unit: 1
    property var profile: null           // { nick, initial, tint }, null hides the screen
    property real started: 0
    readonly property bool shown: profile !== null

    property real elapsed: 0
    readonly property real longAfter: 2000
    readonly property real deadline: 20000

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }

    onShownChanged: elapsed = 0

    // Keeps the last profile while the screen fades out.
    property var shownProfile: null
    onProfileChanged: if (profile !== null) shownProfile = profile

    Timer {
        interval: 100
        repeat: true
        running: screen.shown
        onTriggered: screen.elapsed = Date.now() - screen.started
    }

    MouseArea {
        anchors.fill: parent
        enabled: screen.shown
    }

    BootGlow {
        anchors.fill: parent
        pulsing: screen.shown
        tint: screen.shownProfile ? screen.shownProfile.tint : "transparent"
    }

    Column {
        anchors.centerIn: parent
        spacing: 28 * screen.unit

        ProfileAvatar {
            anchors.horizontalCenter: parent.horizontalCenter
            unit: screen.unit
            size: 144
            initial: screen.shownProfile ? screen.shownProfile.initial : ""
            tint: screen.shownProfile ? screen.shownProfile.tint : GlassStyle.profileColors[0]
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 52 * screen.unit
            verticalAlignment: Text.AlignVCenter
            text: screen.shownProfile ? screen.shownProfile.nick : ""
            color: GlassStyle.textPrimary
            font.family: GlassStyle.titleFont
            font.pixelSize: 44 * screen.unit
            font.letterSpacing: -0.88 * screen.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        ProgressBar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360 * screen.unit
            unit: screen.unit
            barHeight: 6
            value: Math.min(0.95, screen.elapsed / screen.deadline)
            opacity: screen.elapsed > screen.longAfter ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: GlassStyle.popoverDuration } }
        }
    }
}
