import QtQuick 2.12
import WebOSServices 1.0
import "."
import "SettingsEngine.js" as Engine

// The one place that holds LG's settings for every novOS surface: values, descriptors,
// configs and the writing, as LG's own settings app does them (docs/lg-settings). The quick
// panel and the settings modal share one instance, so a setting has one name, one value
// and one way of being written wherever it shows (docs/shared-components.md, point 1).
//
// Keys are "category.name" as in the catalogs (SettingsArea*.js). A key the catalogs name
// gets its title, value names and the write of its catalog row (for example
// pictureSettingModified for picture values), so the panel and the modal cannot differ.
Item {
    id: settingsStore

    property var store: Engine.newStore()
    property int revision: 0
    property bool requested: false
    // Descriptors are large (about 93 KB for every key) and every answer is garbage the
    // JavaScript heap has to collect, which pauses the window for 70 ms and more. A surface
    // that needs only a few names them here ("category.name"); describeAll() asks for the
    // rest once a surface needs them, like the settings modal. null asks for all at once.
    property var descKeys: null
    property bool describedAll: false
    property var descAsked: ({})              // per category, the key lists still unanswered
    property var pendingWrite: null
    property var extraKeys: ({})           // keys a surface needs beyond the catalogs
    readonly property int writeDelay: 120

    // The minutes of the sleep timer, as LG offers them. Panel and modal use this list.
    readonly property var sleepChoices: [0, 10, 20, 30, 60, 90, 120, 180, 240]

    // Every answer that is not a settings value, for the surface that asked.
    signal answered(string method, var response)

    function keys() {
        var all = Engine.collectKeys();
        for (var category in extraKeys) {
            if (!all[category]) all[category] = [];
            for (var i = 0; i < extraKeys[category].length; i++) {
                if (all[category].indexOf(extraKeys[category][i]) < 0) all[category].push(extraKeys[category][i]);
            }
        }
        return all;
    }

    // Subscribes once to every value and to the descriptors in descKeys.
    function request() {
        if (requested) return;
        requested = true;
        var all = keys();
        for (var category in all) {
            if (category === "novos") continue;
            call("luna://com.webos.settingsservice", "/getSystemSettings",
                 { category: category, keys: all[category], subscribe: true });
            var wanted = [];
            for (var i = 0; i < all[category].length; i++) {
                if (descKeys === null || descKeys.indexOf(category + "." + all[category][i]) >= 0) {
                    wanted.push(all[category][i]);
                }
            }
            describe(category, wanted);
        }
        describedAll = descKeys === null;
        var configs = Engine.collectConfigs();
        if (configs.length > 0) call("luna://com.webos.service.config", "/getConfigs", { configNames: configs });
    }

    // The descriptors request() left out.
    function describeAll() {
        request();
        if (describedAll) return;
        describedAll = true;
        var all = keys();
        for (var category in all) {
            if (category === "novos") continue;
            var rest = [];
            for (var i = 0; i < all[category].length; i++) {
                if (descKeys.indexOf(category + "." + all[category][i]) < 0) rest.push(all[category][i]);
            }
            describe(category, rest);
        }
    }

    function describe(category, names) {
        if (names.length === 0) return;
        if (!descAsked[category]) descAsked[category] = [];
        descAsked[category].push(names);
        call("luna://com.webos.settingsservice", "/getSystemSettingDesc",
             { category: category, keys: names, subscribe: true });
    }

    // After a refused write the shown values may be wrong: read them again once.
    function reread() {
        var all = keys();
        for (var category in all) {
            if (category === "novos") continue;
            call("luna://com.webos.settingsservice", "/getSystemSettings", { category: category, keys: all[category] });
        }
    }

    function call(uri, method, params) {
        service.call(uri, method, typeof params === "string" ? params : JSON.stringify(params || {}));
    }

    // Many answers arrive at once; consumers rebuild once for all of them.
    function changed() {
        refresh.restart();
    }

    Timer {
        id: refresh
        interval: 16
        onTriggered: {
            var started = PerfProbe.now();
            settingsStore.revision++;
            PerfProbe.cost("store.revision", started, settingsStore.revision);
        }
    }

    // ---- Reading ---------------------------------------------------------------

    function context(areaId, param) {
        var ctx = Engine.context(store, areaId || "", I18n);
        ctx.area = Engine.areaById(areaId) || null;
        ctx.param = param;
        return ctx;
    }

    function val(key) {
        return context("").val(key);
    }

    function desc(key) {
        return context("").desc(key);
    }

    // The TV shows the key: described and not hidden.
    function has(key) {
        return context("").has(key);
    }

    // LG's list of values for a key, for example the picture modes of the current signal.
    function options(key) {
        var d = desc(key);
        return d && d.values && d.values.arrayExt ? d.values.arrayExt : [];
    }

    function dimension(category) {
        return store.dimension[category] || {};
    }

    property var rowIndex: null

    // The catalog row that shows a key, with its area: { area, row }.
    function rowOf(key) {
        if (rowIndex === null) {
            var index = {};
            for (var a = 0; a < Engine.areas.length; a++) {
                var area = Engine.areas[a];
                var pages = [area.page];
                for (var id in area.pages || {}) pages.push(area.pages[id]);
                for (var p = 0; p < pages.length; p++) {
                    var sections = pages[p].sections || [];
                    for (var s = 0; s < sections.length; s++) {
                        var rows = sections[s].rows || [];
                        for (var r = 0; r < rows.length; r++) {
                            var k = rows[r].key;
                            if (typeof k === "string" && index[k] === undefined && rows[r].field === undefined &&
                                rows[r].member === undefined && rows[r].bit === undefined) {
                                index[k] = { area: area, row: rows[r] };
                            }
                        }
                    }
                }
            }
            rowIndex = index;
        }
        return rowIndex[key] || null;
    }

    // A text of an area's catalog, for rows without a settings key (timers, the TV name).
    function text(areaId, key, params) {
        return Engine.text(I18n, areaId, key, params);
    }

    // The name of an area, the same in the panel's list and the modal's side bar.
    function areaTitle(areaId) {
        var area = Engine.areaById(areaId);
        return area ? Engine.text(I18n, areaId, area.title) : areaId;
    }

    // The name of a setting as the settings modal shows it.
    function title(key) {
        var found = rowOf(key);
        return found ? Engine.text(I18n, found.area.id, found.row.title) : key;
    }

    // The name of a value, current when value is left out.
    function label(key, value) {
        var found = rowOf(key);
        var areaId = found ? found.area.id : "";
        var shown = value === undefined ? val(key) : value;
        if (found && found.row.type === "choice" && typeof found.row.options === "function" && value !== undefined) {
            var ctx = context(areaId);
            var choices = Engine.choiceOptions(found.row, ctx);
            for (var i = 0; i < choices.length; i++) {
                if (choices[i].value === value || choices[i].id === String(value)) return choices[i].label;
            }
        }
        return Engine.valueLabel(I18n, areaId, key, shown);
    }

    // A sleep time as text, "Aus", "30 Minuten", "1,5 Stunden".
    function minutesLabel(minutes) {
        var ctx = context("energy");
        if (minutes === 0) return ctx.t("value.off");
        if (minutes < 60) return ctx.t("value.minutes", { count: minutes });
        var hours = minutes / 60;
        var text = hours % 1 === 0 ? String(hours) :
                   hours.toFixed(1).replace(".", Qt.locale(I18n.qtLocale).decimalPoint);
        return ctx.t(hours === 1 ? "value.hour_one" : "value.hours", { count: text });
    }

    // ---- Writing ---------------------------------------------------------------

    // Writes one key the way its catalog row does; keys without a row are written plain.
    function set(key, value) {
        var found = rowOf(key);
        var row = found ? found.row : { key: key };
        var ctx = context(found ? found.area.id : "");
        commit(Engine.writeRequest(store, row, value, ctx), row, ctx);
    }

    // Several keys of one category in one write, for example the hour and minute of a timer.
    function setAll(category, values) {
        commit({ category: category, settings: values, notifySelf: false }, null, context(""));
    }

    // A ready payload: shows at once, reaches the TV once the key rests.
    function commit(request, row, context) {
        var name = row ? Engine.splitKey(Engine.rowKey(row, context)).name : "";
        // LG keeps many numbers as strings; a slider writes the type it read.
        if (row && row.type === "slider" && typeof context.val(Engine.rowKey(row, context)) === "string") {
            request.settings[name] = String(request.settings[name]);
        }
        if (!store.values[request.category]) store.values[request.category] = {};
        for (var key in request.settings) store.values[request.category][key] = request.settings[key];
        changed();
        if (pendingWrite && (pendingWrite.category !== request.category || name === "" ||
                             !(name in pendingWrite.settings))) {
            flushWrite();
        }
        pendingWrite = request;
        writeTimer.restart();
    }

    function flushWrite() {
        writeTimer.stop();
        if (!pendingWrite) return;
        call("luna://com.webos.settingsservice", "/setSystemSettings", pendingWrite);
        pendingWrite = null;
    }

    Timer {
        id: writeTimer
        interval: settingsStore.writeDelay
        onTriggered: settingsStore.flushWrite()
    }

    // One answer of LG's services. The probe notes how long each took and how large it was.
    function answer(method, payload) {
        var response = JSON.parse(payload);
        if (method === "/getSystemSettings") {
            // An echo must not undo a value that is still waiting to be written.
            if (response.settings && settingsStore.pendingWrite &&
                settingsStore.pendingWrite.category === (response.category || "option")) {
                for (var waiting in settingsStore.pendingWrite.settings) delete response.settings[waiting];
            }
            if (response.settings) Engine.applyValues(settingsStore.store, response);
        } else if (method === "/getSystemSettingDesc") {
            var results = response.results || [];
            var category = results.length > 0 ? results[0].category : "";
            // The first answer to a request marks the keys it asked for and did not get.
            var waiting = category !== "" ? settingsStore.descAsked[category] : undefined;
            var askedKeys = waiting && waiting.length > 0 ? waiting.shift() : null;
            Engine.applyDescs(settingsStore.store, response,
                              askedKeys ? { category: category, keys: askedKeys } : null);
        } else if (method === "/getConfigs" && response.configs) {
            for (var name in response.configs) settingsStore.store.configs[name] = response.configs[name];
            settingsStore.answered(method, response);
        } else if (method === "/setSystemSettings" || method === "/resetSystemSettings") {
            if (response.returnValue === false) settingsStore.reread();
            return;
        } else {
            settingsStore.answered(method, response);
            return;
        }
        settingsStore.changed();
    }

    Service {
        id: service
        appId: "com.webos.app.quicksettings"
        onResponse: {
            var started = PerfProbe.now();
            settingsStore.answer(method, payload);
            PerfProbe.cost("luna" + method, started, payload.length);
            PerfProbe.count("bytes" + method, payload.length);
        }
        onError: {
            if (method === "/setSystemSettings") settingsStore.reread();
        }
    }
}
