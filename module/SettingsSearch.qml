import QtQuick 2.12
import "."
import "SettingsEngine.js" as Engine
import "ListScroll.js" as ListScroll

// Search page of the settings modal (K3-Struktur-Suche-Tippen): field, hits on the left,
// keyboard on the right, QWERTZ | T9 at the top right. Hits show their path and value and
// follow every character. Number keys of the remote type at once with T9. The modal owns
// the focus surface; focusRect says where it belongs, in pane coordinates.
Item {
    id: search

    property var owner: null
    property real unit: 1
    property string rowFont: ""
    property string valueFont: ""
    property string titleFont: ""

    property string query: ""
    property var index: []
    property string focusId: "t-2"
    property string lastKey: "k-1-0"
    property string lastT9Key: "t-2"
    property int lastColumn: 0
    property int resultScroll: 0

    readonly property int maxQuery: 40
    readonly property real fieldY: 31
    readonly property real listY: 149
    readonly property real keyboardX: 424
    readonly property real resultsWidth: 400
    readonly property int visibleResults: 7
    readonly property string typed: query + keyboard.pendingChar
    readonly property var results: Engine.search(index, typed, 30)
    readonly property bool onResult: focusId.indexOf("result:") === 0
    readonly property int resultIndex: onResult ? Number(focusId.substring(7)) : -1

    // Called by the modal whenever the search page opens.
    function open(entries) {
        index = entries;
        keyboard.reset(GlassStyle.keyboardMode);
        focusId = keyboard.mode === "t9" ? lastT9Key : lastKey;
    }

    readonly property real bodyY: 92          // field, hits and keys start under the 64 px head
    readonly property rect focusRect: {
        if (onResult) {
            var row = resultIndex - resultScroll;
            return Qt.rect(0, bodyY + listY + row * 84, resultsWidth, 80);
        }
        if (focusId === "mode-qwertz" || focusId === "mode-t9") {
            var segment = modeSwitch.segmentRect(focusId.substring(5));
            return Qt.rect(segment.x / unit, segment.y / unit, segment.width / unit, segment.height / unit);
        }
        var key = keyboard.keyRect(focusId);
        return Qt.rect(keyboardX + key.x / unit, bodyY + listY + key.y / unit, key.width / unit, key.height / unit);
    }
    readonly property real focusRadius: onResult ? 26 : ((focusId === "mode-qwertz" || focusId === "mode-t9") ? 28 :
                                        (keyboard.isT9Key(focusId) ? 20 : 16))
    readonly property real focusScale: keyboard.pressScaleOf(focusId)

    function setMode(mode) {
        if (keyboard.mode === mode) return;
        keyboard.commitPending();
        keyboard.mode = mode;
        GlassStyle.keyboardMode = mode;
    }

    function type(value) {
        if (query.length >= maxQuery) return;
        query += value;
        resultScroll = 0;
    }

    function remove() {
        if (!keyboard.cancelPending()) query = query.substring(0, query.length - 1);
        resultScroll = 0;
    }

    function pressKey(id) {
        keyboard.pressKey(id);
        if (id.indexOf("k-") === 0) {
            var parts = id.split("-");
            type(keyboard.charAt(Number(parts[1]), Number(parts[2])));
        } else if (id === "space") {
            type(" ");
        } else if (id === "delete" || id === "t-delete") {
            remove();
        } else if (id === "shift") {
            if (keyboard.isEnabled("shift")) keyboard.shifted = !keyboard.shifted;
        } else if (id === "symbols") {
            keyboard.symbols = !keyboard.symbols;
        } else if (id === "t-shift") {
            keyboard.commitPending();
            keyboard.shifted = !keyboard.shifted;
        } else if (id === "t-symbols") {
            setMode("qwertz");
            keyboard.symbols = true;
            focusId = "symbols";
        } else if (keyboard.isT9Key(id)) {
            lastT9Key = id;
            keyboard.tapT9(id);
        }
    }

    // A number key of the remote types at once with T9; holding it types the digit.
    function typeDigit(digit, held) {
        var id = "t-" + digit;
        if (held) {
            keyboard.holdT9(id);
            return;
        }
        setMode("t9");
        focusId = id;
        lastT9Key = id;
        keyboard.pressKey(id);
        keyboard.tapT9(id);
    }

    function toKeys() {
        focusId = keyboard.mode === "t9" ? lastT9Key : lastKey;
    }

    function toResults() {
        if (results.length === 0) return;
        keyboard.commitPending();
        if (keyboard.isT9Key(focusId)) lastT9Key = focusId;
        else if (keyboard.isKey(focusId)) lastKey = focusId;
        focusId = "result:" + Math.min(resultScroll, results.length - 1);
    }

    function moveResult(step) {
        var next = Math.max(0, Math.min(results.length - 1, resultIndex + step));
        focusId = "result:" + next;
        resultScroll = ListScroll.centredIndex(next, visibleResults, results.length);
    }

    function moveKey(id) {
        if (id === "" || !keyboard.isEnabled(id)) return;
        focusId = id;
        if (keyboard.isT9Key(id)) lastT9Key = id;
        else lastKey = id;
    }

    // Returns false when the key leaves the page: Left from the hits goes to the side bar.
    function handleKey(key, autoRepeat) {
        var ok = Remote.isOk(key);
        if (key >= Qt.Key_0 && key <= Qt.Key_9) {
            typeDigit(String(key - Qt.Key_0), autoRepeat);
            return true;
        }
        if (onResult) {
            if (key === Qt.Key_Up) moveResult(-1);
            else if (key === Qt.Key_Down) moveResult(1);
            else if (key === Qt.Key_Right) toKeys();
            else if (key === Qt.Key_Left) return false;
            else if (ok && !autoRepeat) owner.openResult(results[resultIndex]);
            return true;
        }
        if (focusId === "mode-qwertz" || focusId === "mode-t9") {
            if (key === Qt.Key_Left && focusId === "mode-t9") focusId = "mode-qwertz";
            else if (key === Qt.Key_Right && focusId === "mode-qwertz") focusId = "mode-t9";
            else if (key === Qt.Key_Down) toKeys();
            else if (ok && !autoRepeat) setMode(focusId.substring(5));
            return true;
        }
        if (ok) {
            if (!autoRepeat || focusId === "delete" || focusId === "t-delete") pressKey(focusId);
            else if (keyboard.isT9Key(focusId)) keyboard.holdT9(focusId);
            return true;
        }
        if (keyboard.isT9Key(focusId)) {
            var next = keyboard.t9Neighbour(focusId, key);
            if (next !== "") moveKey(next);
            else if (key === Qt.Key_Up) { keyboard.commitPending(); focusId = "mode-t9"; }
            else if (key === Qt.Key_Left) { if (results.length > 0) toResults(); else return false; }
            return true;
        }
        if (focusId.indexOf("k-") === 0) {
            var parts = focusId.split("-");
            var row = Number(parts[1]);
            var col = Number(parts[2]);
            if (key === Qt.Key_Left) {
                if (col > 0) moveKey("k-" + row + "-" + (col - 1));
                else if (results.length > 0) toResults();
                else return false;
            } else if (key === Qt.Key_Right) {
                if (col < keyboard.columns - 1) moveKey("k-" + row + "-" + (col + 1));
            } else if (key === Qt.Key_Up) {
                if (row > 0) moveKey("k-" + (row - 1) + "-" + col);
                else focusId = "mode-qwertz";
            } else if (key === Qt.Key_Down) {
                if (row < 3) moveKey("k-" + (row + 1) + "-" + col);
                else {
                    lastColumn = col;
                    var below = keyboard.bottomKeyAt(col);
                    moveKey(keyboard.isEnabled(below) ? below : "symbols");
                }
            }
            return true;
        }
        var bottom = keyboard.bottomKeys;
        var at = keyboard.bottomIndexOf(focusId);
        if (key === Qt.Key_Up) {
            var here = bottom[at];
            var inside = lastColumn * 64 >= here.x && lastColumn * 64 < here.x + here.w;
            moveKey("k-3-" + (inside ? lastColumn : here.col));
        } else if (key === Qt.Key_Right && at < bottom.length - 1) {
            moveKey(bottom[at + 1].id);
        } else if (key === Qt.Key_Left) {
            var previous = at - 1;
            if (previous >= 0 && !keyboard.isEnabled(bottom[previous].id)) previous--;
            if (previous >= 0) moveKey(bottom[previous].id);
            else if (results.length > 0) toResults();
            else return false;
        }
        return true;
    }

    // ---- Drawing ----

    Text {
        x: 20 * search.unit
        width: parent.width - 300 * search.unit
        height: 64 * search.unit
        verticalAlignment: Text.AlignVCenter
        text: I18n.t("settings", "title.search")
        color: "#ffffff"
        font.family: search.titleFont
        font.pixelSize: 40 * search.unit
        font.letterSpacing: -0.8 * search.unit
    }

    KeyboardModeSwitch {
        id: modeSwitch
        x: parent.width - width
        unit: search.unit
        labelFont: search.rowFont
        mode: keyboard.mode
        focusedSegment: search.focusId === "mode-qwertz" ? "qwertz" : (search.focusId === "mode-t9" ? "t9" : "")
        onChosen: {
            search.focusId = "mode-" + choice;
            search.setMode(choice);
        }
    }

    Item {
        y: search.bodyY * search.unit
        width: parent.width
        height: parent.height - y

        Text {
            x: 8 * search.unit
            height: 23 * search.unit
            verticalAlignment: Text.AlignVCenter
            text: I18n.t("settings", "detail.search_term")
            color: GlassStyle.textSecondary
            font.family: search.rowFont
            font.pixelSize: 18 * search.unit
        }

        GlassControl {
            y: search.fieldY * search.unit
            width: parent.width
            height: 72 * search.unit
            unit: search.unit
            radius: 26
            fill: "#38000000"
            edge: "edge-field-26"

            Row {
                x: 24 * search.unit
                height: parent.height

                Text {
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: search.query
                    color: "#ffffff"
                    font.family: search.rowFont
                    font.pixelSize: 26 * search.unit
                }

                // The T9 character that is not final yet, underlined.
                Text {
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: keyboard.pendingChar
                    font.underline: true
                    color: "#ffffff"
                    font.family: search.rowFont
                    font.pixelSize: 26 * search.unit
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2 * search.unit
                    height: 32 * search.unit
                    radius: search.unit
                    color: "#ffffff"
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        PropertyAction { value: 1 }
                        PauseAnimation { duration: 550 }
                        PropertyAction { value: 0 }
                        PauseAnimation { duration: 550 }
                    }
                }
            }
        }

        Text {
            x: 8 * search.unit
            y: (search.fieldY + 80) * search.unit
            height: 22 * search.unit
            verticalAlignment: Text.AlignVCenter
            text: search.typed.trim() === "" ? I18n.t("settings", "detail.search_hint") :
                  I18n.t("settings", search.results.length === 1 ? "detail.search_hit_one" : "detail.search_hits",
                         { count: search.results.length })
            color: GlassStyle.textDetail
            font.family: search.valueFont
            font.pixelSize: 17 * search.unit
        }

        Item {
            id: hitList
            y: search.listY * search.unit
            width: search.resultsWidth * search.unit
            height: search.visibleResults * 84 * search.unit
            clip: true
            layer.enabled: search.results.length > search.visibleResults
            layer.effect: EdgeFade {
                topFade: 56 * search.unit / Math.max(1, hitList.height)
                bottomFade: 96 * search.unit / Math.max(1, hitList.height)
                topAmount: search.resultScroll > 0 ? 1 : 0
                bottomAmount: search.resultScroll + search.visibleResults < search.results.length ? 1 : 0
            }

            Repeater {
                model: search.results
                Item {
                    readonly property bool focused: search.resultIndex === index && !!search.owner && search.owner.zone === "search"
                    y: (index - search.resultScroll) * 84 * search.unit
                    width: parent.width
                    height: 80 * search.unit

                    Text {
                        x: 20 * search.unit
                        y: 13 * search.unit
                        width: parent.width - 40 * search.unit
                        height: 28 * search.unit
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: modelData.title
                        color: parent.focused ? GlassStyle.focusText : "#ffffff"
                        font.family: search.rowFont
                        font.pixelSize: 22 * search.unit
                    }

                    Text {
                        x: 20 * search.unit
                        y: 43 * search.unit
                        width: parent.width - 40 * search.unit
                        height: 22 * search.unit
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: modelData.value !== "" ? modelData.path + " · " + modelData.value : modelData.path
                        color: parent.focused ? GlassStyle.focusSecondary : GlassStyle.textDetail
                        font.family: search.valueFont
                        font.pixelSize: 17 * search.unit
                    }
                }
            }
        }

        OnScreenKeyboard {
            id: keyboard
            x: search.keyboardX * search.unit
            y: search.listY * search.unit
            width: implicitWidth
            height: implicitHeight
            unit: search.unit
            keyFont: search.rowFont
            focusedKey: search.owner && search.owner.zone === "search" ? search.focusId : ""
            full: search.query.length >= search.maxQuery
            onKeyClicked: {
                search.focusId = keyName;
                search.pressKey(keyName);
            }
            onTyped: search.type(value)
        }
    }
}
