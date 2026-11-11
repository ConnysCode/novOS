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
    readonly property bool isTile: entry.kind === "tile"
    readonly property var row: isRow || isTile ? entry.row : ({ title: "", subtitle: "", value: "", type: "" })
    readonly property bool focused: !!owner && (isRow || isTile) && owner.zone === "content" &&
                                    owner.focusIndex === entry.index
    readonly property bool twoLines: row.subtitle !== "" && row.subtitle !== undefined
    readonly property bool slider: row.type === "slider"
    readonly property real logicalHeight: entry.h || 30
    readonly property bool hasChevron: row.type === "page" || row.type === "choice" ||
                                       (row.type === "listItem" && row.selected !== true && row.external !== true)
    readonly property string titleFont: owner ? owner.rowFont : ""
    readonly property string valueFont: owner ? owner.valueFont : ""

    x: (entry.x || 0) * unit
    y: (entry.y || 0) * unit
    width: (entry.w || (owner ? owner.paneWidth : 1120)) * unit
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

    // A large heading with a text at the right, as "Neu in 1.0" and its date (K3-NovUpdate).
    Item {
        anchors.fill: parent
        visible: cell.entry.kind === "heading"

        Text {
            x: 20 * cell.unit
            text: cell.entry.kind === "heading" ? cell.entry.heading.title : ""
            color: GlassStyle.textPrimary
            font.family: cell.owner ? cell.owner.titleFont : ""
            font.pixelSize: 24 * cell.unit
            font.hintingPreference: Font.PreferNoHinting
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 20 * cell.unit
            anchors.baseline: parent.top
            anchors.baselineOffset: 23 * cell.unit
            text: cell.entry.kind === "heading" ? cell.entry.heading.aside || "" : ""
            color: GlassStyle.textSecondary
            font.family: cell.valueFont
            font.pixelSize: 18 * cell.unit
            font.hintingPreference: Font.PreferNoHinting
        }
    }

    // The state of a task with its buttons (StatusCard) and release notes (NoteList); only
    // rows of that type build them.
    Loader {
        anchors.fill: parent
        active: cell.isRow && cell.row.type === "statusCard"
        sourceComponent: Component {
            StatusCard {
                readonly property var card: cell.row.card || ({})
                unit: cell.unit
                titleFont: cell.owner ? cell.owner.titleFont : ""
                rowFont: cell.titleFont
                valueFont: cell.valueFont
                icon: card.icon || "check"
                title: card.title || ""
                text: card.text || ""
                progress: card.progress === undefined ? -1 : card.progress
                progressText: card.progressText || ""
                progressValue: card.progressValue || ""
                buttons: card.buttons || []
                focusIndex: cell.focused ? cell.owner.cardFocus : -1
                onButtonClicked: {
                    cell.owner.zone = "content";
                    cell.owner.focusIndex = cell.entry.index;
                    cell.owner.cardFocus = index;
                    cell.owner.pressCard(index);
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: cell.isRow && cell.row.type === "notes"
        sourceComponent: Component {
            NoteList {
                unit: cell.unit
                titleFont: cell.titleFont
                valueFont: cell.valueFont
                items: cell.row.notes || []
                focused: cell.focused
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

    // A tile (K3-Ausschalt-2): the shared OptionCard as a media tile; the modal's single
    // surface is its focus. Only tiles build it.
    Loader {
        anchors.fill: parent
        active: cell.isTile
        sourceComponent: Component {
            OptionCard {
                unit: cell.unit
                media: true
                ownFocus: false
                focused: cell.focused
                selected: cell.row.selected === true
                title: cell.row.title || ""
                subtitle: cell.row.subtitle || ""

                ShutdownThumb {
                    anchors.fill: parent
                    unit: cell.unit
                    item: cell.row.item || ({})
                    focused: cell.focused
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        cell.owner.zone = "content";
                        cell.owner.focusIndex = cell.entry.index;
                        cell.owner.activate(cell.row);
                    }
                }
            }
        }
    }

    // The keys of a page and what they do: a key cap, its text, a dot between two.
    Row {
        x: 20 * cell.unit
        height: parent.height
        visible: cell.entry.kind === "keys"
        spacing: 12 * cell.unit

        Repeater {
            model: cell.entry.kind === "keys" ? cell.entry.keys : []

            Row {
                height: 30 * cell.unit
                spacing: 12 * cell.unit

                Text {
                    visible: index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: "#66ffffff"
                    font.family: cell.valueFont
                    font.pixelSize: 18 * cell.unit
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(30 * cell.unit, capText.width + 20 * cell.unit)
                    height: 30 * cell.unit
                    radius: 9 * cell.unit
                    color: "#00ffffff"
                    border.width: 1.5 * cell.unit
                    border.color: "#8cffffff"

                    // The red key: a red bar as on the remote.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: modelData.cap === "red"
                        width: 14 * cell.unit
                        height: 8 * cell.unit
                        radius: 3 * cell.unit
                        color: GlassStyle.keyRed
                    }

                    Text {
                        id: capText
                        anchors.centerIn: parent
                        visible: modelData.cap !== "red"
                        text: modelData.cap === "red" ? "" : modelData.cap
                        color: GlassStyle.textPrimary
                        font.family: cell.titleFont
                        font.pixelSize: 16 * cell.unit
                    }
                }

                Text {
                    readonly property var focusedRow: cell.owner ? cell.owner.focusedRow : null
                    readonly property bool onOwn: !!focusedRow && !!focusedRow.item && !!focusedRow.item.entry &&
                                                  focusedRow.item.entry.own === true
                    anchors.verticalCenter: parent.verticalCenter
                    text: onOwn && modelData.textOwn ? modelData.textOwn : modelData.text
                    color: "#c7ffffff"
                    font.family: cell.valueFont
                    font.pixelSize: 18 * cell.unit
                }
            }
        }
    }

    // The row itself: the shared GlassRow, as in the quick panel.
    GlassRow {
        anchors.fill: parent
        visible: cell.isRow && cell.row.type !== "statusCard" && cell.row.type !== "notes"
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
        // Entries of a host list may bring a profile's avatar or a row icon.
        avatar: cell.row.item && cell.row.item.avatar ? cell.row.item.avatar : null
        avatarSize: cell.row.item && cell.row.item.avatarSize ? cell.row.item.avatarSize : 32
        iconPng: cell.row.item && cell.row.item.png ? cell.row.item.png : ""

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
