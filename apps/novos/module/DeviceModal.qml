import QtQuick 2.12
import "."

// The device dialog of the settings (TON-A, K3-Einst-BT-und-TV-05 … 07, K3-Einst-WiSA-WOWCAST-07
// … 11): a catalog page with dialog: true, drawn over the page it was opened from. Its head is
// the one of StatusCard (symbol in a 64 px circle, name, state), its rows are GlassRows as in
// the list, rows with footer: true are FooterButtons below them. The settings modal owns the
// page, its actions and Back; the dialog draws it, moves the single focus surface and hands the
// keys on. A choice row opens a ChoicePopover beside its row (six positions of a WiSA speaker).
Item {
    id: dialog

    property var owner: null              // SettingsModal
    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property variant backdrop
    property string glassShader: ""
    property string shadowShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0

    property var page: ({ title: "", subtitle: "", icon: "", rows: [] })
    property int focusIndex: 0            // an index of page.rows
    property var choices: []              // the option rows the popover offers
    readonly property bool popoverOpen: popover.shown

    readonly property var rows: page && page.rows ? page.rows : []
    readonly property real cardWidth: 880
    readonly property real pad: 40
    readonly property real headHeight: 64
    readonly property real gap: 28
    readonly property real rowGap: 4
    readonly property real buttonHeight: 64
    readonly property var layout: layoutOf(rows)
    readonly property var focusedRow: rows.length > focusIndex ? rows[focusIndex] : null

    function rowHeight(row) {
        return owner ? owner.rowHeight(row) : 68;
    }

    // Body rows from the top of the card, then the line of buttons.
    function layoutOf(list) {
        var y = pad + headHeight + gap;
        var top = [];
        var body = 0;
        for (var i = 0; i < list.length; i++) {
            if (list[i].footer) {
                top.push(-1);
                continue;
            }
            if (body > 0) y += rowGap;
            top.push(y);
            y += rowHeight(list[i]);
            body++;
        }
        var footer = 0;
        for (var j = 0; j < list.length; j++) {
            if (list[j].footer) footer++;
        }
        var footerTop = body > 0 ? y + gap : pad + headHeight + gap;
        return { top: top, footerTop: footerTop,
                 height: (footer > 0 ? footerTop + buttonHeight : (body > 0 ? y : pad + headHeight)) + pad };
    }

    // A Repeater's modelData is a copy: rows are found by their id.
    function indexOfId(id) {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === id) return i;
        }
        return -1;
    }

    function footerRows() {
        return rows.filter(function (row) { return row.footer; });
    }

    function focusable(index) {
        var row = rows[index];
        if (!row) return false;
        return row.footer ? !row.disabled : row.focusable !== false;
    }

    // The first row that takes OK, else the first button that does (K3-Einst-BT-und-TV-07: with
    // "Position" greyed out the focus starts on "Trennen").
    function firstFocus() {
        for (var i = 0; i < rows.length; i++) {
            if (!rows[i].footer && rows[i].focusable !== false && !rows[i].disabled) return i;
        }
        for (var j = 0; j < rows.length; j++) {
            if (rows[j].footer && !rows[j].disabled) return j;
        }
        return 0;
    }

    function start() {
        popover.close();
        focusIndex = firstFocus();
        Qt.callLater(place);
    }

    // The rows change as the device does: the focus stays on its row by id.
    property string focusedId: ""
    onRowsChanged: {
        var wanted = -1;
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === focusedId) wanted = i;
        }
        if (wanted >= 0 && focusable(wanted)) focusIndex = wanted;
        else if (!focusable(focusIndex)) focusIndex = firstFocus();
        Qt.callLater(place);
    }
    onFocusIndexChanged: {
        if (rows[focusIndex]) focusedId = rows[focusIndex].id;
        Qt.callLater(place);
    }

    function move(step) {
        var row = rows[focusIndex];
        if (!row) return;
        var i;
        if (row.footer) {
            if (step > 0) return;
            for (i = rows.length - 1; i >= 0; i--) {
                if (!rows[i].footer && focusable(i)) {
                    focusIndex = i;
                    return;
                }
            }
            return;
        }
        for (i = focusIndex + step; i >= 0 && i < rows.length; i += step) {
            if (!rows[i].footer && focusable(i)) {
                focusIndex = i;
                return;
            }
        }
        if (step > 0) {
            for (i = 0; i < rows.length; i++) {
                if (rows[i].footer && focusable(i)) {
                    focusIndex = i;
                    return;
                }
            }
        }
    }

    function moveInFooter(step) {
        for (var i = focusIndex + step; i >= 0 && i < rows.length; i += step) {
            if (rows[i].footer && focusable(i)) {
                focusIndex = i;
                return;
            }
        }
    }

    function handleKey(key, autoRepeat) {
        if (popover.shown) {
            popover.handleKey(key, autoRepeat);
            return;
        }
        var row = rows[focusIndex];
        if (key === Qt.Key_Up) move(-1);
        else if (key === Qt.Key_Down) move(1);
        else if ((key === Qt.Key_Left || key === Qt.Key_Right) && row) {
            if (row.footer) moveInFooter(key === Qt.Key_Right ? 1 : -1);
            else if (row.type === "slider" && owner) owner.stepSlider(row, key === Qt.Key_Right ? 1 : -1);
        } else if (Remote.isOk(key) && !autoRepeat && row && owner) {
            owner.activateInDialog(row);
        }
    }

    // A choice with its values beside the row; option rows from Engine.resolveChoice.
    function openChoice(row, options) {
        choices = options;
        var values = [];
        var current = "";
        for (var i = 0; i < options.length; i++) {
            values.push({ label: options[i].title, value: String(options[i].option),
                          detail: options[i].selected ? "" : options[i].subtitle });
            if (options[i].selected) current = String(options[i].option);
        }
        var index = indexOfId(row.id);
        var rowTop = index >= 0 ? layout.top[index] : pad;
        popover.y = card.y + Math.max(0, rowTop - 12) * unit;
        popover.openList(row.title, values, current, 0);
    }

    function closeChoice() {
        popover.close();
    }

    // ---- Focus surface -----------------------------------------------------------

    property rect focusRect: Qt.rect(0, 0, 0, 0)
    property real focusRadius: 26

    function place() {
        var row = rows[focusIndex];
        if (!row) return;
        if (row.footer) {
            var footerIndex = footerRows().indexOf(row);
            var button = buttons.itemAt(footerIndex);
            if (!button) return;
            focusRect = Qt.rect(footerRow.x + button.x, footerRow.y + button.y, button.width, button.height);
            focusRadius = buttonHeight / 2;
        } else {
            focusRect = Qt.rect((pad - 4) * unit, layout.top[focusIndex] * unit, (cardWidth - 2 * (pad - 4)) * unit,
                                rowHeight(row) * unit);
            focusRadius = 26;
        }
    }

    // ---- Drawing -------------------------------------------------------------------

    // The settings card steps back behind the dialog.
    Rectangle {
        anchors.fill: parent
        color: GlassStyle.scrimColor
        opacity: GlassStyle.dialogScrim
    }

    MouseArea {
        anchors.fill: parent
        onClicked: if (dialog.owner) dialog.owner.back()
    }

    GlassCard {
        id: card
        x: (dialog.width - width) / 2
        y: (dialog.height - height) / 2
        width: dialog.cardWidth * dialog.unit
        height: dialog.layout.height * dialog.unit
        unit: dialog.unit
        backdrop: dialog.backdrop
        glassShader: dialog.glassShader
        backdropMargin: dialog.backdropMargin
        backdropArea: dialog.backdropArea
        hasBackdrop: dialog.hasBackdrop
        onHeightChanged: Qt.callLater(dialog.place)

        MouseArea {
            anchors.fill: parent
        }

        // Head as in StatusCard: the symbol in a 64 px circle, the name, the state.
        Rectangle {
            id: circle
            x: (dialog.pad + 8) * dialog.unit
            y: dialog.pad * dialog.unit
            width: dialog.headHeight * dialog.unit
            height: width
            radius: width / 2
            color: GlassStyle.circleFill

            Image {
                anchors.centerIn: parent
                visible: dialog.page.icon !== "" && dialog.page.busy !== true
                source: dialog.page.icon ? Qt.resolvedUrl("icons/" + dialog.page.icon + "-32.png") : ""
            }

            Spinner {
                anchors.centerIn: parent
                visible: dialog.page.busy === true
                running: visible
                size: 30 * dialog.unit
                lineWidth: 3 * dialog.unit
            }
        }

        Column {
            x: circle.x + circle.width + 20 * dialog.unit
            width: card.width - x - dialog.pad * dialog.unit
            anchors.verticalCenter: circle.verticalCenter
            spacing: 2 * dialog.unit

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: dialog.page.title || ""
                color: GlassStyle.textPrimary
                font.family: dialog.titleFont
                font.pixelSize: GlassStyle.dialogTitleSize * dialog.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                text: dialog.page.subtitle || ""
                color: GlassStyle.textSecondary
                font.family: dialog.valueFont
                font.pixelSize: GlassStyle.dialogTextSize * dialog.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        FocusSurface {
            x: dialog.focusRect.x
            y: dialog.focusRect.y
            width: dialog.focusRect.width
            height: dialog.focusRect.height
            // The popover draws its own focus while it is open.
            visible: dialog.rows.length > 0 && dialog.focusRect.width > 0 && !dialog.popoverOpen
            unit: dialog.unit
            radius: dialog.focusRadius
        }

        Repeater {
            model: dialog.rows

            GlassRow {
                readonly property bool slider: modelData.type === "slider"
                x: (dialog.pad - 4) * dialog.unit
                y: Math.max(0, dialog.layout.top[index]) * dialog.unit
                width: (dialog.cardWidth - 2 * (dialog.pad - 4)) * dialog.unit
                height: dialog.rowHeight(modelData) * dialog.unit
                visible: !modelData.footer
                unit: dialog.unit
                titleFont: dialog.rowFont
                valueFont: dialog.valueFont
                focused: dialog.focusIndex === index && !dialog.popoverOpen
                title: modelData.title || ""
                subtitle: modelData.subtitle || ""
                iconPng: modelData.icon || ""
                value: modelData.value || ""
                // A choice opens its values below: the chevron points down (K3-Einst-WiSA-WOWCAST-07).
                // A choice of two values changes on OK and has no mark.
                mark: modelData.type === "choice" ? (modelData.row && modelData.row.cycle ? "" : "down")
                                                  : (modelData.external ? "external" : "")
                sliderShare: slider && modelData.max > modelData.min ?
                             (modelData.number - modelData.min) / (modelData.max - modelData.min) : -1
                sliderOrigin: slider && modelData.origin !== undefined ? modelData.origin : -1
                sliderEnds: slider ? modelData.ends || null : null
                danger: modelData.danger === true
                disabled: modelData.disabled === true
                busy: modelData.busy === true
                tone: modelData.tone || ""

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        dialog.focusIndex = index;
                        if (dialog.owner) dialog.owner.activateInDialog(dialog.rows[index]);
                    }
                }
            }
        }

        Row {
            id: footerRow
            x: (dialog.pad + 4) * dialog.unit
            y: dialog.layout.footerTop * dialog.unit
            spacing: 12 * dialog.unit

            Repeater {
                id: buttons
                model: dialog.footerRows()

                FooterButton {
                    unit: dialog.unit
                    fontFamily: dialog.rowFont
                    label: modelData.title || ""
                    danger: modelData.danger === true
                    disabled: modelData.disabled === true
                    focused: !!dialog.focusedRow && dialog.focusedRow.id === modelData.id && !dialog.popoverOpen
                    onWidthChanged: Qt.callLater(dialog.place)
                    onClicked: {
                        dialog.focusIndex = dialog.indexOfId(modelData.id);
                        if (dialog.owner) dialog.owner.activateInDialog(dialog.rows[dialog.focusIndex]);
                    }
                }
            }
        }
    }

    ChoicePopover {
        id: popover
        z: 10
        unit: dialog.unit
        x: card.x + card.width - (dialog.pad + 380) * dialog.unit
        width: 380 * dialog.unit
        titleFont: dialog.titleFont
        rowFont: dialog.rowFont
        backdrop: dialog.backdrop
        glassShader: dialog.glassShader
        shadowShader: dialog.shadowShader
        backdropMargin: dialog.backdropMargin
        backdropArea: dialog.backdropArea
        hasBackdrop: dialog.hasBackdrop
        onChosen: {
            close();
            for (var i = 0; i < dialog.choices.length; i++) {
                if (String(dialog.choices[i].option) === value && dialog.owner) dialog.owner.chooseInDialog(dialog.choices[i]);
            }
        }
    }
}
