import QtQuick 2.12

// An inner card with a heading in capitals and entries with pictures (IconLine),
// 14 px apart, as in "novOS ersetzt" / "Bleibt wie es ist".
InsetCard {
    id: card

    property string heading: ""
    property var items: []

    SectionTitle {
        x: 28 * card.unit
        y: 26 * card.unit
        unit: card.unit
        text: card.heading
        color: GlassStyle.textSecondary
        font.letterSpacing: 1.28 * card.unit
    }

    Column {
        x: 28 * card.unit
        y: 62 * card.unit
        width: parent.width - 56 * card.unit
        spacing: 14 * card.unit

        Repeater {
            model: card.items
            IconLine {
                width: parent.width
                unit: card.unit
                icon: modelData.icon
                title: modelData.title
                detail: modelData.detail || ""
            }
        }
    }
}
