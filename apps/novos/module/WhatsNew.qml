import QtQuick 2.12
import "."

// "Neu in novOS" after a minor or major update (K3-Neu-1 … 4), over Home or the last source:
// on top a picture, the horizon of the website with the version and a slowly pulsing sun,
// then up to four novelties, a line with what was fixed, and "Alle Neuerungen" / "Weiter".
// Up and Down choose a novelty; the picture fades to its motif when the release brings one
// (release-art/<version>/), OK opens it. The focus starts on "Weiter", so OK closes at once.
// The source window shows it; a patch only gets its notice (K3-Neu-5).
Item {
    id: news

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property variant backdrop
    property string glassShader: ""
    property real backdropMargin: 0
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    property bool shown: false

    property string version: ""          // "0.9.0-beta.9"
    property string installedText: ""    // "Installiert heute um 3:12 Uhr. …"
    property var items: []               // features: { title, text, icon, open, image (URL) }
    property string fixedText: ""        // "Außerdem behoben: …"
    property int focusIndex: items.length + 1      // rows, then "Alle Neuerungen", "Weiter"

    signal openItem(var item)
    signal allNews()
    signal done()

    readonly property bool onRow: focusIndex < items.length
    readonly property string motif: onRow && items[focusIndex].image ? items[focusIndex].image : ""
    // The number on the picture: major and minor, the patch only when there is one.
    readonly property string shortVersion: {
        var parts = version.split("-")[0].split(".");
        return parts.length < 3 ? version : parts[0] + "." + parts[1] + (parts[2] !== "0" ? "." + parts[2] : "");
    }
    readonly property real listY: 14 + 300 + 30 + 46 + 6 + 28 + 22
    readonly property real fixedY: listY + items.length * 88 + Math.max(0, items.length - 1) * 4 + 16
    readonly property real buttonsY: fixedY + (fixedText !== "" ? 26 : -16) + 28

    width: 1040 * unit
    height: (buttonsY + 72 + 36) * unit
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: GlassStyle.popoverDuration }
    }

    function handleKey(key) {
        var rows = items.length;
        if (key === Qt.Key_Up) {
            if (focusIndex >= rows) focusIndex = Math.max(0, rows - 1);
            else focusIndex = Math.max(0, focusIndex - 1);
            if (rows === 0) focusIndex = rows + 1;
        } else if (key === Qt.Key_Down) {
            if (focusIndex < rows - 1) focusIndex += 1;
            else if (focusIndex === rows - 1) focusIndex = rows + 1;
        } else if (key === Qt.Key_Left && focusIndex === rows + 1) {
            focusIndex = rows;
        } else if (key === Qt.Key_Right && focusIndex === rows) {
            focusIndex = rows + 1;
        } else if (Remote.isOk(key)) {
            if (focusIndex < rows) {
                if (items[focusIndex].open) news.openItem(items[focusIndex]);
            } else if (focusIndex === rows) {
                news.allNews();
            } else {
                news.done();
            }
        } else {
            return Remote.isArrow(key);
        }
        return true;
    }

    GlassCard {
        anchors.fill: parent
        unit: news.unit
        backdrop: news.backdrop
        glassShader: news.glassShader
        backdropMargin: news.backdropMargin
        backdropArea: news.backdropArea
        hasBackdrop: news.hasBackdrop
        glides: false
    }

    // ---- Picture -----------------------------------------------------------------------

    Item {
        x: 14 * news.unit
        y: 14 * news.unit
        width: 1012 * news.unit
        height: 300 * news.unit

        // The version's own picture: the horizon, the pulsing sun, the word mark and number.
        Item {
            anchors.fill: parent
            opacity: news.motif === "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }

            Image {
                anchors.fill: parent
                smooth: true
                source: Qt.resolvedUrl("release-art/hero.png")
            }

            Image {
                id: sun
                anchors.fill: parent
                smooth: true
                source: Qt.resolvedUrl("release-art/sun.png")
                transformOrigin: Item.Center
                // Breathes over seven seconds, as on the website.
                SequentialAnimation on opacity {
                    running: news.shown
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.86; to: 1; duration: 3500; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0.86; duration: 3500; easing.type: Easing.InOutSine }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: (300 - 92 - 30 - 2 - 112) * news.unit
                spacing: 2 * news.unit

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: 0.9
                    Text {
                        text: "nov"
                        color: GlassStyle.textPrimary
                        font.family: news.titleFont
                        font.pixelSize: 30 * news.unit
                        font.letterSpacing: -1 * news.unit
                    }
                    Text {
                        text: "OS"
                        color: GlassStyle.textSecondary
                        font.family: news.valueFont
                        font.pixelSize: 30 * news.unit
                        font.letterSpacing: -1 * news.unit
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 112 * news.unit
                    verticalAlignment: Text.AlignVCenter
                    text: news.shortVersion
                    color: GlassStyle.textPrimary
                    font.family: news.valueFont
                    font.pixelSize: 124 * news.unit
                    font.letterSpacing: -6 * news.unit
                }
            }
        }

        // The motif of the chosen novelty, faded in over the version's picture.
        Image {
            anchors.fill: parent
            smooth: true
            source: news.motif
            opacity: news.motif === "" ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: GlassStyle.pageDuration } }
        }
    }

    // ---- Texts and novelties -------------------------------------------------------------

    Text {
        x: 54 * news.unit
        y: (14 + 300 + 30) * news.unit
        width: (1040 - 108) * news.unit
        elide: Text.ElideRight
        text: I18n.t("picker", "whatsnew.title", { version: news.version })
        color: GlassStyle.textPrimary
        font.family: news.titleFont
        font.pixelSize: 38 * news.unit
        font.letterSpacing: -0.76 * news.unit
    }

    Text {
        x: 54 * news.unit
        y: (14 + 300 + 30 + 46 + 6) * news.unit
        width: (1040 - 108) * news.unit
        elide: Text.ElideRight
        text: news.installedText
        color: GlassStyle.textSecondary
        font.family: news.valueFont
        font.pixelSize: 20 * news.unit
    }

    FocusSurface {
        x: 40 * news.unit
        y: (news.listY + Math.min(news.focusIndex, news.items.length - 1) * 92) * news.unit
        width: 960 * news.unit
        height: 88 * news.unit
        radius: 26
        unit: news.unit
        focusScale: GlassStyle.focusScale
        visible: news.onRow
    }

    Repeater {
        model: news.items
        Item {
            readonly property bool focused: news.focusIndex === index
            x: 40 * news.unit
            y: (news.listY + index * 92) * news.unit
            width: 960 * news.unit
            height: 88 * news.unit

            GlassControl {
                x: 14 * news.unit
                anchors.verticalCenter: parent.verticalCenter
                width: 56 * news.unit
                height: width
                radius: 28
                unit: news.unit
                visible: !parent.focused
            }

            Rectangle {
                x: 14 * news.unit
                anchors.verticalCenter: parent.verticalCenter
                width: 56 * news.unit
                height: width
                radius: width / 2
                color: GlassStyle.trackFocused
                visible: parent.focused
            }

            Image {
                x: (14 + 14) * news.unit
                anchors.verticalCenter: parent.verticalCenter
                width: 28 * news.unit
                height: width
                smooth: true
                source: Qt.resolvedUrl("icons/feature-" + (modelData.icon || "sparkle") + "-28" +
                                       (parent.focused ? "-dark" : "") + ".png")
            }

            Column {
                x: 88 * news.unit
                width: parent.width - x - (parent.focused && modelData.open ? 140 : 20) * news.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * news.unit

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.title || ""
                    color: parent.parent.focused ? GlassStyle.focusText : GlassStyle.textPrimary
                    font.family: news.rowFont
                    font.pixelSize: 23 * news.unit
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.text || ""
                    color: parent.parent.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                    font.family: news.valueFont
                    font.pixelSize: 18 * news.unit
                }
            }

            // "Öffnen ›" on the chosen novelty.
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20 * news.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * news.unit
                visible: parent.focused && !!modelData.open

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.t("picker", "whatsnew.open")
                    color: GlassStyle.focusSecondary
                    font.family: news.rowFont
                    font.pixelSize: 18 * news.unit
                }

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl("icons/chevron-18-dark.png")
                }
            }
        }
    }

    Text {
        x: 54 * news.unit
        y: news.fixedY * news.unit
        width: (1040 - 108) * news.unit
        visible: news.fixedText !== ""
        elide: Text.ElideRight
        text: news.fixedText
        color: GlassStyle.textSecondary
        font.family: news.valueFont
        font.pixelSize: 18 * news.unit
    }

    Row {
        x: 40 * news.unit
        y: news.buttonsY * news.unit
        spacing: 12 * news.unit

        FooterButton {
            width: 474 * news.unit
            unit: news.unit
            size: 72
            fontFamily: news.rowFont
            label: I18n.t("picker", "whatsnew.all")
            ownFocus: true
            focused: news.focusIndex === news.items.length
            onClicked: news.allNews()
        }

        FooterButton {
            width: 474 * news.unit
            unit: news.unit
            size: 72
            fontFamily: news.rowFont
            label: I18n.t("picker", "whatsnew.next")
            ownFocus: true
            focused: news.focusIndex === news.items.length + 1
            onClicked: news.done()
        }
    }
}
