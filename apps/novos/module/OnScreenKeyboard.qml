import QtQuick 2.12
import "."

// Keyboard of the Konzept 3 hand-off in two modes (K3-Tastatur-*): QWERTZ for the arrow
// keys and T9 for the number keys of the remote. It knows only its own keys: the owner
// holds the focus, decides what lies around them and keeps the text. Every use gets the
// press feedback from here: call pressKey() on OK and scale the focus surface with
// pressScaleOf(), so that it shrinks along with its key.
//
// T9 is multi-tap: pressing a key again moves to its next character. The character
// waits as pendingChar, which the owner shows underlined, and reaches the text through
// typed() after a second without a press or as soon as another key is used.
Item {
    id: keyboard

    property real unit: 1
    property string keyFont: ""
    property string focusedKey: ""       // id of the focused key, "" when elsewhere
    property string mode: "qwertz"       // "qwertz" or "t9"
    property bool shifted: false
    property bool symbols: false
    property string pressedKey: ""
    property bool full: false            // the owner's text takes no further character

    // One short pulse per press, independent of how long the button stays down.
    // Fast repeated presses must each be visible as their own pulse.
    readonly property real pressScale: 0.93
    readonly property int pressDuration: 40

    readonly property int columns: 11
    readonly property real keySize: 56 * unit
    readonly property real gap: 8 * unit
    implicitWidth: columns * keySize + (columns - 1) * gap
    implicitHeight: 5 * keySize + 4 * gap      // the T9 pad has the same 312 px

    readonly property var letters: ["1234567890ß", "qwertzuiopü", "asdfghjklöä", "yxcvbnm-_.@"]
    readonly property var symbolRows: ["1234567890ß", "!\"§$%&/()=?", "+*#'~<>|\\{}", "[]^°;:,€´`µ"]
    readonly property var bottomKeys: [
        { id: "shift", x: 0, w: 120, col: 0 },
        { id: "symbols", x: 128, w: 120, col: 2 },
        { id: "space", x: 256, w: 312, col: 6 },
        { id: "delete", x: 576, w: 120, col: 9 }
    ]

    // T9: 3 × 4 keys like a phone, on the right the info field over Delete. Logical px.
    readonly property int t9KeyWidth: 136
    readonly property int t9KeyHeight: 72
    readonly property int t9Pitch: 8
    readonly property int t9SideX: 432
    readonly property int t9SideWidth: 264
    readonly property var t9Rows: [["t-1", "t-2", "t-3"], ["t-4", "t-5", "t-6"],
                                   ["t-7", "t-8", "t-9"], ["t-shift", "t-0", "t-symbols"]]
    // Characters of each key in the order of the presses. The digit comes last.
    readonly property var t9Letters: ({ "1": ".,?!", "2": "abcä", "3": "def", "4": "ghi", "5": "jkl",
                                        "6": "mnoö", "7": "pqrsß", "8": "tuvü", "9": "wxyz", "0": " " })

    // Multi-tap state.
    property string pendingKey: ""
    property int pendingIndex: 0
    property real pendingProgress: 0
    readonly property int commitDelay: 1000
    readonly property string pendingChar: pendingKey !== "" ? charOfPending(pendingKey, pendingIndex, shifted) : ""
    readonly property var pendingChoices: pendingKey !== "" ? t9Characters(pendingKey).split("") : []

    signal keyClicked(string keyName)
    signal typed(string value)           // a T9 character is final

    function reset(startMode) {
        shifted = false;
        symbols = false;
        pressedKey = "";
        cancelPending();
        if (startMode === "qwertz" || startMode === "t9") mode = startMode;
    }

    function isT9Key(id) {
        return id.indexOf("t-") === 0;
    }

    function isKey(id) {
        return id.indexOf("k-") === 0 || isT9Key(id) || bottomIndexOf(id) >= 0;
    }

    function pressKey(id) {
        if (!isKey(id) || !isEnabled(id)) return;
        pressedKey = id;
        pressRelease.restart();
    }

    function pressScaleOf(id) {
        return pressedKey !== "" && pressedKey === id ? pressScale : 1;
    }

    function charAt(row, col) {
        var value = (symbols ? symbolRows : letters)[row].charAt(col);
        // "ß".toUpperCase() would type two letters.
        return shifted && !symbols && value !== "ß" ? value.toUpperCase() : value;
    }

    function bottomIndexOf(id) {
        for (var i = 0; i < bottomKeys.length; i++) {
            if (bottomKeys[i].id === id) return i;
        }
        return -1;
    }

    // The bottom key below a column of the 56 + 8 px grid.
    function bottomKeyAt(col) {
        var left = col * 64;
        for (var i = bottomKeys.length - 1; i >= 0; i--) {
            if (left >= bottomKeys[i].x) return bottomKeys[i].id;
        }
        return bottomKeys[0].id;
    }

    function isEnabled(id) {
        return !(id === "shift" && symbols);
    }

    // ---- T9 ---------------------------------------------------------------

    // "2" for "t-2", "" for Shift, Symbols and Delete.
    function t9Digit(id) {
        var digit = id.substring(2);
        return digit.length === 1 && digit >= "0" && digit <= "9" ? digit : "";
    }

    // Letters as the key shows them. Capitals drop "ß", which has no single capital here.
    function t9Label(digit, upper) {
        var value = t9Letters[digit] || "";
        return upper ? value.replace("ß", "").toUpperCase() : value;
    }

    function t9Characters(id) {
        var digit = t9Digit(id);
        return digit === "" ? "" : t9Label(digit, shifted) + digit;
    }

    function charOfPending(id, index, upper) {
        var digit = t9Digit(id);
        var choices = t9Label(digit, upper) + digit;
        return choices.charAt(index % choices.length);
    }

    // A press of a digit key, on the remote or with OK.
    function tapT9(id) {
        if (t9Digit(id) === "") return;
        if (pendingKey === id) {
            pendingIndex = (pendingIndex + 1) % t9Characters(id).length;
        } else {
            commitPending();
            if (full) return;
            pendingKey = id;
            pendingIndex = 0;
        }
        commitTimer.restart();
        progressRun.restart();
    }

    // Holding a digit key types the digit itself.
    function holdT9(id) {
        if (pendingKey !== id) return;
        var digit = t9Digit(id);
        clearPending();
        typed(digit);
    }

    function commitPending() {
        if (pendingKey === "") return;
        var value = pendingChar;
        clearPending();
        if (value !== "") typed(value);
    }

    // Delete takes back a character that is not final yet. True if there was one.
    function cancelPending() {
        var had = pendingKey !== "";
        clearPending();
        return had;
    }

    function clearPending() {
        commitTimer.stop();
        progressRun.stop();
        pendingKey = "";
        pendingIndex = 0;
        pendingProgress = 0;
    }

    function t9Position(id) {
        for (var row = 0; row < t9Rows.length; row++) {
            var col = t9Rows[row].indexOf(id);
            if (col >= 0) return { row: row, col: col };
        }
        return { row: 0, col: 0 };
    }

    // The key next to a T9 key in the direction of an arrow key, "" at the edge of the
    // pad. The info field takes no focus, so Right from the last column reaches Delete.
    function t9Neighbour(id, key) {
        if (id === "t-delete") return key === Qt.Key_Left ? "t-symbols" : "";
        var at = t9Position(id);
        if (key === Qt.Key_Left) return at.col > 0 ? t9Rows[at.row][at.col - 1] : "";
        if (key === Qt.Key_Right) return at.col < 2 ? t9Rows[at.row][at.col + 1] : "t-delete";
        if (key === Qt.Key_Up) return at.row > 0 ? t9Rows[at.row - 1][at.col] : "";
        if (key === Qt.Key_Down) return at.row < 3 ? t9Rows[at.row + 1][at.col] : "";
        return "";
    }

    function t9Row(id) {
        return id === "t-delete" ? 3 : t9Position(id).row;
    }

    // Position of a key inside the keyboard, for the owner's focus surface.
    function keyRect(id) {
        if (id === "t-delete") {
            return Qt.rect(t9SideX * unit, 3 * (t9KeyHeight + t9Pitch) * unit, t9SideWidth * unit, t9KeyHeight * unit);
        }
        if (isT9Key(id)) {
            var at = t9Position(id);
            return Qt.rect(at.col * (t9KeyWidth + t9Pitch) * unit, at.row * (t9KeyHeight + t9Pitch) * unit,
                           t9KeyWidth * unit, t9KeyHeight * unit);
        }
        if (id.indexOf("k-") === 0) {
            var parts = id.split("-");
            return Qt.rect(Number(parts[2]) * (keySize + gap), Number(parts[1]) * (keySize + gap),
                           keySize, keySize);
        }
        var key = bottomKeys[Math.max(0, bottomIndexOf(id))];
        return Qt.rect(key.x * unit, 4 * (keySize + gap), key.w * unit, keySize);
    }

    Timer {
        id: pressRelease
        interval: keyboard.pressDuration
        onTriggered: keyboard.pressedKey = ""
    }

    Timer {
        id: commitTimer
        interval: keyboard.commitDelay
        onTriggered: keyboard.commitPending()
    }

    NumberAnimation {
        id: progressRun
        target: keyboard
        property: "pendingProgress"
        from: 0
        to: 1
        duration: keyboard.commitDelay
    }

    // ---- QWERTZ -----------------------------------------------------------

    Item {
        anchors.fill: parent
        visible: keyboard.mode === "qwertz"

        Repeater {
            model: 4

            Item {
                id: keyRow
                readonly property int rowIndex: index
                y: rowIndex * (keyboard.keySize + keyboard.gap)
                width: keyboard.width
                height: keyboard.keySize

                Repeater {
                    model: keyboard.columns

                    KeyCap {
                        x: index * (keyboard.keySize + keyboard.gap)
                        width: keyboard.keySize
                        height: keyboard.keySize
                        board: keyboard
                        keyId: "k-" + keyRow.rowIndex + "-" + index
                        label: keyboard.charAt(keyRow.rowIndex, index)
                    }
                }
            }
        }

        Repeater {
            model: keyboard.bottomKeys

            KeyCap {
                x: modelData.x * keyboard.unit
                y: 4 * (keyboard.keySize + keyboard.gap)
                width: modelData.w * keyboard.unit
                height: keyboard.keySize
                board: keyboard
                keyId: modelData.id
                label: modelData.id === "space" ? I18n.t("keyboard", "key.space") :
                       (modelData.id === "delete" ? I18n.t("keyboard", "key.delete") :
                        (modelData.id === "symbols" ? (keyboard.symbols ? "ABC" : "#+=") : ""))
            }
        }
    }

    // ---- T9 ---------------------------------------------------------------

    Item {
        anchors.fill: parent
        visible: keyboard.mode === "t9"

        Repeater {
            model: 12

            T9Key {
                readonly property string slotId: keyboard.t9Rows[Math.floor(index / 3)][index % 3]
                x: (index % 3) * (keyboard.t9KeyWidth + keyboard.t9Pitch) * keyboard.unit
                y: Math.floor(index / 3) * (keyboard.t9KeyHeight + keyboard.t9Pitch) * keyboard.unit
                width: keyboard.t9KeyWidth * keyboard.unit
                height: keyboard.t9KeyHeight * keyboard.unit
                board: keyboard
                keyId: slotId
                digit: keyboard.t9Digit(slotId)
                letters: digit === "0" ? "" : keyboard.t9Label(digit, keyboard.shifted)
                icon: slotId === "t-shift" ? "shift-24" : ""
                label: slotId === "t-shift" ? "Aa" : (slotId === "t-symbols" ? "#+=" : "")
                latched: slotId === "t-shift" && keyboard.shifted
            }
        }

        // Info field: how multi-tap works, or the characters of the key being pressed.
        GlassControl {
            id: infoField
            x: keyboard.t9SideX * keyboard.unit
            width: keyboard.t9SideWidth * keyboard.unit
            height: (3 * keyboard.t9KeyHeight + 2 * keyboard.t9Pitch) * keyboard.unit
            unit: keyboard.unit
            radius: 20
            fill: "#14ffffff"

            Column {
                x: 16 * keyboard.unit
                width: parent.width - 32 * keyboard.unit
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    height: 20 * keyboard.unit
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: keyboard.pendingKey !== "" ?
                          I18n.t("keyboard", "label.key", { digit: keyboard.t9Digit(keyboard.pendingKey) }) :
                          I18n.t("keyboard", "label.multi_tap")
                    color: GlassStyle.textSecondary
                    font.family: keyboard.keyFont
                    font.pixelSize: 16 * keyboard.unit
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.96 * keyboard.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Text {
                    visible: keyboard.pendingKey === ""
                    width: parent.width
                    topPadding: 8 * keyboard.unit
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 25 * keyboard.unit
                    text: I18n.t("keyboard", "hint.multi_tap")
                    color: "#ffffff"
                    font.family: keyboard.keyFont
                    font.pixelSize: 19 * keyboard.unit
                    font.hintingPreference: Font.PreferNoHinting
                }

                Item {
                    visible: keyboard.pendingKey !== ""
                    width: parent.width
                    height: 76 * keyboard.unit

                    Row {
                        y: 12 * keyboard.unit
                        spacing: 6 * keyboard.unit

                        Repeater {
                            model: keyboard.pendingChoices

                            Rectangle {
                                readonly property bool chosen: index === keyboard.pendingIndex
                                width: 34 * keyboard.unit
                                height: 44 * keyboard.unit
                                radius: 12 * keyboard.unit
                                color: chosen ? "#ffffff" : "#14ffffff"
                                antialiasing: true

                                Text {
                                    anchors.centerIn: parent
                                    visible: modelData !== " "
                                    text: modelData
                                    color: parent.chosen ? GlassStyle.focusText : "#d1ffffff"
                                    font.family: keyboard.keyFont
                                    font.pixelSize: 22 * keyboard.unit
                                    font.hintingPreference: Font.PreferNoHinting
                                }

                                Image {
                                    anchors.centerIn: parent
                                    visible: modelData === " "
                                    source: Qt.resolvedUrl(parent.chosen ? "icons/space-22-dark.png" : "icons/space-22.png")
                                }
                            }
                        }
                    }

                    // Runs for the second until the character is taken.
                    Rectangle {
                        y: 72 * keyboard.unit
                        width: parent.width
                        height: 4 * keyboard.unit
                        radius: 2 * keyboard.unit
                        color: "#29ffffff"

                        Rectangle {
                            width: parent.width * keyboard.pendingProgress
                            height: parent.height
                            radius: parent.radius
                            color: "#d9ffffff"
                        }
                    }
                }
            }
        }

        T9Key {
            x: keyboard.t9SideX * keyboard.unit
            y: 3 * (keyboard.t9KeyHeight + keyboard.t9Pitch) * keyboard.unit
            width: keyboard.t9SideWidth * keyboard.unit
            height: keyboard.t9KeyHeight * keyboard.unit
            board: keyboard
            keyId: "t-delete"
            icon: "delete-24"
            label: I18n.t("keyboard", "key.delete")
        }
    }
}
