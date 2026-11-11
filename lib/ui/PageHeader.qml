import QtQuick 2.12
import "."

// Head of a page: back link, title and an optional second line (docs/design-system.md,
// "Klare Stufen"). Two named levels: the quick panel's 32 px title and the settings
// modal's 40 px title (large). The tip of the back arrow sits on the title's left edge.
// The owner places the header on the left edge and gives its width.
Item {
    id: header

    property real unit: 1
    property bool large: false
    property string back: ""            // text of the back link; empty hides it
    property string title: ""
    property string subtitle: ""
    // A device's page (K3-Einst-Bluetooth-Audio): an outlined badge beside the title ("Dolby
    // Atmos") and a small spinner before the second line while it connects.
    property string badge: ""
    property bool busy: false

    readonly property real titleY: back !== "" ? (large ? 34 : 32) : 0
    readonly property real titleHeight: large ? 48 : 38.4
    readonly property real subtitleY: titleY + (large ? 52 : 40)
    readonly property real subtitleHeight: large ? 26 : 23.4
    // In logical px, for owners that place their list below the header.
    readonly property real logicalHeight: subtitle !== "" ? subtitleY + subtitleHeight : titleY + titleHeight

    height: logicalHeight * unit

    Item {
        width: parent.width
        height: 28 * header.unit
        visible: header.back !== ""

        // The arrow's tip lies 6.75 px into its 18 px box.
        Image {
            x: -6.75 * header.unit
            anchors.verticalCenter: parent.verticalCenter
            width: 18 * header.unit
            height: width
            source: Qt.resolvedUrl("icons/back-18.png")
        }

        Text {
            x: (header.large ? 22 : 14) * header.unit
            width: parent.width - x
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: header.back
            color: GlassStyle.textSecondary
            font.family: GlassStyle.rowFont
            font.pixelSize: (header.large ? 19 : 18) * header.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    Text {
        id: titleText
        y: header.titleY * header.unit
        width: Math.min(implicitWidth, parent.width - (header.badge !== "" ? badgeBox.width + 18 * header.unit : 0))
        height: header.titleHeight * header.unit
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: header.title
        color: GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: (header.large ? GlassStyle.modalTitleSize : GlassStyle.titleSize) * header.unit
        font.letterSpacing: (header.large ? -0.8 : -0.64) * header.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Rectangle {
        id: badgeBox
        x: titleText.width + 18 * header.unit
        y: (header.titleY + (header.titleHeight - 32) / 2) * header.unit
        width: badgeText.implicitWidth + 24 * header.unit
        height: 32 * header.unit
        radius: 8 * header.unit
        visible: header.badge !== ""
        color: "transparent"
        border.width: 1.5 * header.unit
        border.color: GlassStyle.textSecondary

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: header.badge
            color: GlassStyle.textPrimary
            font.family: GlassStyle.titleFont
            font.pixelSize: GlassStyle.badgeSize * header.unit
            font.letterSpacing: 0.64 * header.unit
            font.capitalization: Font.AllUppercase
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    Spinner {
        y: (header.subtitleY + (header.subtitleHeight - 18) / 2) * header.unit
        visible: header.busy && header.subtitle !== ""
        size: 18 * header.unit
        lineWidth: 2.5 * header.unit
        running: visible
    }

    Text {
        x: (header.busy ? 28 : 0) * header.unit
        y: header.subtitleY * header.unit
        width: parent.width - x
        height: header.subtitleHeight * header.unit
        visible: header.subtitle !== ""
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: header.subtitle
        color: GlassStyle.textSecondary
        font.family: GlassStyle.valueFont
        font.pixelSize: (header.large ? 20 : 18) * header.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
