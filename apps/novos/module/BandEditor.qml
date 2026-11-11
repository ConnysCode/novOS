import QtQuick 2.12
import "."

// A compact glass bar over the picture with columns side by side: the equalizers' 5 and 10
// bands (K3-Einst-Equalizer) and the points of the white balance (K3-Einst-Weissabgleich).
// It stands at the bottom centre, so that the picture stays in view while the sound or
// colour changes. A column is a vertical slider or a list of levels (the signal levels of
// the white balance, the chosen one in the middle). Left and Right choose a column and skip
// greyed ones, Up and Down change its value (held keys repeat), Right of the last column
// reaches the button, if there is one ("Flach"). Every change goes out at once: the owner
// writes columnChanged and buttonPressed, and closes the bar on finished (OK on a column) and
// on Back. It fills the screen; its glass samples the owner's crop like a GlassCard.
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
    // One per column (SettingsEngine.resolveBands): { kind: "slider", label, dot, value, text,
    // min, max, step, center, disabled, reason, group } or { kind: "levels", label, options,
    // selected, group }. center null fills a slider from its bottom.
    property var columns: []
    property var keys: []            // the legend: [{ key: "Links/Rechts", action: "Band" }]
    property string buttonLabel: ""  // empty: no button
    property bool buttonDanger: false
    property int focusIndex: 0       // a column, or count for the button

    signal columnChanged(int index, real value)
    signal buttonPressed()
    signal finished()

    readonly property int count: columns.length
    readonly property bool hasButton: buttonLabel !== ""
    readonly property bool onButton: hasButton && focusIndex >= count
    readonly property bool hasLevels: {
        for (var i = 0; i < count; i++) {
            if (columns[i].kind === "levels") return true;
        }
        return false;
    }
    // Ten bands stay readable from the sofa at 100 px each (K3-Einst-Equalizer-05). The white
    // balance has narrower sliders and wide columns for the levels and the maximum.
    readonly property real bandWidth: hasLevels ? 112 : (count > 6 ? 100 : 128)
    readonly property real wideWidth: 150
    readonly property real bandGap: hasLevels ? 12 : (count > 6 ? 10 : 16)
    readonly property real padX: 32
    readonly property real padY: hasLevels ? 24 : 28
    readonly property real headHeight: hasLevels ? 34 : 36
    readonly property real headGap: hasLevels ? 16 : 22
    readonly property real trackHeight: hasLevels ? 200 : 240
    readonly property real reasonHeight: 23    // 4 + one line of 19
    readonly property bool hasReason: {
        for (var i = 0; i < count; i++) {
            if (columns[i].disabled && columns[i].reason) return true;
        }
        return false;
    }
    // 18 + value 30 + 14 + track + 14 + label 24 + 16, and a line for a reason.
    readonly property real bandHeight: 18 + 30 + 14 + trackHeight + 14 + 24 + 16 + (hasReason ? reasonHeight : 0)
    readonly property real separatorGap: 24
    readonly property real buttonArea: hasLevels ? 190 : 132
    readonly property var columnX: {
        var xs = [];
        var x = padX;
        for (var i = 0; i < count; i++) {
            if (i > 0) x += columns[i].group !== columns[i - 1].group ? 2 * separatorGap + 1 : bandGap;
            xs.push(x);
            x += widthOf(i);
        }
        xs.push(x);
        return xs;
    }
    readonly property real bandsWidth: count > 0 ? columnX[count] - padX : 0
    readonly property real cardWidth: 2 * padX + bandsWidth + (hasButton ? 2 * separatorGap + 1 + buttonArea : 0)
    readonly property real cardHeight: 2 * padY + headHeight + headGap + bandHeight
    readonly property real bandsY: padY + headHeight + headGap
    readonly property real levelRow: 40

    function widthOf(index) {
        var column = columns[index];
        return column && (column.kind === "levels" || column.wide) ? wideWidth : bandWidth;
    }

    function bandX(index) {
        return columnX[Math.max(0, Math.min(index, count))];
    }

    function focusable(index) {
        return index >= 0 && index < count && !columns[index].disabled;
    }

    // "+3", "0", "−2" with a real minus.
    function signed(value) {
        return value > 0 ? "+" + value : (value < 0 ? "−" + Math.abs(value) : "0");
    }

    function share(column, value) {
        return column.max > column.min ? (value - column.min) / (column.max - column.min) : 0.5;
    }

    function open() {
        focusIndex = 0;
        while (focusIndex < count && !focusable(focusIndex)) focusIndex++;
    }

    // A column that turns grey under the focus (the maximum when the level leaves 100 %)
    // hands the focus to its left neighbour.
    onColumnsChanged: {
        if (focusIndex < count && !focusable(focusIndex)) {
            var at = focusIndex;
            while (at > 0 && !focusable(at)) at--;
            focusIndex = at;
        }
    }

    function step(direction) {
        var at = Math.min(focusIndex, count) + direction;
        while (at >= 0 && at < count && !focusable(at)) at += direction;
        if (at >= 0 && at < count) focusIndex = at;
        else if (direction > 0 && hasButton) focusIndex = count;
    }

    function handleKey(key, autoRepeat) {
        if (key === Qt.Key_Left) {
            step(-1);
        } else if (key === Qt.Key_Right) {
            if (focusIndex < count) step(1);
        } else if (key === Qt.Key_Up || key === Qt.Key_Down) {
            if (focusIndex >= count) return true;
            var column = columns[focusIndex];
            if (column.kind === "levels") {
                // Up goes to the higher level, which stands above.
                var next = column.selected + (key === Qt.Key_Up ? -1 : 1);
                if (next >= 0 && next < column.options.length) columnChanged(focusIndex, next);
            } else {
                var current = Number(column.value) || 0;
                var stepped = Math.max(column.min, Math.min(column.max,
                                       current + (key === Qt.Key_Up ? column.step : -column.step)));
                if (stepped !== current) columnChanged(focusIndex, stepped);
            }
        } else if (Remote.isOk(key)) {
            if (autoRepeat) return true;
            if (onButton) buttonPressed();
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
                font.pixelSize: (editor.hasLevels ? GlassStyle.barTitleCompactSize : GlassStyle.barTitleSize) * editor.unit
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

        // The single focus surface glides between the columns and the button.
        FocusSurface {
            visible: editor.onButton || editor.focusable(editor.focusIndex)
            x: (editor.onButton ? actionButton.x / editor.unit : editor.bandX(editor.focusIndex)) * editor.unit
            y: (editor.onButton ? actionButton.y / editor.unit : editor.bandsY) * editor.unit
            width: (editor.onButton ? actionButton.width / editor.unit : editor.widthOf(editor.focusIndex)) * editor.unit
            height: (editor.onButton ? 64 : editor.bandHeight) * editor.unit
            unit: editor.unit
            radius: editor.onButton ? GlassStyle.pillRadius : GlassStyle.chipRadius
            focusScale: GlassStyle.focusScale
        }

        Repeater {
            model: editor.count

            Item {
                id: column
                readonly property var spec: editor.columns[index] || ({})
                readonly property bool focused: editor.focusIndex === index && !spec.disabled
                readonly property bool levels: spec.kind === "levels"
                readonly property bool centred: spec.center !== null && spec.center !== undefined
                readonly property real value: Number(spec.value) || 0
                readonly property color quiet: focused ? GlassStyle.focusSecondary : GlassStyle.textSecondary
                x: editor.bandX(index) * editor.unit
                y: editor.bandsY * editor.unit
                width: editor.widthOf(index) * editor.unit
                height: editor.bandHeight * editor.unit
                scale: focused ? GlassStyle.focusScale : 1

                Behavior on scale {
                    NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
                }

                // The value above a slider ("+3", "130"), the arrows above a level list.
                Text {
                    visible: !column.levels
                    y: 18 * editor.unit
                    width: parent.width
                    height: 30 * editor.unit
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: column.spec.text !== undefined ? column.spec.text : editor.signed(column.value)
                    color: column.spec.disabled ? GlassStyle.textDisabled :
                           (column.focused ? GlassStyle.focusText : GlassStyle.textPrimary)
                    font.family: editor.titleFont
                    font.pixelSize: GlassStyle.bandValueSize * editor.unit
                    font.hintingPreference: Font.PreferNoHinting
                    Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                }

                Row {
                    visible: column.levels
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 23 * editor.unit
                    spacing: 4 * editor.unit

                    Repeater {
                        model: ["chevron-up-20", "chevron-down-20"]

                        Image {
                            width: 20 * editor.unit
                            height: width
                            sourceSize.width: width
                            sourceSize.height: height
                            source: "icons/" + modelData + (column.focused ? "-dark" : "") + ".png"
                            opacity: column.focused ? 1 : 0.72
                        }
                    }
                }

                GlassSlider {
                    visible: !column.levels
                    x: (parent.width - width) / 2
                    y: 62 * editor.unit
                    height: editor.trackHeight * editor.unit
                    unit: editor.unit
                    vertical: true
                    origin: column.centred ? editor.share(column.spec, column.spec.center) : 0
                    zeroLine: column.centred
                    knob: true
                    share: editor.share(column.spec, column.value)
                    focused: column.focused
                    disabled: column.spec.disabled === true
                }

                // The levels, the chosen one in the middle; the ends fade out.
                Item {
                    visible: column.levels
                    y: 62 * editor.unit
                    width: parent.width
                    height: editor.trackHeight * editor.unit
                    clip: true

                    Column {
                        id: levelList
                        readonly property real logicalY: editor.trackHeight / 2 - editor.levelRow / 2 -
                                                         (column.spec.selected || 0) * editor.levelRow
                        width: parent.width
                        y: logicalY * editor.unit
                        Behavior on y {
                            NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve }
                        }

                        Repeater {
                            model: column.levels ? column.spec.options : []

                            Item {
                                readonly property bool chosen: index === column.spec.selected
                                // Centre of this entry inside the list window, for the fade.
                                readonly property real centre: levelList.y / editor.unit + (index + 0.5) * editor.levelRow
                                readonly property real fade: 0.3 * editor.trackHeight
                                width: levelList.width
                                height: editor.levelRow * editor.unit
                                opacity: Math.max(0, Math.min(1, centre / fade)) *
                                         Math.max(0, Math.min(1, (editor.trackHeight - centre) / fade))

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14 * editor.unit
                                    anchors.rightMargin: 14 * editor.unit
                                    radius: GlassStyle.levelRadius * editor.unit
                                    visible: parent.chosen
                                    color: column.focused ? GlassStyle.levelChosenFocused : GlassStyle.levelChosenFill
                                }

                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData
                                    color: parent.chosen ? (column.focused ? GlassStyle.focusText : GlassStyle.textPrimary)
                                                         : column.quiet
                                    font.family: parent.chosen ? editor.titleFont : editor.rowFont
                                    font.pixelSize: (parent.chosen ? GlassStyle.levelChosenSize : GlassStyle.levelSize) * editor.unit
                                    font.hintingPreference: Font.PreferNoHinting
                                }
                            }
                        }
                    }
                }

                // The label, with a dot in the channel's colour.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (62 + editor.trackHeight + 14) * editor.unit
                    height: 24 * editor.unit
                    spacing: 6 * editor.unit

                    Rectangle {
                        visible: !!column.spec.dot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10 * editor.unit
                        height: width
                        radius: width / 2
                        color: column.spec.dot ? GlassStyle[column.spec.dot] : "transparent"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: column.spec.label || ""
                        color: column.quiet
                        font.family: editor.rowFont
                        font.pixelSize: GlassStyle.bandLabelSize * editor.unit
                        font.hintingPreference: Font.PreferNoHinting
                        Behavior on color { ColorAnimation { duration: GlassStyle.colorDuration } }
                    }
                }

                // Why the column is grey: "Nur bei Stufe 100 %".
                Text {
                    visible: column.spec.disabled === true && !!column.spec.reason
                    x: 8 * editor.unit
                    y: (62 + editor.trackHeight + 14 + 24 + 4) * editor.unit
                    width: parent.width - 16 * editor.unit
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: column.spec.reason || ""
                    color: GlassStyle.textDetail
                    font.family: editor.rowFont
                    font.pixelSize: GlassStyle.bandReasonSize * editor.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !column.spec.disabled
                    onClicked: editor.focusIndex = index
                }
            }
        }

        // Dividers between groups of columns and before the button.
        Repeater {
            model: editor.count + (editor.hasButton ? 1 : 0)

            Rectangle {
                readonly property bool last: index === editor.count
                readonly property bool between: index > 0 && index < editor.count &&
                                                editor.columns[index].group !== editor.columns[index - 1].group
                visible: last || between
                x: (last ? editor.padX + editor.bandsWidth + editor.separatorGap
                         : editor.bandX(index) - editor.separatorGap - 1) * editor.unit
                y: (editor.bandsY + (editor.bandHeight - editor.trackHeight) / 2) * editor.unit
                width: Math.max(1, editor.unit)
                height: editor.trackHeight * editor.unit
                color: GlassStyle.divider
            }
        }

        FooterButton {
            id: actionButton
            visible: editor.hasButton
            x: (editor.padX + editor.bandsWidth + 2 * editor.separatorGap + 1) * editor.unit +
               (editor.buttonArea * editor.unit - width) / 2
            y: (editor.bandsY + (editor.bandHeight - 64) / 2) * editor.unit
            unit: editor.unit
            fontFamily: editor.rowFont
            label: editor.buttonLabel
            danger: editor.buttonDanger
            focused: editor.onButton
            scale: focused ? GlassStyle.focusScale : 1
            onClicked: {
                editor.focusIndex = editor.count;
                editor.buttonPressed();
            }
        }
    }
}
