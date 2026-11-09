import QtQuick 2.12
import "WizardMemory.js" as Memory

// The glass dialog of the setup (K3-Install-*, K3-Update-*, K3-Entfernen-*): 1280 px wide,
// centred, as tall as its content. Header with the wordmark, the section and the steps;
// title and lead; the screen's content; footer buttons at the left and the right.
// One white focus surface glides between the focused elements, as everywhere in novOS:
// buttons, switch rows and choice cards are focus targets (focusTarget, focused,
// plateRadius, plateScale) and draw no white of their own. focusKey tells the dialog that
// the focus moved.
// The owner gives the content's height in logical px. Measures are the boards':
// padding 44 / 56, 44 from header to title, 12 to the lead, 32 to the content,
// 48 to the footer.
Item {
    id: dialog

    property real unit: 1
    property Item backdrop
    property string label: ""
    property int step: 0                    // 0 hides the steps at the right
    property int stepCount: 6
    property string title: ""
    property string lead: ""
    property real contentHeight: 0          // logical px
    property var leftButtons: []            // [{ label, icon, focused, disabled, danger }]
    property var rightButtons: []
    property string focusKey: ""
    default property alias content: contentArea.data

    readonly property bool hasFooter: leftButtons.length + rightButtons.length > 0
    readonly property real headerY: 44 * unit
    readonly property real titleY: headerY + 74 * unit
    readonly property real leadY: titleY + 66 * unit
    readonly property real contentY: (lead !== "" ? leadY + leadText.height : titleY + 54 * unit) + 32 * unit
    readonly property real footerY: contentY + (contentHeight + 48) * unit
    readonly property real cardHeight: (hasFooter ? footerY + 64 * unit : contentY + contentHeight * unit) + 44 * unit

    // Every page is a new dialog. It starts at the size of the page before, waits until its
    // own layout is measured (text and content arrive over the first frames) and then
    // glides there once, while its body fades in; without a page before it fades in whole.
    property real startHeight: 0
    property bool settled: false

    Timer {
        id: settleTimer
        interval: 60
        onTriggered: dialog.settled = true
    }

    onSettledChanged: Memory.remember(cardHeight)

    property Item focusItem: null
    property bool plateShown: false
    property string plateAt: ""
    property real plateTargetX: 0
    property real plateTargetY: 0

    function findFocused(item) {
        for (var i = 0; i < item.children.length; ++i) {
            var child = item.children[i];
            if (child.focusTarget === true && child.focused === true && child.visible) return child;
            var found = findFocused(child);
            if (found) return found;
        }
        return null;
    }

    // Measured from the target's parent, so that a target grown to 103 % still gives its
    // own size; the surface grows by itself.
    function placePlate() {
        var target = findFocused(body);
        focusItem = target;
        if (!target) return;
        var point = target.parent.mapToItem(plate.parent, target.x, target.y);
        // Measured again while gliding, the same place must not restart the glide.
        var place = [point.x, point.y, target.width, target.height].join(",");
        if (plateShown && place === plateAt) return;
        var far = Math.abs(point.x - plateTargetX) + Math.abs(point.y - plateTargetY) > GlassStyle.focusFarDistance * unit;
        plateAt = place;
        plateTargetX = point.x;
        plateTargetY = point.y;
        plate.duration = far ? GlassStyle.focusFarDuration : GlassStyle.focusDuration;
        plate.animated = plateShown;
        plate.x = point.x;
        plate.y = point.y;
        plate.width = target.width;
        plate.height = target.height;
        plate.radius = target.plateRadius;
        plate.focusScale = target.plateScale;
        plateShown = true;
    }

    // Rows lay out new buttons before the next frame; measure after that. A focus move
    // changes no layout and goes at once, so the surface leaves with the key press.
    Timer {
        id: placeTimer
        interval: 30
        onTriggered: dialog.placePlate()
    }

    onFocusKeyChanged: Qt.callLater(dialog.placePlate)
    onLeftButtonsChanged: placeTimer.restart()
    onRightButtonsChanged: placeTimer.restart()
    onCardHeightChanged: {
        placeTimer.restart();
        if (settled) Memory.remember(cardHeight);
    }
    Component.onCompleted: {
        startHeight = Memory.last();
        settleTimer.start();
        placeTimer.restart();
    }

    ImageGlass {
        id: glass
        sourceItem: dialog.backdrop
        unit: dialog.unit
        area: Qt.rect(card.x, card.y, card.width, card.height)
        visible: false
    }

    GlassCard {
        id: card
        x: 320 * dialog.unit
        y: Math.round((dialog.height - height) / 2)
        width: 1280 * dialog.unit
        height: dialog.settled || dialog.startHeight <= 0 ? dialog.cardHeight : dialog.startHeight
        glides: dialog.startHeight > 0 || dialog.settled
        opacity: dialog.settled || dialog.startHeight > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }
        unit: dialog.unit
        backdrop: glass.texture
        glassShader: GlassStyle.glassShader
        backdropMargin: glass.margin
        backdropArea: glass.area
        hasBackdrop: 1

        // Clipped to the card, so that a body taller than the card in the middle of the glide
        // does not stand out over the picture.
        Item {
            width: card.width
            height: card.height
            clip: true

            Wordmark {
                id: wordmark
                x: 56 * dialog.unit
                y: dialog.headerY + 1 * dialog.unit
                unit: dialog.unit
                size: 28
            }

            Text {
                x: wordmark.x + wordmark.width + 14 * dialog.unit
                anchors.baseline: wordmark.baseline
                text: dialog.label
                color: GlassStyle.textSecondary
                font.family: GlassStyle.rowFont
                font.pixelSize: 18 * dialog.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Row {
                visible: dialog.step > 0
                x: parent.width - width - 56 * dialog.unit
                y: dialog.headerY
                height: 30 * dialog.unit
                spacing: 14 * dialog.unit

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.t("setup", "header.step", { step: dialog.step, count: dialog.stepCount })
                    color: GlassStyle.textSecondary
                    font.family: GlassStyle.rowFont
                    font.pixelSize: 18 * dialog.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                StepBar {
                    anchors.verticalCenter: parent.verticalCenter
                    unit: dialog.unit
                    count: dialog.stepCount
                    reached: dialog.step
                }
            }

            Item {
                id: body
                width: card.width
                height: dialog.cardHeight
                opacity: dialog.settled ? 1 : 0
                y: dialog.settled ? 0 : 16 * dialog.unit

                Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve } }
                Behavior on y { NumberAnimation { duration: GlassStyle.pageDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve } }

                // Below everything else of the card, so that text and drawings lie on it.
                FocusSurface {
                    id: plate
                    visible: dialog.focusItem !== null
                    unit: dialog.unit
                    animated: false
                }

                Text {
                    x: 56 * dialog.unit
                    y: dialog.titleY
                    width: 1168 * dialog.unit
                    text: dialog.title
                    color: GlassStyle.textPrimary
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 54 * dialog.unit
                    font.family: GlassStyle.titleFont
                    font.pixelSize: 46 * dialog.unit
                    font.letterSpacing: -1.15 * dialog.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    id: leadText
                    visible: dialog.lead !== ""
                    x: 56 * dialog.unit
                    y: dialog.leadY
                    width: 980 * dialog.unit
                    text: dialog.lead
                    wrapMode: Text.WordWrap
                    color: "#ccffffff"
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 32 * dialog.unit
                    font.family: GlassStyle.valueFont
                    font.pixelSize: 22 * dialog.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item {
                    id: contentArea
                    x: 56 * dialog.unit
                    y: dialog.contentY
                    width: 1168 * dialog.unit
                    height: dialog.contentHeight * dialog.unit
                }

                Row {
                    x: 56 * dialog.unit
                    y: dialog.footerY
                    spacing: 12 * dialog.unit
                    Repeater {
                        // By count, so that a focus move does not build the buttons anew.
                        model: dialog.leftButtons.length
                        FooterButton {
                            readonly property var spec: dialog.leftButtons[index] || ({})
                            unit: dialog.unit
                            fontFamily: GlassStyle.rowFont
                            label: spec.label || ""
                            icon: spec.icon || ""
                            focused: spec.focused === true
                            disabled: spec.disabled === true
                            danger: spec.danger === true
                        }
                    }
                }

                Row {
                    x: parent.width - width - 56 * dialog.unit
                    y: dialog.footerY
                    spacing: 12 * dialog.unit
                    Repeater {
                        // By count, so that a focus move does not build the buttons anew.
                        model: dialog.rightButtons.length
                        FooterButton {
                            readonly property var spec: dialog.rightButtons[index] || ({})
                            unit: dialog.unit
                            fontFamily: GlassStyle.rowFont
                            label: spec.label || ""
                            icon: spec.icon || ""
                            focused: spec.focused === true
                            disabled: spec.disabled === true
                            danger: spec.danger === true
                        }
                    }
                }
            }
        }
    }
}
