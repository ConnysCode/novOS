import QtQuick 2.12
import "."

// Bar at the bottom centre for LG's toasts and dialogs, in LG's words. A single white
// surface marks the focused button, the owner decides what a button does.
Item {
    id: bar

    property real unit: 1
    property string titleFont: ""
    property string valueFont: ""
    property string shadowShader: ""
    property string glassShader: ""
    property variant backdrop
    property real backdropMargin: 0
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property var notice: ({ title: "", detail: "", icon: "notice-info", buttons: [] })
    property int focusIndex: 0
    property bool shown: false
    readonly property var buttons: notice.buttons || []
    signal buttonClicked(int index)

    width: Math.min(content.width + (buttons.length > 0 ? 42 : 60) * unit, 1400 * unit)
    height: 88 * unit
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 200 }
    }

    SoftShadow {
        unit: bar.unit
        radius: 44
        softness: 30
        drop: 24
        strength: 0.35
        pad: 110
    }

    GlassCard {
        anchors.fill: parent
        unit: bar.unit
        cornerRadius: 44 * bar.unit
        backdrop: bar.backdrop
        glassShader: bar.glassShader
        backdropMargin: bar.backdropMargin
        backdropArea: bar.backdropArea
        hasBackdrop: bar.hasBackdrop
        shadow: ""
    }

    Row {
        id: content
        x: 26 * bar.unit
        anchors.verticalCenter: parent.verticalCenter
        spacing: 18 * bar.unit

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 34 * bar.unit
            height: 34 * bar.unit
            smooth: true
            source: Qt.resolvedUrl("icons/" + bar.notice.icon + ".png")
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * bar.unit

            Text {
                width: Math.min(implicitWidth, (bar.buttons.length > 0 ? 900 : 1300) * bar.unit)
                elide: Text.ElideRight
                text: bar.notice.title
                color: "#ffffff"
                font.family: bar.titleFont
                font.pixelSize: 22 * bar.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                width: Math.min(implicitWidth, (bar.buttons.length > 0 ? 900 : 1300) * bar.unit)
                visible: text !== ""
                elide: Text.ElideRight
                text: bar.notice.detail
                color: GlassStyle.textSecondary
                font.family: bar.valueFont
                font.pixelSize: 17 * bar.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.buttons.length > 0
            spacing: 10 * bar.unit

            Repeater {
                model: bar.buttons

                Item {
                    readonly property bool focused: index === bar.focusIndex
                    width: buttonText.implicitWidth + 52 * bar.unit
                    height: 56 * bar.unit
                    scale: focused ? GlassStyle.focusScale : 1

                    Behavior on scale {
                        NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier
                                          easing.bezierCurve: GlassStyle.curve }
                    }

                    GlassControl {
                        anchors.fill: parent
                        visible: !parent.focused
                        unit: bar.unit
                        radius: 28
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: parent.focused
                        radius: height / 2
                        color: GlassStyle.focusFill
                        antialiasing: true
                    }

                    Text {
                        id: buttonText
                        anchors.centerIn: parent
                        text: modelData.label || ""
                        color: parent.focused ? GlassStyle.focusText : "#ffffff"
                        font.family: bar.titleFont
                        font.pixelSize: 20 * bar.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: bar.buttonClicked(index)
                    }
                }
            }
        }
    }
}
