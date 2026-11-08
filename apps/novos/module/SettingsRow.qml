import QtQuick 2.12
import "."

// One entry of a settings page: a section title, a note under a list or a row with its
// value, switch, slider, chevron, check or the ↗ of an LG app. Positions come from the
// modal's layout, in logical px.
Item {
    id: cell

    property var entry: ({})
    property var owner: null

    readonly property real unit: owner ? owner.unit : 1
    readonly property bool isRow: entry.kind === "row"
    readonly property var row: isRow ? entry.row : ({ title: "", subtitle: "", value: "", type: "" })
    readonly property bool focused: !!owner && isRow && owner.zone === "content" && owner.focusIndex === entry.index
    readonly property bool twoLines: row.subtitle !== "" && row.subtitle !== undefined
    readonly property bool slider: row.type === "slider"
    readonly property real logicalHeight: entry.h || 30
    readonly property bool hasChevron: row.type === "page" || row.type === "choice" ||
                                       (row.type === "listItem" && row.selected !== true && row.external !== true)
    readonly property string titleFont: owner ? owner.rowFont : ""
    readonly property string valueFont: owner ? owner.valueFont : ""

    y: (entry.y || 0) * unit
    width: (owner ? owner.paneWidth : 1120) * unit
    height: logicalHeight * unit

    // Head block of Über novOS: a light plate with the word mark, a line, version and TV.
    // Only that page has one, so the other rows do not build its texts at all.
    Loader {
        anchors.fill: parent
        active: cell.entry.kind === "hero"
        sourceComponent: Component {
            Item {
                anchors.fill: parent

                GlassControl {
                    anchors.fill: parent
                    unit: cell.unit
                    radius: 28
                    fill: "#14ffffff"
                }

                Row {
                    id: wordMark
                    x: 28 * cell.unit
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "nov"
                        color: "#ffffff"
                        font.family: cell.owner ? cell.owner.titleFont : ""
                        font.pixelSize: 64 * cell.unit
                        font.letterSpacing: -2.2 * cell.unit
                    }

                    Text {
                        text: "OS"
                        color: GlassStyle.textSecondary
                        font.family: cell.valueFont
                        font.pixelSize: 64 * cell.unit
                        font.letterSpacing: -2.2 * cell.unit
                    }
                }

                Rectangle {
                    x: wordMark.x + wordMark.width + 28 * cell.unit
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, cell.unit)
                    height: 60 * cell.unit
                    color: "#29ffffff"
                }

                Column {
                    x: wordMark.x + wordMark.width + 57 * cell.unit
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * cell.unit

                    Text {
                        text: cell.entry.hero ? cell.entry.hero.title : ""
                        visible: text !== ""
                        color: "#ffffff"
                        font.family: cell.titleFont
                        font.pixelSize: 24 * cell.unit
                    }

                    Text {
                        text: cell.entry.hero ? cell.entry.hero.text : ""
                        visible: text !== ""
                        color: GlassStyle.textSecondary
                        font.family: cell.valueFont
                        font.pixelSize: 18 * cell.unit
                    }
                }
            }
        }
    }

    // Section title: 16 px, capitals, 60 % white.
    SectionTitle {
        x: 20 * cell.unit
        visible: cell.entry.kind === "section"
        unit: cell.unit
        text: cell.entry.kind === "section" ? String(cell.entry.text) : ""
    }

    // Note under a list: 18 px, 72 % white, at most 760 px wide.
    Text {
        x: 20 * cell.unit
        width: 760 * cell.unit
        visible: cell.entry.kind === "note"
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: cell.entry.kind === "note" ? cell.entry.text : ""
        color: GlassStyle.textSecondary
        font.family: cell.valueFont
        font.pixelSize: 18 * cell.unit
        lineHeight: 1.45
    }

    // The row itself: the shared GlassRow, as in the quick panel.
    GlassRow {
        anchors.fill: parent
        visible: cell.isRow
        unit: cell.unit
        titleFont: cell.titleFont
        valueFont: cell.valueFont
        focused: cell.focused
        title: cell.row.title || ""
        subtitle: cell.row.subtitle || ""
        value: cell.row.type === "toggle" ? "" : (cell.row.value || "")
        mark: cell.row.external === true ? "external" :
              (cell.row.selected === true ? "check" : (cell.hasChevron ? "chevron" : ""))
        toggle: cell.row.type === "toggle" ? cell.row.on === true : undefined
        sliderShare: cell.slider && cell.row.max > cell.row.min ?
                     (cell.row.number - cell.row.min) / (cell.row.max - cell.row.min) : -1
        danger: cell.row.danger === true
        disabled: cell.row.disabled === true

        MouseArea {
            anchors.fill: parent
            enabled: cell.isRow
            onClicked: {
                cell.owner.zone = "content";
                cell.owner.focusIndex = cell.entry.index;
                cell.owner.activate(cell.row);
            }
        }
    }
}
