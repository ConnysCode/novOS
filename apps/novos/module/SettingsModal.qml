import QtQuick 2.12
import "."
import "SettingsEngine.js" as Engine
import "ListScroll.js" as ListScroll
import "ShutdownScreens.js" as ShutdownScreens

// The large settings modal of K3-Einstellungen and K3-Struktur: a side bar with search and
// twelve areas, on the right the page of the chosen area with up to two levels below it.
// What a page shows comes from the catalogs (SettingsArea*.js) and from what this TV's
// settings service describes, see docs/settings-catalog.md. Values are written the way LG's
// own settings app writes them.
Item {
    id: settings

    property real unit: 1
    property string titleFont: ""
    property string rowFont: ""
    property string valueFont: ""
    property variant backdrop
    property string glassShader: ""
    property string shadowShader: ""
    property real backdropMargin: 56
    property rect backdropArea: Qt.rect(0, 0, 0, 0)
    property real hasBackdrop: 0
    readonly property real backdropVeil: 0.38   // its own dimming, over the host's
    property var focusCurve: GlassStyle.curve
    property var hostState: ({})          // source, network and device facts the panel knows

    property bool active: false           // the modal owns the keys
    property bool shown: false            // the card is on screen, set by the panel

    // The panel runs what needs its own flows: Wi-Fi setup, name entry, confirmations.
    signal hostAction(string name, var params)
    signal launchApp(var app)

    // ---- Stage --------------------------------------------------------------

    readonly property real cardWidth: 1680
    readonly property real cardHeight: 920
    readonly property real sideX: 16
    readonly property real sideY: 16
    readonly property real sideWidth: 440
    readonly property real tabX: 32           // side bar padding 16
    readonly property real tabWidth: 408
    readonly property real searchY: 104
    readonly property real tabsY: 170
    readonly property real tabHeight: 50
    readonly property real tabPitch: 54
    readonly property int separatorAfter: 9    // a line between Datenschutz and System
    readonly property real paneX: 504
    readonly property real paneY: 52
    readonly property real paneWidth: 1120
    readonly property real paneHeight: 828
    readonly property real rowGap: 4
    readonly property real sectionGap: 32
    readonly property real sectionTitle: 30    // 20 px label and 10 px to the list
    readonly property real listGap: 28
    readonly property real tileWidth: 360         // K3-Ausschalt-2: 8 + 203 picture + 12 + text + 14
    readonly property real tileHeight: 287
    readonly property real tileGap: 12
    readonly property int pageDuration: GlassStyle.pageDuration
    readonly property real pageShift: GlassStyle.pageShift

    readonly property color textPrimary: GlassStyle.textPrimary
    readonly property color textSecondary: GlassStyle.textSecondary
    readonly property color focusText: GlassStyle.focusText
    readonly property color focusSecondary: GlassStyle.focusSecondary
    readonly property color accent: GlassStyle.accent

    // ---- State ---------------------------------------------------------------

    // Values, descriptors and writing live in the shared SettingsStore of the panel.
    property var settingsStore: null
    readonly property var store: settingsStore ? settingsStore.store : Engine.newStore()
    readonly property int revision: settingsStore ? settingsStore.revision : 0
    property bool requested: false

    property string zone: "sidebar"           // sidebar, content, search
    property bool fromSearch: false           // the page was opened from a hit
    property int searchDepth: 0               // its level: Back there returns to the hits
    property int sideIndex: 1                 // 0 is the search, then the areas
    property int areaIndex: 0
    property var stack: []                    // levels below the area: { kind, page, row, rowId, focus }
    property int focusIndex: 0
    property real scroll: 0
    property real pageFade: 1
    property real pageOffset: 0
    property var lastFocus: ({})              // per area, where the focus was on level 0
    property bool searchNeeded: false         // the search page is built on its first use
    readonly property var searchPage: searchLoader.item

    readonly property var area: Engine.areas[areaIndex]
    readonly property var page: resolveCurrent(revision, areaIndex, stack)
    readonly property var layout: layoutOf(page)
    readonly property var focusedRow: zone === "content" && page.rows.length > 0 ?
                                      page.rows[Math.min(focusIndex, page.rows.length - 1)] : null

    function resolveCurrent() {
        var started = PerfProbe.now();
        var resolved = resolveLevel();
        PerfProbe.cost("modal.resolve", started, resolved.rows.length + " rows");
        return resolved;
    }

    function resolveLevel() {
        var top = stack.length > 0 ? stack[stack.length - 1] : null;
        var param = paramOf(stack.length);
        if (top && top.kind === "choice") return Engine.resolveChoice(store, I18n, area.id, top.row, param);
        return Engine.resolvePage(store, I18n, area.id, top ? top.page : area.page.id, param);
    }

    // The entry the levels up to depth were opened for; a choice inherits its page's.
    function paramOf(depth) {
        for (var i = depth - 1; i >= 0; i--) {
            if (stack[i].param !== undefined) return stack[i].param;
        }
        return undefined;
    }

    // ---- Opening -------------------------------------------------------------

    // areaId and rowId are optional: the panel opens on the page that matches its own.
    function open(areaId, pageId) {
        requestData();
        var index = 0;
        for (var i = 0; i < Engine.areas.length; i++) {
            if (Engine.areas[i].id === areaId) index = i;
        }
        areaIndex = index;
        sideIndex = index + 1;
        stack = [];
        zone = "sidebar";
        focusIndex = 0;
        scroll = 0;
        if (pageId && pageId !== Engine.areas[index].page.id) {
            stack = [{ kind: "page", page: pageId, rowId: "", focus: 0 }];
            zone = "content";
        }
        active = true;
    }

    function close() {
        flushWrite();
        active = false;
    }

    // The panel calls this once the card has faded out.
    function reset() {
        stack = [];
        zone = "sidebar";
    }

    function requestData() {
        if (requested) return;
        requested = true;
        settingsStore.describeAll();
        settingsStore.call("luna://com.webos.service.eim", "/getAllInputStatus", { subscribe: true });
        tvData.request();
    }

    // The host may hand over its state before or after the store.
    function applyHostState() {
        if (!settingsStore) return;
        for (var name in hostState) settingsStore.store.state[name] = hostState[name];
        changed();
    }

    onHostStateChanged: applyHostState()
    onSettingsStoreChanged: applyHostState()

    // Many answers arrive at once; the page is built once for all of them.
    function changed() {
        settingsStore.changed();
    }

    // ---- Layout ---------------------------------------------------------------

    function rowHeight(row) {
        var twoLines = row.subtitle !== "";
        if (row.type === "slider") return 104;   // as the panel's slider rows
        // StatusCard: 26 above and below a 64 px circle, a bar with its texts, a 60 px button row.
        if (row.type === "statusCard") {
            return 26 * 2 + 64 + (row.card.progress >= 0 ? 18 + 10 + 10 + 24 : 0) +
                   ((row.card.buttons || []).length > 0 ? 22 + 60 : 0);
        }
        // NoteList: 20 above and below, per entry a 28 px title and its text, 26 px a line of
        // about 100 characters at 18 px, 16 between entries.
        if (row.type === "notes") {
            var height = 2 * 20;
            for (var i = 0; i < row.notes.length; i++) {
                var lines = Math.max(1, Math.ceil(String(row.notes[i].text || "").length / 100));
                height += 28 + 2 + 26 * lines + (i > 0 ? 16 : 0);
            }
            return height;
        }
        return twoLines ? 80 : 68;
    }

    // Positions of everything in the list, in logical px from the top of the list.
    function layoutOf(current) {
        var started = PerfProbe.now();
        var items = [];
        var rowY = [];
        var rowH = [];
        var rowX = [];
        var rowW = [];
        var rowCol = [];      // column in a grid of tiles, -1 for a plain row
        var rowCols = [];     // columns of that grid
        var y = 0;
        // Head block of Über novOS: word mark, version, what it runs on.
        if (current.hero) {
            items.push({ kind: "hero", y: 0, h: 116, hero: current.hero });
            y = 116 + listGap;
        }
        for (var s = 0; s < current.sections.length; s++) {
            var section = current.sections[s];
            if (s > 0) y += sectionGap;
            if (section.title !== "") {
                items.push({ kind: "section", y: y, text: section.title });
                y += sectionTitle;
            }
            if (section.heading) {
                items.push({ kind: "heading", y: y, h: 30, heading: section.heading });
                y += 30 + 12;
            }
            if (section.columns > 0) {
                // Tiles (K3-Ausschalt-2): columns of tileWidth spread over the pane.
                var columns = section.columns;
                var step = tileWidth + (paneWidth - columns * tileWidth) / Math.max(1, columns - 1);
                for (var t = 0; t < section.rows.length; t++) {
                    var column = t % columns;
                    if (t > 0 && column === 0) y += tileHeight + tileGap;
                    var tile = section.rows[t];
                    items.push({ kind: "tile", x: column * step, y: y, w: tileWidth, h: tileHeight, row: tile,
                                 index: rowY.length });
                    rowX.push(column * step);
                    rowW.push(tileWidth);
                    rowY.push(y);
                    rowH.push(tileHeight);
                    rowCol.push(column);
                    rowCols.push(columns);
                }
                if (section.rows.length > 0) y += tileHeight;
            } else {
                for (var r = 0; r < section.rows.length; r++) {
                    var row = section.rows[r];
                    var height = rowHeight(row);
                    items.push({ kind: "row", y: y, h: height, row: row, index: rowY.length });
                    rowX.push(0);
                    rowW.push(paneWidth);
                    rowY.push(y);
                    rowH.push(height);
                    rowCol.push(-1);
                    rowCols.push(0);
                    y += height + (r < section.rows.length - 1 ? rowGap : 0);
                }
            }
            // The keys of the page and what they do, under the tiles.
            if (section.keys && section.keys.length > 0) {
                items.push({ kind: "keys", y: y + 20, h: 30, keys: section.keys });
                y += 20 + 30;
            }
            if (section.note) {
                items.push({ kind: "note", y: y + 14, text: section.note });
                y += 14 + 52;
            }
        }
        if (current.note) {
            items.push({ kind: "note", y: y + 14, text: current.note });
            y += 14 + 52;
        }
        PerfProbe.cost("modal.layout", started, items.length + " items");
        return { items: items, rowY: rowY, rowH: rowH, rowX: rowX, rowW: rowW, rowCol: rowCol, rowCols: rowCols,
                 height: y };
    }

    readonly property real headerHeight: (stack.length > 0 ? 34 : 0) + 48 + (page.subtitle !== "" ? 30 : 0)
    readonly property real listTop: paneY + headerHeight + listGap
    readonly property real listHeight: paneY + paneHeight - listTop

    readonly property real listEndGap: 24
    readonly property real maxScroll: Math.max(0, layout.height + listEndGap - listHeight)
    // The chosen row stays in the middle of the list until the list meets its start or
    // its end. Near the start that shows a head block and the section titles above, near
    // the end a note below the last row, which take no focus themselves. On Über novOS the
    // first focusable row lies below the middle; the first and last focusable row still
    // show the list's start and end (ListScroll.centredBetween).
    function keepVisible() {
        if (zone !== "content" || layout.rowY.length === 0) return;
        var first = firstFocusable();
        var last = lastFocusable();
        scroll = ListScroll.centredBetween(layout.rowY[focusIndex], layout.rowH[focusIndex], listHeight,
                                           maxScroll + listHeight,
                                           { start: layout.rowY[first], size: layout.rowH[first] },
                                           { start: layout.rowY[last], size: layout.rowH[last] });
    }

    onLayoutChanged: {
        growRows();
        settleCardFocus();
        if (focusIndex >= layout.rowY.length) focusIndex = Math.max(0, layout.rowY.length - 1);
        // A page opened straight from a launch starts at 0, maybe before its focusable rows
        // have their data: the focus never rests on a row that takes none. A status card is
        // the exception: while its task runs (a search) its only button is greyed out, and
        // the focus stays on the card instead of jumping to the rows below it.
        var row = page.rows[focusIndex];
        if (zone === "content" && row && !row.focusable && row.type !== "statusCard") focusIndex = firstFocusable();
        keepVisible();
    }

    // The list's rows: one slot per entry of the longest page so far.
    readonly property var emptyEntry: ({ kind: "none", y: 0, h: 0 })
    ListModel {
        id: rowSlots
    }

    function growRows() {
        while (rowSlots.count < layout.items.length) rowSlots.append({ slot: rowSlots.count });
    }

    Component.onCompleted: growRows()

    onFocusIndexChanged: {
        keepVisible();
        cardFocus = defaultCardButton();
    }

    // The focused button of a StatusCard row: Left and Right move it, the card draws it.
    property int cardFocus: 0
    readonly property bool focusOnCard: zone === "content" && !!focusedRow && focusedRow.type === "statusCard"

    function cardButtons() {
        return focusOnCard ? (focusedRow.card.buttons || []) : [];
    }

    function defaultCardButton() {
        var buttons = cardButtons();
        for (var i = 0; i < buttons.length; i++) {
            if (buttons[i].focus && buttons[i].disabled !== true) return i;
        }
        for (var j = 0; j < buttons.length; j++) {
            if (buttons[j].disabled !== true) return j;
        }
        return 0;
    }

    function moveOnCard(step) {
        var buttons = cardButtons();
        var index = cardFocus + step;
        while (index >= 0 && index < buttons.length && buttons[index].disabled === true) index += step;
        if (index < 0 || index >= buttons.length) return false;
        cardFocus = index;
        return true;
    }

    // The card's buttons change with the task (a search, a download): the focus stays usable.
    function settleCardFocus() {
        var buttons = cardButtons();
        if (buttons.length > 0 && (cardFocus >= buttons.length || buttons[cardFocus].disabled === true)) {
            cardFocus = defaultCardButton();
        }
    }

    function pressCard(index) {
        var button = cardButtons()[index];
        if (!button || button.disabled === true) return;
        if (button.confirm) {
            var context = ctx();
            hostAction("confirm", { action: button.action, params: button.params || {},
                                    title: context.t(button.confirm.title), text: context.t(button.confirm.text),
                                    confirm: context.t(button.confirm.confirm), danger: button.confirm.danger === true });
        } else {
            runAction(button.action, button.params || {});
        }
    }

    // The single focus surface, in card coordinates.
    readonly property rect focusRect: {
        if (zone === "search") {
            var hit = searchPage.focusRect;
            return Qt.rect(paneX + hit.x, paneY + hit.y, hit.width, hit.height);
        }
        if (zone === "sidebar") {
            if (sideIndex === 0) return Qt.rect(tabX, searchY, tabWidth, 52);
            return Qt.rect(tabX, tabY(sideIndex - 1), tabWidth, tabHeight);
        }
        if (layout.rowY.length === 0) return Qt.rect(paneX, listTop, paneWidth, 68);
        return Qt.rect(paneX + layout.rowX[focusIndex], listTop + layout.rowY[focusIndex] - scroll,
                       layout.rowW[focusIndex], layout.rowH[focusIndex]);
    }

    readonly property bool focusOnTile: zone === "content" && layout.rowCol.length > focusIndex &&
                                        layout.rowCol[focusIndex] >= 0

    function tabY(index) {
        return tabsY + index * tabPitch + (index > separatorAfter ? 21 : 0);
    }

    // ---- Writing ---------------------------------------------------------------

    function ctx() {
        var context = Engine.context(store, area.id, I18n);
        context.area = area;
        context.param = paramOf(stack.length);
        return context;
    }

    // The new value shows at once; the TV gets it once the key rests.
    function write(row, value) {
        var context = ctx();
        var key = Engine.rowKey(row, context);
        if (key.indexOf("novos.") === 0) {
            tvData.writeNovos(key.slice(6), value);
            return;
        }
        commit(Engine.writeRequest(store, row, value, context), row, context);
    }

    // The shared store shows a value at once and writes it once the key rests.
    function commit(request, row, context) {
        settingsStore.commit(request, row, context);
    }

    function flushWrite() {
        settingsStore.flushWrite();
    }

    // ---- Actions -------------------------------------------------------------

    // Actions the modal runs itself. The rest go to the panel through hostAction.
    function runAction(name, params) {
        var context = ctx();
        if (name === "applyPictureToAll") {
            settingsStore.call("luna://com.webos.settingsservice", "/setSystemSettings",
                         JSON.stringify({ category: "picture", settings: { applyToAllInput: "picture" } }));
        } else if (name === "resetPicture") {
            resetPicture(context);
        } else if (name === "previewShutdown") {
            shutdownPreview.own = ShutdownScreens.ownEntries();
            shutdownPreview.changes = params && params.changes ? params.changes : null;
            shutdownPreview.screenId = params && params.id ? params.id : NovosSettings.shutdownScreen;
            shutdownPreview.sound = NovosSettings.shutdownSound;
            shutdownPreview.play();
        } else if (name === "chooseShutdown") {
            tvData.writeNovos("shutdownScreen", String(params.id));
        } else if (name === "openShutdownUpload") {
            pushPage({ id: "shutdownUpload", title: "page.shutdown_upload", custom: "shutdownUpload", sections: [] });
        } else if (name === "openShutdownEdit") {
            var own = ShutdownScreens.entry(String(params.id), ShutdownScreens.ownEntries());
            pushPage({ id: "shutdownEdit", title: function () { return own.name || ""; }, custom: "shutdownEdit",
                       target: String(params.id), sections: [] });
        } else if (name === "deleteShutdown") {
            tvData.deleteShutdown(String(params.id));
            if (page.custom === "shutdownEdit") back();
        } else if (name === "applySoundToAll") {
            settingsStore.call("luna://com.webos.settingsservice", "/setSystemSettings",
                         JSON.stringify({ category: "sound", settings: { applyToAllInputSSM: "sound" } }));
        } else if (tvData.runs(name)) {
            tvData.run(name, params || {}, context);
        } else {
            // The panel gets the entry the page is about, for example the input.
            var forward = {};
            for (var key in params || {}) forward[key] = params[key];
            if (forward.param === undefined) forward.param = context.param;
            var item = tvData.inputOf(context);
            if (item) forward.input = item;
            hostAction(name, forward);
        }
    }

    // As LG: reset the mode of this input, then mark it as unchanged.
    function resetPicture(context) {
        var dimension = store.dimension.picture || {};
        var mode = context.val("picture.pictureMode");
        settingsStore.call("luna://com.webos.settingsservice", "/resetSystemSettings", JSON.stringify(
            { category: "picture", dimension: { input: dimension.input, _3dStatus: dimension._3dStatus,
                                                pictureMode: mode } }));
        var modified = context.val("picture.pictureSettingModified") || {};
        var marked = {};
        for (var m in modified) marked[m] = modified[m];
        marked[mode] = false;
        var settingsOut = { pictureSettingModified: marked };
        var isf = context.val("picture.isfMode");
        if (isf && typeof isf === "object" && isf[mode] && isf[mode] !== "none") {
            var cleared = {};
            for (var i in isf) cleared[i] = isf[i];
            cleared[mode] = "none";
            settingsOut.isfMode = cleared;
        }
        settingsStore.call("luna://com.webos.settingsservice", "/setSystemSettings",
                     JSON.stringify({ category: "picture", settings: settingsOut }));
    }

    // The panel answers a confirmation with this.
    function confirmed(name, params) {
        runAction(name, params);
    }

    // ---- Keys -----------------------------------------------------------------

    function isOk(key) {
        return Remote.isOk(key);
    }

    function handleKey(key, autoRepeat) {
        if (shutdownPreview.shown) {
            // Any key ends the preview; Back is taken by back() on its release.
            if (!Remote.isBack(key)) endPreview();
            return;
        }
        if (zone === "sidebar") sidebarKey(key, autoRepeat);
        else if (zone === "search") {
            if (!searchPage.handleKey(key, autoRepeat)) {
                zone = "sidebar";
                sideIndex = 0;
            }
        } else contentKey(key, autoRepeat);
    }

    // OK on the search field: the page on the right turns into the search.
    function openSearch() {
        fromSearch = false;
        var built = PerfProbe.now();
        searchLoader.asynchronous = false;      // finishes a build still running
        searchNeeded = true;
        PerfProbe.cost("modal.searchBuild", built, searchLoader.status === Loader.Ready ? "ready" : "");
        searchPage.open(searchEntries());
        zone = "search";
        pageChange.restart();
    }

    // A hit opens its page with the focus on the row that was found.
    function openResult(entry) {
        if (!entry) return;
        var index = 0;
        for (var i = 0; i < Engine.areas.length; i++) {
            if (Engine.areas[i].id === entry.area) index = i;
        }
        areaIndex = index;
        sideIndex = index + 1;
        var levels = [];
        for (var c = 0; c < entry.chain.length; c++) {
            levels.push({ kind: "page", page: entry.chain[c].page, rowId: entry.chain[c].rowId, focus: 0 });
        }
        stack = levels;
        scroll = 0;
        focusIndex = 0;
        for (var r = 0; r < page.rows.length; r++) {
            if (page.rows[r].id === entry.row) focusIndex = r;
        }
        zone = "content";
        fromSearch = true;
        searchDepth = levels.length;
        keepVisible();
        pageChange.restart();
    }

    function sidebarKey(key, autoRepeat) {
        if (key === Qt.Key_Up && sideIndex > 0) {
            selectSide(sideIndex - 1);
        } else if (key === Qt.Key_Down && sideIndex < Engine.areas.length) {
            selectSide(sideIndex + 1);
        } else if ((key === Qt.Key_Right || isOk(key)) && !autoRepeat) {
            if (sideIndex === 0) {
                openSearch();
            } else if (page.rows.length > 0) {
                zone = "content";
                focusIndex = Math.min(lastFocus[area.id] || firstFocusable(), page.rows.length - 1);
                keepVisible();
            }
        }
    }

    // The search index (about 50 ms) is kept while the values stay the same, and worked out
    // once the focus has rested on the search field, not with the key that opens it.
    property var searchCache: null

    function searchEntries() {
        if (searchCache && searchCache.revision === revision) return searchCache.entries;
        var started = PerfProbe.now();
        var entries = Engine.searchIndex(store, I18n);
        PerfProbe.cost("modal.searchIndex", started, entries.length + " entries");
        searchCache = { revision: revision, entries: entries };
        return entries;
    }

    Timer {
        id: searchWarm
        interval: GlassStyle.focusDuration + GlassStyle.popoverDuration
        onTriggered: {
            if (settings.active && settings.zone === "sidebar" && settings.sideIndex === 0) settings.searchEntries();
        }
    }

    // Up and down change the page at once, without OK.
    function selectSide(index) {
        sideIndex = index;
        fromSearch = false;
        // On the search field the search page starts building in the background, so that
        // OK usually finds it standing.
        if (index === 0) {
            searchNeeded = true;
            searchWarm.restart();
            return;
        }
        if (areaIndex !== index - 1) {
            areaIndex = index - 1;
            stack = [];
            scroll = 0;
            focusIndex = 0;
            pageChange.restart();
        }
    }

    function firstFocusable() {
        for (var i = 0; i < page.rows.length; i++) {
            if (page.rows[i].focusable) return i;
        }
        return 0;
    }

    function lastFocusable() {
        for (var i = page.rows.length - 1; i >= 0; i--) {
            if (page.rows[i].focusable) return i;
        }
        return Math.max(0, page.rows.length - 1);
    }

    function moveFocus(step) {
        var index = focusIndex + step;
        while (index >= 0 && index < page.rows.length && !page.rows[index].focusable) index += step;
        if (index >= 0 && index < page.rows.length) focusIndex = index;
    }

    // In a grid of tiles: up and down by one line of tiles, to the last tile of a shorter
    // line; left and right along a line.
    function moveInGrid(key) {
        var column = layout.rowCol[focusIndex];
        var columns = layout.rowCols[focusIndex];
        var count = layout.rowCol.length;
        var target = -1;
        var nextLine = focusIndex - column + columns;
        if (key === Qt.Key_Up && focusIndex - columns >= 0) target = focusIndex - columns;
        else if (key === Qt.Key_Down && nextLine < count && layout.rowCol[nextLine] === 0) {
            // The next line of tiles, its last tile if it is shorter.
            target = Math.min(focusIndex + columns, count - 1);
            while (layout.rowCol[target] < 0) target--;
        } else if (key === Qt.Key_Down) {
            // Below the last line: the first row after the tiles.
            for (var i = focusIndex + 1; i < count && target < 0; i++) {
                if (layout.rowCol[i] < 0 && page.rows[i].focusable) target = i;
            }
        } else if (key === Qt.Key_Right && column < columns - 1 && focusIndex + 1 < count) target = focusIndex + 1;
        else if (key === Qt.Key_Left && column > 0) target = focusIndex - 1;
        if (target >= 0 && page.rows[target].focusable) focusIndex = target;
        else if (key === Qt.Key_Left) toSidebar();
    }

    function contentKey(key, autoRepeat) {
        // A page with content of its own takes the keys first; Left it leaves goes to the side bar.
        if (page.custom) {
            if (customPage.item && customPage.item.handleKey && customPage.item.handleKey(key, autoRepeat)) return;
            if (key === Qt.Key_Left) toSidebar();
            return;
        }
        var row = focusedRow;
        if (focusOnCard && (key === Qt.Key_Left || key === Qt.Key_Right)) {
            if (!moveOnCard(key === Qt.Key_Right ? 1 : -1) && key === Qt.Key_Left) toSidebar();
        } else if (focusOnCard && isOk(key)) {
            if (!autoRepeat) pressCard(cardFocus);
        } else if (focusOnTile && Remote.isArrow(key)) {
            moveInGrid(key);
        } else if (row && row.preview && Remote.isRed(key)) {
            if (!autoRepeat) runAction(row.preview.action, row.preview.params || {});
        } else if (key === Qt.Key_Up) {
            moveFocus(-1);
        } else if (key === Qt.Key_Down) {
            moveFocus(1);
        } else if ((key === Qt.Key_Left || key === Qt.Key_Right) && row && row.type === "slider") {
            if (!row.disabled) {
                var context = ctx();
                write(row.row, Engine.sliderStep(row.row, context, key === Qt.Key_Right ? 1 : -1));
            }
        } else if (key === Qt.Key_Left) {
            toSidebar();
        } else if ((key === Qt.Key_Right && row && (row.type === "page" || row.type === "choice")) ||
                   isOk(key)) {
            if (!autoRepeat && row) activate(row);
        }
    }

    function toSidebar() {
        if (stack.length === 0) lastFocus[area.id] = focusIndex;
        zone = "sidebar";
        sideIndex = areaIndex + 1;
    }

    // Rows with pin: "parental" ask LG's own PIN prompt first; the PIN never reaches us.
    function activate(row) {
        if (row.disabled) return;
        if (row.row && row.row.pin && row.type !== "page") {
            tvData.askPin(row.row.pin, function () { perform(row); });
            return;
        }
        perform(row);
    }

    function perform(row) {
        var context = ctx();
        if (row.type === "page") {
            push({ kind: "page", page: row.row.page, rowId: row.id, focus: focusIndex });
            // onOpen: what a page fetches when it opens, as the list of versions.
            if (row.row.onOpen) runAction(row.row.onOpen, {});
        } else if (row.type === "choice") {
            push({ kind: "choice", row: row.row, rowId: row.id, focus: focusIndex });
        } else if (row.type === "option" && row.action) {
            runAction(row.action, row.params || {});
        } else if (row.type === "option" && row.write) {
            commit(row.write, null, context);
            flushWrite();
        } else if (row.type === "option") {
            write(row.row, row.option);
            if (row.row.onChange) runAction(row.row.onChange, { value: row.option });
        } else if (row.type === "toggle" && row.row.action) {
            // The host writes, for example to move a timer's app along with it.
            runAction(row.row.action, { value: Engine.nextToggleValue(row.row, context) });
        } else if (row.type === "toggle") {
            var next = Engine.nextToggleValue(row.row, context);
            write(row.row, next);
            if (row.row.onChange) {
                flushWrite();
                runAction(row.row.onChange, { value: next });
            }
        } else if (row.type === "lgApp") {
            flushWrite();
            launchApp(row.row.app);
        } else if (row.type === "action") {
            var catalogRow = row.row;
            // paramsOf: parameters that depend on the page, as the version to go back to.
            var actionParams = typeof catalogRow.paramsOf === "function" ? catalogRow.paramsOf(context) :
                               (catalogRow.params || {});
            if (catalogRow.confirm) {
                // confirm.params: values for its texts, as the version and the date of a way back.
                var asked = catalogRow.confirm;
                var texts = typeof asked.params === "function" ? asked.params(context) : (asked.params || {});
                hostAction("confirm", { action: catalogRow.action, params: actionParams,
                                        title: context.t(asked.title, texts),
                                        text: context.t(asked.text, texts),
                                        confirm: context.t(asked.confirm, texts),
                                        icon: asked.icon || "",
                                        safe: asked.safe === true });
            } else {
                runAction(catalogRow.action, actionParams);
            }
        } else if (row.type === "listItem" && row.row.page) {
            push({ kind: "page", page: row.row.page, param: row.item.id, rowId: row.id, focus: focusIndex });
        } else if (row.type === "listItem") {
            tvData.activateItem(row, context);
        }
    }

    // Levels built at run time, for example the sleep timer's minutes.
    function pushChoice(row) {
        push({ kind: "choice", row: row, rowId: focusedRow ? focusedRow.id : "", focus: focusIndex });
    }

    function pushPage(pageObject) {
        push({ kind: "page", page: pageObject, rowId: focusedRow ? focusedRow.id : "", focus: focusIndex });
    }

    function push(level) {
        var next = stack.slice();
        next.push(level);
        stack = next;
        scroll = 0;
        focusIndex = 0;
        if (level.kind === "choice") {
            for (var i = 0; i < page.rows.length; i++) {
                if (page.rows[i].selected) focusIndex = i;
            }
        } else {
            focusIndex = firstFocusable();
        }
        keepVisible();
        pageChange.restart();
    }

    // Back: one level up with the focus on the row we came from; on the top level into
    // the side bar; from the side bar the modal closes.
    function back() {
        if (shutdownPreview.shown) {
            endPreview();
            return;
        }
        if (zone === "sidebar") {
            close();
            return;
        }
        if (zone === "search") {
            zone = "sidebar";
            sideIndex = 0;
            return;
        }
        // From a hit, Back leads to the hits, not one level up.
        if (fromSearch && stack.length === searchDepth) {
            fromSearch = false;
            zone = "search";
            pageChange.restart();
            return;
        }
        if (stack.length === 0) {
            toSidebar();
            return;
        }
        var top = stack[stack.length - 1];
        var next = stack.slice(0, stack.length - 1);
        stack = next;
        scroll = 0;
        focusIndex = 0;
        for (var i = 0; i < page.rows.length; i++) {
            if (page.rows[i].id === top.rowId) focusIndex = i;
        }
        keepVisible();
        pageChange.restart();
    }

    SequentialAnimation {
        id: pageChange
        PropertyAction { target: settings; property: "pageFade"; value: 0 }
        PropertyAction { target: settings; property: "pageOffset"; value: settings.pageShift }
        ParallelAnimation {
            NumberAnimation { target: settings; property: "pageFade"; to: 1; duration: settings.pageDuration;
                              easing.type: Easing.Bezier; easing.bezierCurve: settings.focusCurve }
            NumberAnimation { target: settings; property: "pageOffset"; to: 0; duration: settings.pageDuration;
                              easing.type: Easing.Bezier; easing.bezierCurve: settings.focusCurve }
        }
    }

    // Preview only: keys the modal presses by itself, one every 450 ms ("down", "ok", "back",
    // "left", "right", "up", "red" or a digit). The TV takes no injected keys.
    property var testKeys: []

    Timer {
        id: testKeyTimer
        interval: 450
        repeat: true
        running: settings.active && settings.shown && settings.testKeys.length > 0
        onTriggered: {
            var keys = settings.testKeys.slice();
            var name = keys.shift();
            settings.testKeys = keys;
            var map = { up: Qt.Key_Up, down: Qt.Key_Down, left: Qt.Key_Left, right: Qt.Key_Right, ok: Qt.Key_Return,
                        red: Remote.redKey };
            if (name === "back") settings.back();
            else if (map[name] !== undefined) settings.handleKey(map[name], false);
            else if (/^[0-9]$/.test(name)) settings.handleKey(Qt.Key_0 + Number(name), false);
        }
    }

    // ---- Speech ------------------------------------------------------------------

    readonly property var speech: {
        if (!active) return null;
        if (zone === "sidebar") {
            var label = sideIndex === 0 ? I18n.t("settings", "row.search") : I18n.t("settings_" + area.id, area.title);
            return { context: "settings", layer: "sidebar", subject: "side-" + sideIndex,
                     intro: I18n.t("settings", "title.settings"), text: label };
        }
        if (zone === "search") {
            var hit = searchPage.onResult ? searchPage.results[searchPage.resultIndex] : null;
            return { context: "settings", layer: "search", subject: searchPage.focusId,
                     layerIntro: I18n.t("settings", "title.search"),
                     text: hit ? [hit.title, hit.path, hit.value].join(", ") :
                           (searchPage.focusId.indexOf("t-") === 0 ? searchPage.focusId.substring(2) : searchPage.typed) };
        }
        var row = focusedRow;
        if (!row) return null;
        var state = row.type === "toggle" ? I18n.t("settings", row.on ? "value.on" : "value.off") :
                    (row.type === "option" && row.selected ? I18n.t("settings", "speech.selected") : row.value);
        return { context: "settings", layer: area.id + "/" + page.id, subject: row.id,
                 layerIntro: page.title, text: [row.title, state, row.subtitle].join(", "), change: state };
    }

    // ---- Data from the TV -----------------------------------------------------------

    Connections {
        target: settings.settingsStore
        onAnswered: {
            if (method === "/getAllInputStatus") tvData.applyInputs(response);
        }
    }

    SettingsData {
        id: tvData
        settings: settings
    }

    // ---- Drawing ---------------------------------------------------------------------

    Item {
        anchors.fill: parent
        visible: opacity > 0
        opacity: settings.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        // The picture behind the modal steps back by 38 %. The host passes it to the glass.
        Rectangle {
            anchors.fill: parent
            color: GlassStyle.scrimColor
            opacity: settings.backdropVeil
        }

        MouseArea {
            anchors.fill: parent
            onClicked: settings.close()
        }

        GlassCard {
            id: card
            x: (settings.width - width) / 2
            y: (settings.height - height) / 2
            width: settings.cardWidth * settings.unit
            height: settings.cardHeight * settings.unit
            unit: settings.unit
            backdrop: settings.backdrop
            glassShader: settings.glassShader
            backdropMargin: settings.backdropMargin
            backdropArea: settings.backdropArea
            hasBackdrop: settings.hasBackdrop
            glideCurve: settings.focusCurve

            MouseArea {
                anchors.fill: parent
            }

            // Side bar: a light plate in the glass, not a second glass layer.
            GlassControl {
                x: settings.sideX * settings.unit
                y: settings.sideY * settings.unit
                width: settings.sideWidth * settings.unit
                height: (settings.cardHeight - 2 * settings.sideY) * settings.unit
                unit: settings.unit
                radius: 34
                fill: "#12ffffff"
            }

            // The chosen area keeps a plate while the focus works on the page.
            Rectangle {
                x: settings.tabX * settings.unit
                y: settings.tabY(settings.areaIndex) * settings.unit
                width: settings.tabWidth * settings.unit
                height: settings.tabHeight * settings.unit
                radius: 22 * settings.unit
                color: "#2effffff"
                opacity: settings.zone === "content" ? 1 : 0
                visible: settings.zone !== "search"
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            // Search field, with its own contour.
            Item {
                x: settings.tabX * settings.unit
                y: settings.searchY * settings.unit
                width: settings.tabWidth * settings.unit
                height: 52 * settings.unit

                Rectangle {
                    anchors.fill: parent
                    radius: 26 * settings.unit
                    color: "#2e000000"
                    border.width: Math.max(1, settings.unit)
                    border.color: "#24ffffff"
                }
            }

            Rectangle {
                x: (settings.tabX + 18) * settings.unit
                y: (settings.tabY(settings.separatorAfter + 1) - 13) * settings.unit
                width: (settings.tabWidth - 36) * settings.unit
                height: Math.max(1, settings.unit)
                color: "#24ffffff"
            }

            // The focus surface glides between side bar and page.
            FocusSurface {
                id: focusSurface
                x: settings.focusRect.x * settings.unit
                y: settings.focusRect.y * settings.unit
                width: settings.focusRect.width * settings.unit
                height: settings.focusRect.height * settings.unit
                // A StatusCard's focused button draws its own plate.
                visible: settings.zone !== "content" || (settings.page.rows.length > 0 && !settings.focusOnCard)
                unit: settings.unit
                pressScale: settings.zone === "search" ? searchPage.focusScale : 1
                // A tile grows on focus (OptionCard); the plate grows with it, so that its
                // corners stay concentric with the tile's picture.
                focusScale: settings.focusOnTile ? GlassStyle.focusScale : 1
                radius: settings.zone === "search" ? searchPage.focusRadius : (settings.zone === "sidebar" ? (settings.sideIndex === 0 ? 26 : 22) : (settings.focusOnTile ? 28 : 26))
            }

            Text {
                x: (settings.sideX + 34) * settings.unit
                y: (settings.sideY + 28) * settings.unit
                height: 40 * settings.unit
                verticalAlignment: Text.AlignVCenter
                text: I18n.t("settings", "title.settings")
                color: settings.textPrimary
                font.family: settings.titleFont
                font.pixelSize: 34 * settings.unit
                font.letterSpacing: -0.68 * settings.unit
            }

            // Search row of the side bar.
            Item {
                readonly property bool focused: settings.zone === "sidebar" && settings.sideIndex === 0
                x: settings.tabX * settings.unit
                y: settings.searchY * settings.unit
                width: settings.tabWidth * settings.unit
                height: 52 * settings.unit

                Image {
                    x: 18 * settings.unit
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28 * settings.unit
                    height: width
                    source: Qt.resolvedUrl("icons/settings-search" + (parent.focused ? "-dark" : "") + ".png")
                }

                Text {
                    x: 58 * settings.unit
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: I18n.t("settings", "row.search")
                    color: parent.focused ? settings.focusSecondary : settings.textSecondary
                    font.family: settings.valueFont
                    font.pixelSize: 20 * settings.unit
                }
            }

            Repeater {
                model: Engine.areas
                Item {
                    readonly property bool focused: settings.zone === "sidebar" && settings.sideIndex === index + 1
                    readonly property bool current: settings.areaIndex === index
                    x: settings.tabX * settings.unit
                    y: settings.tabY(index) * settings.unit
                    width: settings.tabWidth * settings.unit
                    height: settings.tabHeight * settings.unit

                    Image {
                        x: 18 * settings.unit
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28 * settings.unit
                        height: width
                        source: Qt.resolvedUrl("icons/settings-" + modelData.icon + (parent.focused ? "-dark" : "") + ".png")
                    }

                    Text {
                        x: 62 * settings.unit
                        width: parent.width - 80 * settings.unit
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: I18n.t("settings_" + modelData.id, modelData.title)
                        color: parent.focused ? settings.focusText : settings.textPrimary
                        font.family: parent.current ? settings.titleFont : settings.rowFont
                        font.pixelSize: 21 * settings.unit
                    }
                }
            }

            // ---- Search ----
            // Built on its first use, in the background once the focus reaches the search
            // field: with its keyboard it is a large part of the modal, and every opening of
            // the modal would wait for it.
            Loader {
                id: searchLoader
                x: (settings.paneX + settings.pageOffset) * settings.unit
                y: settings.paneY * settings.unit
                width: settings.paneWidth * settings.unit
                height: settings.paneHeight * settings.unit
                opacity: settings.pageFade
                visible: settings.zone === "search"
                active: settings.searchNeeded
                asynchronous: true
                sourceComponent: Component {
                    SettingsSearch {
                        owner: settings
                        unit: settings.unit
                        titleFont: settings.titleFont
                        rowFont: settings.rowFont
                        valueFont: settings.valueFont
                    }
                }
            }

            // ---- Page ----
            Item {
                id: pane
                x: (settings.paneX + settings.pageOffset) * settings.unit
                y: settings.paneY * settings.unit
                width: settings.paneWidth * settings.unit
                height: settings.paneHeight * settings.unit
                opacity: settings.pageFade
                visible: settings.zone !== "search"

                // Path of the levels above, title and second line: the shared header, large.
                PageHeader {
                    x: 20 * settings.unit
                    width: parent.width - 40 * settings.unit
                    unit: settings.unit
                    large: true
                    back: settings.stack.length > 0 ? settings.pathText() : ""
                    title: settings.page.title
                    subtitle: settings.page.subtitle
                }

                Text {
                    x: 20 * settings.unit
                    y: (settings.listTop - settings.paneY) * settings.unit
                    width: parent.width - 40 * settings.unit
                    visible: settings.page.rows.length === 0 && !settings.page.custom
                    wrapMode: Text.WordWrap
                    text: settings.revision === 0 ? "" : I18n.t("settings", "detail.nothing_here")
                    color: settings.textSecondary
                    font.family: settings.valueFont
                    font.pixelSize: 20 * settings.unit
                }

                // A page with its own content instead of rows: the upload of power-off videos
                // and the page of an own one.
                Loader {
                    id: customPage
                    y: (settings.listTop - settings.paneY) * settings.unit
                    width: parent.width
                    height: settings.listHeight * settings.unit
                    active: !!settings.page.custom     // choice pages have none at all
                    sourceComponent: settings.page.custom === "shutdownEdit" ? shutdownEditPage :
                                     settings.page.custom === "profileEdit" ? profileEditPage :
                                     settings.page.custom === "profileSignIn" ? profileSignInPage : shutdownUploadPage
                }

                Component {
                    id: profileEditPage
                    ProfileEdit {
                        unit: settings.unit
                        owner: settings
                        host: tvData
                    }
                }

                Component {
                    id: profileSignInPage
                    ProfileSignIn {
                        unit: settings.unit
                        owner: settings
                        host: tvData
                    }
                }

                Component {
                    id: shutdownUploadPage
                    ShutdownUpload {
                        unit: settings.unit
                        host: tvData     // a property named like the id would bind to itself
                    }
                }

                Component {
                    id: shutdownEditPage
                    ShutdownEdit {
                        unit: settings.unit
                        owner: settings
                        host: tvData
                        entryId: settings.page.target
                    }
                }

                // The list scrolls under the head and fades out at an end with more.
                EdgeFadeView {
                    id: listViewport
                    y: (settings.listTop - settings.paneY) * settings.unit
                    width: parent.width
                    height: settings.listHeight * settings.unit
                    fading: settings.maxScroll > 0
                    topFade: 56 * settings.unit
                    bottomFade: 96 * settings.unit
                    topAmount: settings.scroll > 1 ? 1 : 0
                    bottomAmount: settings.scroll < settings.maxScroll - 1 ? 1 : 0

                    Item {
                        width: parent.width
                        y: -settings.scroll * settings.unit
                        Behavior on y { NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: settings.focusCurve } }

                        // A pool of rows that only grows: another page reuses them and
                        // changes their texts, instead of building every row anew.
                        Repeater {
                            model: rowSlots
                            onItemAdded: PerfProbe.count("modal.rows.created")
                            delegate: SettingsRow {
                                readonly property bool used: index < settings.layout.items.length
                                entry: used ? settings.layout.items[index] : settings.emptyEntry
                                visible: used
                                owner: settings
                            }
                        }
                    }
                }
            }
        }
    }

    // K3-Ausschalt-3: a power-off video played once over the whole screen from its tile, with
    // a pill that names it. No bar: nothing loads when the TV switches off, and a bar would read
    // as one. It ends by itself once black, or with any key; Back ends it at once. The TV
    // stays on.
    ShutdownScreen {
        id: shutdownPreview

        readonly property bool shown: running || ended.running
        anchors.fill: parent
        z: 100
        visible: shown
        unit: settings.unit
        onFinished: ended.start()

        GlassControl {
            id: previewPill
            anchors.horizontalCenter: parent.horizontalCenter
            y: 48 * settings.unit
            width: previewLabel.width + 40 * settings.unit
            height: 56 * settings.unit
            unit: settings.unit
            radius: 28
            fill: "#29ffffff"
            visible: shutdownPreview.running

            Row {
                id: previewLabel
                x: 18 * settings.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * settings.unit

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl("icons/play-18.png")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Engine.text(I18n, "interface", "preview.title",
                                      { name: shutdownPreview.ownEntry ? shutdownPreview.entry.name :
                                              Engine.text(I18n, "interface", "value.shutdown_screen." + shutdownPreview.screenId) })
                    color: settings.textPrimary
                    font.family: settings.titleFont
                    font.pixelSize: 19 * settings.unit
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Engine.text(I18n, "interface", "preview.back")
                    color: settings.textSecondary
                    font.family: settings.rowFont
                    font.pixelSize: 19 * settings.unit
                }
            }
        }

        // A moment of black before the modal comes back, as after the real one.
        Timer {
            id: ended
            interval: GlassStyle.shutdownOutDuration
            onTriggered: shutdownPreview.stop()
        }
    }

    function endPreview() {
        ended.stop();
        shutdownPreview.stop();
    }

    function pathText() {
        var parts = [I18n.t("settings_" + area.id, area.title)];
        for (var i = 0; i < stack.length - 1; i++) {
            var level = stack[i];
            if (level.kind === "page") {
                var pageData = Engine.pageOf(area, level.page);
                var context = Engine.context(store, area.id, I18n);
                context.param = paramOf(i + 1);
                parts.push(!pageData ? "" : (typeof pageData.title === "function" ? pageData.title(context)
                                                                                 : context.t(pageData.title)));
            } else {
                parts.push(Engine.text(I18n, area.id, level.row.title));
            }
        }
        return parts.join("  /  ");
    }
}
