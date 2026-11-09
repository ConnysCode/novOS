import QtQuick 2.12

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

    property Item focusItem: null
    property bool plateShown: false

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
        var target = findFocused(card);
        focusItem = target;
        if (!target) return;
        var point = target.parent.mapToItem(card, target.x, target.y);
        plate.animated = plateShown;
        plate.x = point.x;
        plate.y = point.y;
        plate.width = target.width;
        plate.height = target.height;
        plate.radius = target.plateRadius;
        plate.focusScale = target.plateScale;
        plateShown = true;
    }

    // Rows lay out their buttons before the next frame; measure after that.
    Timer {
        id: placeTimer
        interval: 30
        onTriggered: dialog.placePlate()
    }

    onFocusKeyChanged: placeTimer.restart()
    onLeftButtonsChanged: placeTimer.restart()
    onRightButtonsChanged: placeTimer.restart()
    onCardHeightChanged: placeTimer.restart()
    Component.onCompleted: placeTimer.restart()

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
        height: dialog.cardHeight
        unit: dialog.unit
        backdrop: glass.texture
        glassShader: GlassStyle.glassShader
        backdropMargin: glass.margin
        backdropArea: glass.area
        hasBackdrop: 1

        // Below everything else of the card, so that text and drawings lie on it.
        FocusSurface {
            id: plate
            visible: dialog.focusItem !== null
            unit: dialog.unit
            animated: false
        }

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
                model: dialog.leftButtons
                FooterButton {
                    unit: dialog.unit
                    fontFamily: GlassStyle.rowFont
                    label: modelData.label
                    icon: modelData.icon || ""
                    focused: modelData.focused === true
                    disabled: modelData.disabled === true
                    danger: modelData.danger === true
                }
            }
        }

        Row {
            x: parent.width - width - 56 * dialog.unit
            y: dialog.footerY
            spacing: 12 * dialog.unit
            Repeater {
                model: dialog.rightButtons
                FooterButton {
                    unit: dialog.unit
                    fontFamily: GlassStyle.rowFont
                    label: modelData.label
                    icon: modelData.icon || ""
                    focused: modelData.focused === true
                    disabled: modelData.disabled === true
                    danger: modelData.danger === true
                }
            }
        }
    }
}
