import QtQuick 2.12
import "."

// A compact glass bar over the picture with one vertical slider per band (K3-Einst-Equalizer):
// the equalizers' 5 and 10 bands, later the points of the white balance. It stands at the
// bottom centre, so that the picture stays in view while the sound or colour changes.
// Left and Right choose a band, Up and Down change its value (held keys repeat), Right of
// the last band reaches the button "Flach". Every change goes out at once: the owner writes
// bandChanged and flatten, and closes the bar on finished (OK on a band) and on Back.
// It fills the screen; its glass samples the owner's crop like a GlassCard.
Item {
    id: editor

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property variant backdrop
    property string glassShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0

    property string title: ""
    property var labels: []          // one per band, "100 Hz"
    property var values: []          // one number per band
    property real minimum: -10
    property real maximum: 10
    property real step: 1
    property var keys: []            // the legend: [{ key: "Links/Rechts", action: "Band" }]
    property string flatLabel: ""
    property int focusIndex: 0       // a band, or count for the button

    signal bandChanged(int index, real value)
    signal flatten()
    signal finished()

    readonly property int count: labels.length
    readonly property bool onButton: focusIndex >= count
    // Ten bands stay readable from the sofa at 100 px each (K3-Einst-Equalizer-05).
    readonly property real bandWidth: count > 6 ? 100 : 128
    readonly property real bandGap: count > 6 ? 10 : 16
    readonly property real padX: 32
    readonly property real padY: 28
    readonly property real headHeight: 36
    readonly property real headGap: 22
    readonly property real bandHeight: 356     // 18 + value 30 + 14 + track 240 + 14 + label 24 + 16
    readonly property real trackHeight: 240
    readonly property real separatorGap: 24
    readonly property real buttonArea: 132
    readonly property real bandsWidth: count * bandWidth + Math.max(0, count - 1) * bandGap
    readonly property real cardWidth: 2 * padX + bandsWidth + 2 * separatorGap + 1 + buttonArea
    readonly property real cardHeight: 2 * padY + headHeight + headGap + bandHeight
    readonly property real bandsY: padY + headHeight + headGap

    function bandX(index) {
        return padX + index * (bandWidth + bandGap);
    }

    // "+3", "0", "−2" with a real minus.
    function signed(value) {
        return value > 0 ? "+" + value : (value < 0 ? "−" + Math.abs(value) : "0");
    }

    function share(value) {
        return maximum > minimum ? (value - minimum) / (maximum - minimum) : 0.5;
    }

    function open() {
        focusIndex = 0;
    }

    function handleKey(key, autoRepeat) {
        if (key === Qt.Key_Left) {
            if (focusIndex > 0) focusIndex = Math.min(focusIndex, count) - 1;
        } else if (key === Qt.Key_Right) {
            if (focusIndex < count) focusIndex++;
        } else if (key === Qt.Key_Up || key === Qt.Key_Down) {
            if (onButton) return true;
            var current = Number(values[focusIndex]) || 0;
            var next = Math.max(minimum, Math.min(maximum, current + (key === Qt.Key_Up ? step : -step)));
            if (next !== current) bandChanged(focusIndex, next);
        } else if (Remote.isOk(key)) {
            if (autoRepeat) return true;
            if (onButton) flatten();
            else finished();
        } else {
            return false;
        }
        return true;
    }

    GlassCard {
        id: card
        x: (editor.width - width) / 2
        y: editor.height - height - GlassStyle.bottomBarInset * editor.unit
        width: editor.cardWidth * editor.unit
        height: editor.cardHeight * editor.unit
        glides: false
        unit: editor.unit
        backdrop: editor.backdrop
        glassShader: editor.glassShader
        backdropMargin: editor.backdropMargin
        backdropArea: editor.backdropArea
        hasBackdrop: editor.hasBackdrop

        // Title and the keys at the right: "Links/Rechts: Band".
        Item {
            x: (editor.padX + 12) * editor.unit
            y: editor.padY * editor.unit
            width: (editor.cardWidth - 2 * editor.padX - 24) * editor.unit
            height: editor.headHeight * editor.unit

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - legend.width - 24 * editor.unit
                elide: Text.ElideRight
                text: editor.title
                color: GlassStyle.textPrimary
                font.family: editor.titleFont
                font.pixelSize: GlassStyle.barTitleSize * editor.unit
                font.letterSpacing: -0.6 * editor.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Row {
                id: legend
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 24 * editor.unit

                Repeater {
                    model: editor.keys

                    Row {
                        spacing: 6 * editor.unit

                        Text {
                            text: modelData.key + ":"
                            color: GlassStyle.textPrimary
                            font.family: editor.rowFont
                            font.pixelSize: GlassStyle.detailSize * editor.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }

                        Text {
                            text: modelData.action
                            color: GlassStyle.textSecondary
                            font.family: editor.valueFont
                            font.pixelSize: GlassStyle.detailSize * editor.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }
        }

        // The single focus surface glides between the bands and the button.
        FocusSurface {
            readonly property real buttonWidth: flatButton.width / editor.unit
            x: (editor.onButton ? flatButton.x / editor.unit : editor.bandX(editor.focusIndex)) * editor.unit
            y: (editor.onButton ? flatButton.y / editor.unit : editor.bandsY) * editor.unit
            width: (editor.onButton ? buttonWidth : editor.bandWidth) * editor.unit
            height: (editor.onButton ? 64 : editor.bandHeight) * editor.unit
            unit: editor.unit
            radius: editor.onButton ? GlassStyle.pillRadius : GlassStyle.chipRadius
            focusScale: GlassStyle.focusScale
        }

        Repeater {
            model: editor.count

            Item {
                readonly property bool focused: editor.focusIndex === index
                readonly property real value: Number(editor.values[index]) || 0
                x: editor.bandX(index) * editor.unit
                y: editor.bandsY * editor.unit
                width: editor.bandWidth * editor.unit
                height: editor.bandHeight * editor.unit
                scale: focused ? GlassStyle.focusScale : 1

                Behavior on scale {
                    NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
                }

                Text {
                    y: 18 * editor.unit
                    width: parent.width
                    height: 30 * editor.unit
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: editor.signed(parent.value)
                    color: parent.focused ? GlassStyle.focusText : GlassStyle.textPrimary
                    font.family: editor.titleFont
                    font.pixelSize: GlassStyle.bandValueSize * editor.unit
                    font.hintingPreference: Font.PreferNoHinting
                    Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                }

                GlassSlider {
                    x: (parent.width - width) / 2
                    y: 62 * editor.unit
                    height: editor.trackHeight * editor.unit
                    unit: editor.unit
                    vertical: true
                    origin: editor.share(0)
                    zeroLine: true
                    knob: true
                    share: editor.share(parent.value)
                    focused: parent.focused
                }

                Text {
                    y: (62 + editor.trackHeight + 14) * editor.unit
                    width: parent.width
                    height: 24 * editor.unit
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: editor.labels[index]
                    color: parent.focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
                    font.family: editor.rowFont
                    font.pixelSize: GlassStyle.bandLabelSize * editor.unit
                    font.hintingPreference: Font.PreferNoHinting
                    Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: editor.focusIndex = index
                }
            }
        }

        Rectangle {
            x: (editor.padX + editor.bandsWidth + editor.separatorGap) * editor.unit
            y: (editor.bandsY + (editor.bandHeight - editor.trackHeight) / 2) * editor.unit
            width: Math.max(1, editor.unit)
            height: editor.trackHeight * editor.unit
            color: GlassStyle.divider
        }

        FooterButton {
            id: flatButton
            x: (editor.padX + editor.bandsWidth + 2 * editor.separatorGap + 1) * editor.unit +
               (editor.buttonArea * editor.unit - width) / 2
            y: (editor.bandsY + (editor.bandHeight - 64) / 2) * editor.unit
            unit: editor.unit
            fontFamily: editor.rowFont
            label: editor.flatLabel
            focused: editor.onButton
            scale: focused ? GlassStyle.focusScale : 1
            onClicked: {
                editor.focusIndex = editor.count;
                editor.flatten();
            }
        }
    }
}
