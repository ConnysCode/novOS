import QtQuick 2.12
import "."

// Glass popover left of the panel: a list of values or the time of a timer. It sits
// outside the panel, so the panel keeps its backdrop crop wide enough to serve both.
// An owner elsewhere sets x, y and width itself; the rows follow the width. An option
// may carry a second line (detail), for example the genres of the game bar.
Item {
    id: popover

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property variant backdrop
    property string glassShader: ""
    property string shadowShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property var curve: GlassStyle.curve
    property real anchorY: 0                 // screen centre of the row that opened it

    property bool shown: false
    property string kind: "list"             // list or time
    property string title: ""
    property var options: []                 // [{ label, value, detail (optional) }]
    property string selected: ""
    property string focusId: ""
    property int hour: 0
    property int minute: 0

    signal chosen(string value)
    signal timeChosen(int hour, int minute)
    signal timerOff()

    readonly property int minuteStep: 5
    readonly property real boxHeight: (kind === "time" ? 448 :
                                       10 + 42 + options.length * 64 - 4 + 10) * unit
    readonly property rect focusRect: rectOf(focusId)
    readonly property real focusRadius: (focusId === "confirm" || focusId === "off" ? 32 :
                                         (kind === "time" ? 26 : 18)) * unit

    function openList(name, values, current, centre) {
        kind = "list";
        title = name;
        options = values;
        selected = current;
        anchorY = centre;
        var first = 0;
        for (var i = 0; i < values.length; i++) {
            if (values[i].value === current) first = i;
        }
        focusId = "option-" + first;
        shown = true;
    }

    function openTime(name, startHour, startMinute, centre) {
        kind = "time";
        title = name;
        hour = startHour;
        minute = startMinute;
        anchorY = centre;
        focusId = "minute";
        shown = true;
    }

    function close() {
        shown = false;
    }

    function rectOf(id) {
        var u = unit;
        if (id.indexOf("option-") === 0) {
            return Qt.rect(10 * u, (52 + Number(id.substring(7)) * 64) * u, width - 20 * u, 60 * u);
        }
        if (id === "hour") return Qt.rect(49 * u, 130 * u, 132 * u, 104 * u);
        if (id === "minute") return Qt.rect(219 * u, 130 * u, 132 * u, 104 * u);
        if (id === "confirm") return Qt.rect(28 * u, 294 * u, 344 * u, 64 * u);
        if (id === "off") return Qt.rect(28 * u, 366 * u, 344 * u, 64 * u);
        return Qt.rect(0, 0, 0, 0);
    }

    function stepTime(direction) {
        if (focusId === "hour") {
            hour = (hour + direction + 24) % 24;
        } else {
            // Values between the steps land on the next step.
            var rounded = direction > 0 ? Math.floor(minute / minuteStep) + 1
                                        : Math.ceil(minute / minuteStep) - 1;
            minute = (rounded * minuteStep + 60) % 60;
        }
    }

    function handleKey(key, autoRepeat) {
        var ok = Remote.isOk(key);
        if (kind === "list") {
            var index = Number(focusId.substring(7));
            if (key === Qt.Key_Up && index > 0) focusId = "option-" + (index - 1);
            else if (key === Qt.Key_Down && index < options.length - 1) focusId = "option-" + (index + 1);
            else if (ok && !autoRepeat) chosen(options[index].value);
            return;
        }
        if (focusId === "hour" || focusId === "minute") {
            if (key === Qt.Key_Up) stepTime(1);
            else if (key === Qt.Key_Down) stepTime(-1);
            else if (key === Qt.Key_Left) focusId = "hour";
            else if (key === Qt.Key_Right) focusId = "minute";
            else if (ok && !autoRepeat) focusId = "confirm";
        } else if (key === Qt.Key_Up) {
            focusId = focusId === "off" ? "confirm" : "minute";
        } else if (key === Qt.Key_Down) {
            focusId = "off";
        } else if (ok && !autoRepeat) {
            if (focusId === "confirm") timeChosen(hour, minute);
            else timerOff();
        }
    }

    function pad(value) {
        return (value < 10 ? "0" : "") + value;
    }

    // For Audio-Guidance: the title once, then what has the focus.
    readonly property var speech: speechOf(kind, focusId, hour, minute, options, selected)

    function speechOf(kind, focusId, hour, minute, options, selected) {
        var time = minute > 0 ? I18n.t("popover", "speech.time", { hour: hour, minute: minute,
                                                                    minute_padded: pad(minute) })
                              : I18n.t("popover", "speech.time_hour", { hour: hour });
        if (kind === "time") {
            if (focusId === "hour") return { intro: title + ", " + time, subject: "hour",
                                             text: I18n.t("popover", "speech.hour", { hour: hour }),
                                             change: String(hour) };
            if (focusId === "minute") return { intro: title + ", " + time, subject: "minute",
                                               text: I18n.t("popover", "speech.minute", { minute: minute }),
                                               change: String(minute) };
            if (focusId === "confirm") return { intro: title, subject: "confirm", text: I18n.t("popover", "speech.confirm_time", { time: time }) };
            return { intro: title, subject: "off", text: I18n.t("popover", "button.timer_off") };
        }
        var index = focusId.indexOf("option-") === 0 ? Number(focusId.substring(7)) : -1;
        var option = options[index];
        if (!option) return { intro: title, subject: "", text: "" };
        var chosen = option.value === selected ? I18n.t("popover", "speech.selected") : "";
        return { intro: title, subject: "option:" + option.value,
                 text: option.label + (option.detail ? ", " + option.detail : "") + (chosen !== "" ? ", " + chosen : ""),
                 change: chosen };
    }

    x: 840 * unit
    y: Math.max(40 * unit, Math.min(parent.height - boxHeight - 40 * unit, anchorY - boxHeight / 2))
    width: 400 * unit
    height: boxHeight
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 160 }
    }

    SoftShadow {
        unit: popover.unit
        boxWidth: popover.width
        boxHeight: popover.height
        radius: 28
        softness: 8
        drop: 8
        strength: 0.30
        pad: 40
    }

    ShaderEffect {
        anchors.fill: parent
        property variant backdrop: popover.backdrop
        property size panelSize: Qt.size(width, height)
        property real cornerRadius: 28 * popover.unit
        property real topLightWidth: 1.5 * popover.unit
        property real contourWidth: 1.25 * popover.unit
        property real glowHeight: 10 * popover.unit
        property real backdropMargin: popover.backdropMargin
        property point backdropOrigin: Qt.point(popover.x - popover.backdropArea.x,
                                                popover.y - popover.backdropArea.y)
        property size backdropArea: Qt.size(popover.backdropArea.width, popover.backdropArea.height)
        property real dim: 0
        property real hasBackdrop: popover.hasBackdrop
        property real edgeGain: GlassStyle.edgeGain
        vertexShader: GlassStyle.glassVertexShader
        fragmentShader: popover.glassShader
    }

    SectionTitle {
        x: 28 * popover.unit
        y: 22 * popover.unit
        unit: popover.unit
        text: popover.title
    }

    // Focus surface of the popover, without scaling.
    Rectangle {
        x: popover.focusRect.x
        y: popover.focusRect.y
        width: popover.focusRect.width
        height: popover.focusRect.height
        radius: popover.focusRadius
        color: GlassStyle.focusFill
        antialiasing: true

        Behavior on x {
            NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: popover.curve }
        }
        Behavior on y {
            NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: popover.curve }
        }
        Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: popover.curve }
        }
        Behavior on height {
            NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: popover.curve }
        }
    }

    // Value list.
    Repeater {
        model: popover.kind === "list" ? popover.options : []

        Item {
            readonly property bool focused: popover.focusId === "option-" + index
            x: 10 * popover.unit
            y: (52 + index * 64) * popover.unit
            width: popover.width - 20 * popover.unit
            height: 60 * popover.unit

            Column {
                x: 18 * popover.unit
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: modelData.label
                    color: parent.parent.focused ? GlassStyle.focusText : "#ffffff"
                    font.family: popover.rowFont
                    font.pixelSize: GlassStyle.rowSize * popover.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    visible: modelData.detail !== undefined && modelData.detail !== ""
                    text: modelData.detail || ""
                    color: parent.parent.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                    font.family: GlassStyle.valueFont
                    font.pixelSize: GlassStyle.detailSize * popover.unit
                    font.hintingPreference: Font.PreferNoHinting
                }
            }

            Image {
                x: parent.width - 42 * popover.unit
                anchors.verticalCenter: parent.verticalCenter
                visible: popover.selected === modelData.value
                source: Qt.resolvedUrl(parent.focused ? "icons/check-24-dark.png" : "icons/check-24.png")
            }

            MouseArea {
                anchors.fill: parent
                onClicked: popover.chosen(modelData.value)
            }
        }
    }

    // Time of a timer.
    Repeater {
        model: popover.kind === "time" ? [{ id: "hour", x: 49, label: I18n.t("popover", "label.hour") },
                                          { id: "minute", x: 219, label: I18n.t("popover", "label.minute") }] : []

        Item {
            id: spin
            readonly property bool focused: popover.focusId === modelData.id
            readonly property bool isHour: modelData.id === "hour"
            readonly property int value: isHour ? popover.hour : popover.minute
            readonly property int step: isHour ? 1 : popover.minuteStep
            readonly property int range: isHour ? 24 : 60
            x: modelData.x * popover.unit
            width: 132 * popover.unit
            height: popover.height

            SectionTitle {
                y: 58 * popover.unit
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                unit: popover.unit
                text: modelData.label
            }

            Repeater {
                model: [{ y: 88, offset: -1 }, { y: 240, offset: 1 }]

                Text {
                    y: modelData.y * popover.unit
                    width: spin.width
                    height: 36 * popover.unit
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: popover.pad((spin.value + modelData.offset * spin.step + spin.range) % spin.range)
                    color: "#80ffffff"
                    font.family: popover.rowFont
                    font.pixelSize: 24 * popover.unit
                    font.hintingPreference: Font.PreferNoHinting
                }
            }

            GlassControl {
                y: 130 * popover.unit
                width: parent.width
                height: 104 * popover.unit
                visible: !spin.focused
                unit: popover.unit
                radius: 26
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 134 * popover.unit
                rotation: -90
                visible: spin.focused
                source: Qt.resolvedUrl("icons/chevron-18-dark.png")
            }

            Text {
                y: 154 * popover.unit
                width: parent.width
                height: 56 * popover.unit
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: popover.pad(spin.value)
                color: spin.focused ? GlassStyle.focusText : "#ffffff"
                font.family: popover.titleFont
                font.pixelSize: 48 * popover.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 212 * popover.unit
                rotation: 90
                visible: spin.focused
                source: Qt.resolvedUrl("icons/chevron-18-dark.png")
            }
        }
    }

    Text {
        x: 193 * popover.unit
        y: 154 * popover.unit
        width: 14 * popover.unit
        height: 56 * popover.unit
        visible: popover.kind === "time"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: ":"
        color: GlassStyle.textSecondary
        font.family: popover.titleFont
        font.pixelSize: 44 * popover.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Repeater {
        model: popover.kind === "time" ? [{ id: "confirm", y: 294, label: I18n.t("popover", "button.confirm") },
                                          { id: "off", y: 366, label: I18n.t("popover", "button.timer_off") }] : []

        Item {
            readonly property bool focused: popover.focusId === modelData.id
            x: 28 * popover.unit
            y: modelData.y * popover.unit
            width: 344 * popover.unit
            height: 64 * popover.unit

            GlassControl {
                anchors.fill: parent
                visible: !parent.focused
                unit: popover.unit
                radius: 32
            }

            Text {
                anchors.centerIn: parent
                text: modelData.label
                color: parent.focused ? GlassStyle.focusText : "#ffffff"
                font.family: popover.rowFont
                font.pixelSize: 20 * popover.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }
    }
}
