import QtQuick 2.12
import WebOS.Global 1.0
import WebOSServices 1.0
import "."
import "RemoteKeys.js" as RemoteKeys

// "Fernbedienung erlernen" (BF-2, K3-Einst-Fernbedienung): over the dimmed picture a glass card
// explains each key the user presses, what it does under novOS when pressed short and long
// (RemoteKeys.js). Every key but power is caught and does nothing else; Back twice in a row
// ends it, any other key between starts the count again. The owner hands every key to press()
// and Back to back(), and closes on finished. It fills the screen; its glass samples the
// owner's crop like a GlassCard.
Item {
    id: guide

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property variant backdrop
    property string glassShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property bool active: false

    property var shown: null          // { entry, digit } of the last key, null at the start
    property bool backArmed: false    // Back was pressed once
    property bool keysTaken: false    // the surface manager hands the system keys to us
    signal finished()

    readonly property var entry: shown ? shown.entry : null
    readonly property string name: entry ? keyName(shown) : ""
    readonly property string shortText: entry ? effect(entry.short, "guide.as_app") : ""
    readonly property string longText: entry && entry.long ? effect(entry.long, "") : ""
    readonly property bool placeholder: !!entry && entry.placeholder === true

    function t(key, params) {
        return I18n.t("settings_accessibility", key, params);
    }

    function keyName(found) {
        if (found.entry.id === "digit") return t("guide.key_digit", { digit: found.digit });
        return t("guide.key_" + found.entry.id);
    }

    // A placeholder stands in brackets until the assignment is settled.
    function effect(key, fallback) {
        if (!key) return fallback ? t(fallback) : "";
        return entry.placeholder ? "[" + t(key) + "]" : t(key);
    }

    function start() {
        shown = null;
        backArmed = false;
        allowKeys(true);
    }

    function stop() {
        allowKeys(false);
    }

    function press(key) {
        backArmed = false;
        shown = RemoteKeys.find(key, function (name) { return Qt[name]; },
                                function (name) { return WebOS[name]; });
    }

    function back() {
        if (backArmed) {
            finished();
            return;
        }
        shown = RemoteKeys.find(WebOS.Key_webOS_Back, function (name) { return Qt[name]; },
                                function (name) { return WebOS[name]; });
        backArmed = true;
    }

    // What the audio guide reads: the name, then short, then long.
    readonly property var speech: entry ?
        { subject: entry.id + (shown.digit >= 0 ? shown.digit : "") + (backArmed ? "-armed" : ""),
          text: [name, t("guide.short") + ": " + shortText,
                 longText !== "" ? t("guide.long") + ": " + longText : "",
                 backArmed ? t("guide.back_again") : ""].filter(function (part) { return part !== ""; }).join(", ") } :
        { subject: "start", text: [t("row.remote_guide"), t("guide.press_key"), t("guide.power_excepted")].join(", ") }

    // As LG's guide: the surface manager hands the system keys to this window while it runs.
    function allowKeys(on) {
        if (keysTaken === on) return;
        keysTaken = on;
        keyService.call("luna://com.webos.surfacemanager.input", "/registerAllowedKey",
                        JSON.stringify({ keyList: on ? RemoteKeys.allowedKeys : [], whitelist: false }));
    }

    Service {
        id: keyService
        appId: "com.webos.app.quicksettings"
    }

    // ---- The card ----------------------------------------------------------------------------

    readonly property real cardWidth: entry ? 1080 : 820
    readonly property real padX: 56
    readonly property real padTop: entry ? 48 : 56
    readonly property real padBottom: entry ? 48 : 52

    GlassCard {
        id: card
        width: guide.cardWidth * guide.unit
        height: (guide.padTop + guide.padBottom) * guide.unit + (guide.entry ? keyBody.height : startBody.height)
        x: (guide.width - width) / 2
        // As translate(-50%, -54%): a little above the middle.
        y: guide.height / 2 - 0.54 * height
        glides: false
        unit: guide.unit
        backdrop: guide.backdrop
        glassShader: guide.glassShader
        backdropMargin: guide.backdropMargin
        backdropArea: guide.backdropArea
        hasBackdrop: guide.hasBackdrop

        // Start: an icon, the title and how it works (-02, -03).
        Column {
            id: startBody
            visible: !guide.entry
            x: guide.padX * guide.unit
            y: guide.padTop * guide.unit
            width: parent.width - 2 * guide.padX * guide.unit

            Item {
                width: parent.width
                height: 96 * guide.unit

                GlassControl {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96 * guide.unit
                    height: width
                    unit: guide.unit
                    radius: 48
                    fill: GlassStyle.circleFill

                    Image {
                        anchors.centerIn: parent
                        width: 48 * guide.unit
                        height: width
                        sourceSize.width: width
                        sourceSize.height: height
                        source: "icons/remote-guide-48.png"
                    }
                }
            }

            Item { width: 1; height: 28 * guide.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: guide.t("row.remote_guide")
                color: GlassStyle.textPrimary
                font.family: guide.titleFont
                font.pixelSize: GlassStyle.guideStartTitle * guide.unit
                font.letterSpacing: -0.88 * guide.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Item { width: 1; height: 16 * guide.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: guide.t("guide.press_key")
                color: GlassStyle.textPrimary
                font.family: guide.rowFont
                font.pixelSize: GlassStyle.guideEffectSize * guide.unit
                font.hintingPreference: Font.PreferNoHinting
            }

            Item { width: 1; height: 8 * guide.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: guide.t("guide.power_excepted")
                color: GlassStyle.textSecondary
                font.family: guide.valueFont
                font.pixelSize: GlassStyle.dialogTextSize * guide.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }

        // A key: the key on the left, its name, short and long on the right (-04 … -12).
        Item {
            id: keyBody
            visible: !!guide.entry
            x: guide.padX * guide.unit
            y: guide.padTop * guide.unit
            width: parent.width - 2 * guide.padX * guide.unit
            height: Math.max(GlassStyle.guideKeySize * guide.unit, texts.height)

            GlassControl {
                id: plate
                anchors.verticalCenter: parent.verticalCenter
                width: GlassStyle.guideKeySize * guide.unit
                height: width
                unit: guide.unit
                radius: 48
                fill: GlassStyle.guideKeyFill

                Image {
                    anchors.centerIn: parent
                    visible: !!guide.entry && !!guide.entry.icon
                    width: GlassStyle.guideKeyIcon * guide.unit
                    height: width
                    sourceSize.width: width
                    sourceSize.height: height
                    source: guide.entry && guide.entry.icon ? "icons/" + guide.entry.icon + ".png" : ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: !!guide.entry && (!!guide.entry.label || guide.entry.id === "digit")
                    text: !guide.entry ? "" : (guide.entry.id === "digit" ? String(guide.shown.digit) : (guide.entry.label || ""))
                    color: GlassStyle.textPrimary
                    font.family: guide.titleFont
                    font.pixelSize: GlassStyle.guideKeyLabel * guide.unit
                    font.letterSpacing: -1.28 * guide.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: !!guide.entry && !!guide.entry.dot
                    width: GlassStyle.guideDot * guide.unit
                    height: width
                    radius: width / 2
                    color: guide.entry && guide.entry.dot ? GlassStyle[guide.entry.dot] : "transparent"
                }
            }

            Column {
                id: texts
                anchors.verticalCenter: parent.verticalCenter
                x: plate.width + 48 * guide.unit
                width: parent.width - x

                Text {
                    width: parent.width
                    text: guide.t("row.remote_guide").toUpperCase()
                    color: GlassStyle.textMuted
                    font.family: guide.rowFont
                    font.bold: true
                    font.pixelSize: GlassStyle.eyebrowSize * guide.unit
                    font.letterSpacing: GlassStyle.sectionTracking * guide.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item { width: 1; height: 8 * guide.unit }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: guide.name
                    color: GlassStyle.textPrimary
                    font.family: guide.titleFont
                    font.pixelSize: GlassStyle.guideNameSize * guide.unit
                    font.letterSpacing: -0.96 * guide.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item { width: 1; height: 24 * guide.unit }

                Repeater {
                    model: guide.longText !== "" ? [{ chip: guide.t("guide.short"), text: guide.shortText },
                                                    { chip: guide.t("guide.long"), text: guide.longText }]
                                                 : [{ chip: guide.t("guide.short"), text: guide.shortText }]

                    Item {
                        width: texts.width
                        // 16 px between short and long.
                        height: Math.max(36 * guide.unit, effects.height) + (index > 0 ? 16 * guide.unit : 0)

                        // "Kurz", "Lang".
                        GlassControl {
                            id: chip
                            y: index > 0 ? 16 * guide.unit : 0
                            width: chipText.implicitWidth + 32 * guide.unit
                            height: 36 * guide.unit
                            unit: guide.unit
                            radius: 18
                            fill: GlassStyle.guideChipFill

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData.chip
                                color: GlassStyle.textPrimary
                                font.family: guide.rowFont
                                font.bold: true
                                font.pixelSize: GlassStyle.guideChipSize * guide.unit
                                font.hintingPreference: Font.PreferNoHinting
                            }
                        }

                        Flow {
                            id: effects
                            x: chip.width + 16 * guide.unit
                            y: chip.y
                            width: parent.width - x
                            spacing: 12 * guide.unit

                            Text {
                                id: effectText
                                width: Math.min(implicitWidth, parent.width)
                                wrapMode: Text.WordWrap
                                text: modelData.text
                                color: GlassStyle.textPrimary
                                font.family: guide.rowFont
                                font.pixelSize: GlassStyle.guideEffectSize * guide.unit
                                lineHeight: 36 * guide.unit
                                lineHeightMode: Text.FixedHeight
                                font.hintingPreference: Font.PreferNoHinting
                            }

                            // "Platzhalter": the assignment is not settled.
                            Rectangle {
                                visible: guide.placeholder
                                y: (36 * guide.unit - height) / 2
                                width: markText.implicitWidth + 20 * guide.unit
                                height: 26 * guide.unit
                                radius: height / 2
                                color: "transparent"
                                border.width: 1.5 * guide.unit
                                border.color: GlassStyle.guideMarkLine

                                Text {
                                    id: markText
                                    anchors.centerIn: parent
                                    text: guide.t("guide.placeholder")
                                    color: GlassStyle.guideMarkText
                                    font.family: guide.rowFont
                                    font.bold: true
                                    font.pixelSize: GlassStyle.guideMarkSize * guide.unit
                                    font.letterSpacing: 0.56 * guide.unit
                                    font.hintingPreference: Font.PreferNoHinting
                                }
                            }
                        }
                    }
                }

                // After the first Back: one more ends it (-12).
                Item {
                    visible: guide.backArmed
                    width: 1
                    height: visible ? 28 * guide.unit : 0
                }

                Rectangle {
                    visible: guide.backArmed
                    width: againRow.width + 48 * guide.unit
                    height: visible ? 64 * guide.unit : 0
                    radius: 32 * guide.unit
                    color: GlassStyle.focusFill

                    Row {
                        id: againRow
                        anchors.centerIn: parent
                        spacing: 12 * guide.unit

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24 * guide.unit
                            height: width
                            sourceSize.width: width
                            sourceSize.height: height
                            source: "icons/return-24-dark.png"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: guide.t("guide.back_again")
                            color: GlassStyle.focusText
                            font.family: guide.rowFont
                            font.bold: true
                            font.pixelSize: 22 * guide.unit
                            font.hintingPreference: Font.PreferNoHinting
                        }
                    }
                }
            }
        }
    }

    // The legend at the bottom: "Zurück, Zurück: Beenden", a pill as the notice bar.
    GlassCard {
        width: legendRow.width + 52 * guide.unit
        height: 56 * guide.unit
        cornerRadius: 28 * guide.unit
        shadow: ""
        x: (guide.width - width) / 2
        y: guide.height - height - GlassStyle.bottomBarInset * guide.unit
        glides: false
        unit: guide.unit
        backdrop: guide.backdrop
        glassShader: guide.glassShader
        backdropMargin: guide.backdropMargin
        backdropArea: guide.backdropArea
        hasBackdrop: guide.hasBackdrop

        Row {
            id: legendRow
            anchors.centerIn: parent
            spacing: 10 * guide.unit

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 22 * guide.unit
                height: width
                sourceSize.width: width
                sourceSize.height: height
                source: "icons/return-22.png"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: guide.t("guide.legend")
                color: GlassStyle.textSecondary
                font.family: guide.rowFont
                font.pixelSize: GlassStyle.guideChipSize * guide.unit
                font.hintingPreference: Font.PreferNoHinting
            }
        }
    }
}
