.pragma library
.import "SettingsAreaPicture.js" as Picture
.import "SettingsAreaSound.js" as Sound
.import "SettingsAreaSources.js" as Sources
.import "SettingsAreaGames.js" as Games
.import "SettingsAreaNetwork.js" as Network
.import "SettingsAreaInterface.js" as Interface
.import "SettingsAreaEnergy.js" as Energy
.import "SettingsAreaAccessibility.js" as Accessibility
.import "SettingsAreaParental.js" as Parental
.import "SettingsAreaPrivacy.js" as Privacy
.import "SettingsAreaProfile.js" as Profile
.import "SettingsAreaSystem.js" as System
.import "SettingsAreaInfo.js" as Info

// Engine of the settings modal. The catalogs say what a page may hold, LG's settings
// service says what this TV has: a row with a key shows only when the service describes
// that key as visible, and its values are the ones the service lists as visible. Model,
// region and signal differences therefore come from LG's own rules. The format of the
// catalogs is in docs/settings-catalog.md.

var areas = [Picture.area, Sound.area, Sources.area, Games.area, Network.area, Interface.area,
             Energy.area, Accessibility.area, Parental.area, Privacy.area, Profile.area, System.area, Info.area];

var maxRowsPerList = 64;

function areaById(id) {
    for (var i = 0; i < areas.length; i++) {
        if (areas[i].id === id) return areas[i];
    }
    return null;
}

function pageOf(area, pageId) {
    if (pageId && typeof pageId === "object") return pageId;     // a page built at run time
    if (!area) return null;
    if (!pageId || pageId === area.page.id) return area.page;
    return area.pages ? area.pages[pageId] || null : null;
}

// "filmMaker" -> "film_maker", "444BypassHDMI1" -> "444_bypass_hdmi1".
function snake(text) {
    if (/^[0-9.]+$/.test(String(text))) return String(text);   // "1.5" stays as it is
    return String(text).replace(/([a-z0-9])([A-Z])/g, "$1_$2").replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
                       .replace(/[^A-Za-z0-9]+/g, "_").replace(/^_+|_+$/g, "").toLowerCase();
}

function splitKey(key) {
    var dot = key.indexOf(".");
    return { category: key.slice(0, dot), name: key.slice(dot + 1) };
}

function rowKey(row, ctx) {
    if (typeof row.keyOf === "function") return row.keyOf(ctx) || "";
    return row.key || "";
}

// Some values are objects: LG keeps the video range per colour system, for example.
// A row with member reads and writes only its part.
function rowRawValue(row, ctx) {
    var value = ctx.val(rowKey(row, ctx));
    if (typeof row.field === "string") {
        return value && typeof value === "object" ? value[row.field] : undefined;
    }
    if (typeof row.member === "function") {
        var member = row.member(ctx);
        return value && typeof value === "object" && member !== undefined ? value[member] : undefined;
    }
    return value;
}

// Every key a catalog can read, per category. Rows with a computed key list theirs in watch.
function collectKeys() {
    var result = {};
    function add(key) {
        if (!key) return;
        var parts = splitKey(key);
        if (!result[parts.category]) result[parts.category] = [];
        if (result[parts.category].indexOf(parts.name) < 0) result[parts.category].push(parts.name);
    }
    function scanRows(rows) {
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (typeof row.key === "string") add(row.key);
            var lists = [row.watch || [], row.summary || []];
            for (var l = 0; l < lists.length; l++) {
                for (var k = 0; k < lists[l].length; k++) add(lists[l][k]);
            }
        }
    }
    function scanPage(page) {
        if (!page) return;
        for (var s = 0; s < page.sections.length; s++) scanRows(page.sections[s].rows);
        var extra = page.watch || [];
        for (var w = 0; w < extra.length; w++) add(extra[w]);
    }
    for (var a = 0; a < areas.length; a++) {
        var area = areas[a];
        scanPage(area.page);
        for (var id in area.pages || {}) scanPage(area.pages[id]);
        var watch = (area.watch || []).concat(area.keys || []).concat(area.reads || []);
        for (var x = 0; x < watch.length; x++) add(watch[x]);
    }
    return result;
}

function collectConfigs() {
    var names = [];
    for (var a = 0; a < areas.length; a++) {
        var list = areas[a].configs || [];
        for (var i = 0; i < list.length; i++) {
            if (names.indexOf(list[i]) < 0) names.push(list[i]);
        }
    }
    return names;
}

// The store holds what the TV reported. The modal owns it and bumps a revision on change.
function newStore() {
    return { values: {}, descs: {}, missing: {}, configs: {}, state: {}, lists: {}, dimension: {},
             apps: null };   // ids of installed apps once known
}

function applyValues(store, response) {
    var category = response.category || "option";
    if (!store.values[category]) store.values[category] = {};
    var settings = response.settings || {};
    for (var name in settings) store.values[category][name] = settings[name];
    if (response.dimension) store.dimension[category] = response.dimension;
    var errors = response.errorKey || [];
    if (!store.missing[category]) store.missing[category] = {};
    for (var i = 0; i < errors.length; i++) {
        if (settings[errors[i]] === undefined) store.missing[category][errors[i]] = true;
    }
}

// LG lists keys in errorKey even when it describes them, so only the results count.
function applyDescs(store, response, asked) {
    var results = response.results || [];
    var seen = {};
    for (var i = 0; i < results.length; i++) {
        var desc = results[i];
        var category = desc.category || asked.category;
        if (!store.descs[category]) store.descs[category] = {};
        store.descs[category][desc.key] = desc;
        seen[desc.key] = true;
    }
    if (!asked || !asked.keys) return;
    if (!store.descs[asked.category]) store.descs[asked.category] = {};
    for (var k = 0; k < asked.keys.length; k++) {
        if (!seen[asked.keys[k]] && store.descs[asked.category][asked.keys[k]] === undefined) {
            store.descs[asked.category][asked.keys[k]] = null;   // the TV does not know it
        }
    }
}

function context(store, areaId, i18n) {
    var ctx = {
        state: store.state,
        val: function (key) {
            var parts = splitKey(key);
            var table = store.values[parts.category];
            return table ? table[parts.name] : undefined;
        },
        desc: function (key) {
            var parts = splitKey(key);
            var table = store.descs[parts.category];
            return table ? table[parts.name] : undefined;
        },
        known: function (key) {
            var parts = splitKey(key);
            var table = store.descs[parts.category];
            return table !== undefined && table[parts.name] !== undefined;
        },
        // novOS's own values (category "novos") always exist.
        has: function (key) {
            if (key.indexOf("novos.") === 0) return true;
            var desc = ctx.desc(key);
            return !!desc && !(desc.ui && desc.ui.visible === false);
        },
        cfg: function (name) {
            return store.configs[name];
        },
        installed: function (appId) {
            return store.apps === null || store.apps.indexOf(appId) >= 0;
        },
        list: function (name) {
            return store.lists[name] || [];
        },
        t: function (key, params) {
            return text(i18n, areaId, key, params);
        },
        label: function (key, value) {
            return valueLabel(i18n, areaId, key, value);
        }
    };
    return ctx;
}

// A key of the own area wins over the shared texts.
function text(i18n, areaId, key, params) {
    if (!key) return "";
    var own = i18n.t("settings_" + areaId, key, params);
    if (own !== "settings_" + areaId + "/" + key) return own;
    return i18n.t("settings", key, params);
}

function valueLabel(i18n, areaId, key, value) {
    if (value === undefined || value === null) return "";
    if (typeof value === "boolean") return text(i18n, areaId, value ? "value.on" : "value.off");
    var name = splitKey(key).name;
    var textKey = "value." + snake(name) + "." + snake(value);
    var found = text(i18n, areaId, textKey);
    if (found !== "settings/" + textKey) return found;
    for (var i = 0; i < areas.length; i++) {
        var other = i18n.t("settings_" + areas[i].id, textKey);
        if (other !== "settings_" + areas[i].id + "/" + textKey) return other;
    }
    if (value === "on" || value === "off") return text(i18n, areaId, "value." + value);
    return String(value);
}

function call(value, ctx) {
    return typeof value === "function" ? value(ctx) : value;
}

// Visible: the service describes the key as visible (or the row has no key), and what
// the row itself requires holds. A page link is visible when its page shows a row.
function rowVisible(row, ctx, depth) {
    if (row.hidden === true) return false;
    if (typeof row.requires === "function" && !row.requires(ctx)) return false;
    var key = rowKey(row, ctx);
    if (key && row.type !== "page" && row.type !== "lgApp" && row.type !== "action" && row.type !== "info") {
        // A few keys carry a value but no descriptor on some firmware.
        var optional = row.descOptional === true && ctx.desc(key) === null && ctx.val(key) !== undefined;
        // hiddenOk: a key LG keeps out of its menus on purpose, shown here.
        var hiddenOk = row.hiddenOk === true && !!ctx.desc(key);
        if (!ctx.has(key) && !optional && !hiddenOk) return false;
    }
    // Another model may lack an LG app; once the list of apps is known, the row follows it.
    if (row.type === "lgApp" && row.app && ctx.installed && !ctx.installed(row.app.id)) return false;
    if (row.needs) {
        for (var n = 0; n < row.needs.length; n++) {
            if (!ctx.has(row.needs[n])) return false;
        }
    }
    if (row.type === "choice" && choiceOptions(row, ctx).length === 0) return false;
    // A single value as its own row, like one output on the sound output page.
    if (row.type === "option" && key && key.indexOf("novos.") !== 0) {
        var listed = (ctx.desc(key) || {}).values;
        var values = listed && listed.arrayExt ? listed.arrayExt : [];
        var found = false;
        for (var v = 0; v < values.length; v++) {
            if (values[v].value === row.option && values[v].visible !== false) found = true;
        }
        if (!found) return false;
    }
    if (row.type === "page") {
        if ((depth || 0) > 3) return true;
        return pageHasRows(ctx.area, row.page, ctx, (depth || 0) + 1);
    }
    if (row.type === "list") return ctx.list(row.source).length > 0;
    return true;
}

// A key the TV has not answered yet keeps its row out until it does.
function pageHasRows(area, pageId, ctx, depth) {
    var page = pageOf(area, pageId);
    if (!page) return false;
    if (page.custom) return true;          // a page with its own content, as the profile's
    for (var s = 0; s < page.sections.length; s++) {
        var rows = page.sections[s].rows;
        for (var r = 0; r < rows.length; r++) {
            if (rowVisible(rows[r], ctx, depth)) return true;
        }
    }
    return false;
}

function disabledReason(row, ctx) {
    var rules = row.disabled || [];
    for (var i = 0; i < rules.length; i++) {
        if (rules[i].when(ctx)) return ctx.t(rules[i].reason);
    }
    var key = rowKey(row, ctx);
    var desc = key ? ctx.desc(key) : null;
    if (desc && desc.ui && desc.ui.active === false && row.type !== "page") return ctx.t("reason.not_available_now");
    return "";
}

function choiceOptions(row, ctx) {
    if (typeof row.options === "function") {
        var own = row.options(ctx) || [];
        var result = [];
        for (var n = 0; n < own.length; n++) {
            result.push({ value: own[n].id, label: own[n].label, active: own[n].active !== false,
                          selected: own[n].selected === true, write: own[n].write,
                          action: own[n].action, params: own[n].params });
        }
        return result;
    }
    var key = rowKey(row, ctx);
    var desc = ctx.desc(key);
    var options = [];
    var listed = desc && desc.values && desc.values.arrayExt ? desc.values.arrayExt : [];
    var wanted = row.values || null;
    var exclude = row.exclude || [];
    var order = wanted || [];
    if (!wanted) {
        for (var i = 0; i < listed.length; i++) order.push(listed[i].value);
    }
    for (var o = 0; o < order.length; o++) {
        var value = order[o];
        if (exclude.indexOf(value) >= 0) continue;
        var entry = null;
        for (var j = 0; j < listed.length; j++) {
            if (listed[j].value === value) entry = listed[j];
        }
        if (!entry && !row.values) continue;
        if (entry && entry.visible === false) continue;
        if (!entry && listed.length > 0) continue;     // the TV lists values, this one is not among them
        options.push({ value: value, label: ctx.label(key, value), active: !entry || entry.active !== false });
    }
    return options;
}

function sliderRange(row, ctx) {
    var desc = ctx.desc(rowKey(row, ctx));
    var range = desc && desc.values && desc.values.range ? desc.values.range : {};
    var min = row.min !== undefined ? row.min : (range.min !== undefined ? range.min : 0);
    var max = row.max !== undefined ? row.max : (range.max !== undefined ? range.max : 100);
    var interval = range.interval || 1;
    return { min: min, max: max, interval: interval, step: (row.step || 1) * interval };
}

function numberOf(value) {
    var number = Number(value);
    return isNaN(number) ? 0 : number;
}

function formatNumber(row, value, ctx) {
    var number = numberOf(value);
    var size = String(Math.abs(number));
    if (row.format === "signed" && number > 0) return "+" + number;
    // LG's own words: warm below zero, cold above; red below, green above.
    if (row.format === "temperature" && number !== 0) {
        return ctx.t(number > 0 ? "value.cold" : "value.warm", { value: size });
    }
    if (row.format === "tint" && number !== 0) return (number < 0 ? "R" : "G") + size;
    return String(number);
}

// The text at the right of a row.
function rowValue(row, ctx) {
    if (row.value !== undefined) return call(row.value, ctx) || "";
    if (row.type === "choice" && typeof row.options === "function") {
        var options = choiceOptions(row, ctx);
        for (var i = 0; i < options.length; i++) {
            if (options[i].selected) return options[i].label;
        }
        return "";
    }
    var key = rowKey(row, ctx);
    if (!key) return "";
    var value = rowRawValue(row, ctx);
    if (value === undefined || value === null) return "";
    if (row.type === "slider") return formatNumber(row, value, ctx);
    if (row.type === "toggle") return "";
    if (row.format && typeof row.format === "function") return row.format(value, ctx);
    return ctx.label(key, value);
}

function toggleOn(row, ctx) {
    var value = rowRawValue(row, ctx);
    var on = row.on !== undefined ? row.on : "on";
    if (typeof row.isOn === "function") return row.isOn(value, ctx);
    if (typeof row.member === "string") return Array.isArray(value) && value.indexOf(row.member) >= 0;
    if (row.bit !== undefined) return (numberOf(value) & (1 << row.bit)) !== 0;
    if (row.onValues) return row.onValues.indexOf(value) >= 0;
    return value === on;
}

// The row of a page that shows a key, for the titles and formats of a summary.
function rowWithKey(pageId, key, ctx) {
    var page = pageOf(ctx.area, pageId);
    if (!page) return null;
    for (var s = 0; s < page.sections.length; s++) {
        var rows = page.sections[s].rows;
        for (var r = 0; r < rows.length; r++) {
            if (rows[r].key === key) return rows[r];
        }
    }
    return null;
}

// "Panel-Helligkeit 70 · Local Dimming Mittel": the first two keys this TV shows.
function summaryText(row, ctx) {
    var parts = [];
    var keys = row.summary || [];
    for (var i = 0; i < keys.length && parts.length < 2; i++) {
        var entry = keys[i];
        var key = typeof entry === "string" ? entry : entry.key;
        if (!ctx.has(key)) continue;
        var value = ctx.val(key);
        if (value === undefined || value === null || typeof value === "object") continue;
        var target = rowWithKey(row.page, key, ctx);
        var titleKey = typeof entry === "string" ? "summary." + snake(splitKey(key).name) : entry.title;
        var title = ctx.t(titleKey);
        if (title.indexOf("/" + titleKey) >= 0) title = target ? ctx.t(target.title) : "";
        var shown;
        if (target && target.type === "slider") shown = formatNumber(target, value, ctx);
        else if (target && target.type === "toggle") shown = ctx.t(toggleOn(target, ctx) ? "value.on" : "value.off");
        else shown = ctx.label(key, value);
        parts.push((title + " " + shown).trim());
    }
    return parts.join(" · ");
}

function resolveRow(row, ctx) {
    var reason = disabledReason(row, ctx);
    var subtitle = reason;
    if (subtitle === "" && row.type === "page" && row.summary) subtitle = summaryText(row, ctx);
    if (subtitle === "" && typeof row.subtitle === "function") subtitle = row.subtitle(ctx) || "";
    else if (subtitle === "" && row.subtitle) subtitle = ctx.t(row.subtitle);
    var resolved = {
        id: row.id,
        type: row.type,
        title: typeof row.title === "function" ? row.title(ctx) : ctx.t(row.title),
        subtitle: subtitle,
        value: "",
        disabled: reason !== "",
        focusable: row.focusable !== false,
        external: row.type === "lgApp",
        danger: row.danger === true,
        thumb: row.thumb || "",
        preview: row.preview || null,
        row: row
    };
    // A card with the state of a task and its buttons, and a block of release notes.
    if (row.type === "statusCard") {
        resolved.card = row.card(ctx);
        var buttons = resolved.card.buttons || [];
        resolved.focusable = buttons.some(function (button) { return button.disabled !== true; });
    } else if (row.type === "notes") {
        resolved.notes = row.notes(ctx) || [];
    }
    if (row.type === "toggle") resolved.on = toggleOn(row, ctx);
    else if (row.type === "option") {
        resolved.option = row.option;
        resolved.selected = String(rowRawValue(row, ctx)) === String(row.option);
        resolved.value = row.value !== undefined ? call(row.value, ctx) || "" : "";
    } else if (row.type === "slider") {
        var range = sliderRange(row, ctx);
        resolved.min = range.min;
        resolved.max = range.max;
        resolved.number = numberOf(rowRawValue(row, ctx));
        resolved.value = formatNumber(row, resolved.number, ctx);
    } else {
        resolved.value = rowValue(row, ctx);
    }
    return resolved;
}

// Rows of a host list. Each entry brings its own id, title and value.
function listRows(row, ctx) {
    var items = ctx.list(row.source);
    var rows = [];
    for (var i = 0; i < items.length && i < maxRowsPerList; i++) {
        var item = items[i];
        rows.push({
            id: row.id + ":" + item.id,
            type: "listItem",
            title: item.title,
            subtitle: item.subtitle || "",
            value: item.value || "",
            disabled: item.disabled === true,
            focusable: item.focusable !== false,
            selected: item.selected === true,
            external: item.external === true,
            thumb: item.thumb || "",
            preview: item.preview || null,
            row: row,
            item: item
        });
    }
    return rows;
}

// A page as the modal draws it, with only what this TV can show.
// param is the entry a page was opened for, for example the input of an input's page.
function resolvePage(store, i18n, areaId, pageId, param) {
    var area = areaById(areaId);
    var page = pageOf(area, pageId);
    var ctx = context(store, areaId, i18n);
    ctx.area = area;
    ctx.param = param;
    if (!page) return { id: pageId, title: "", subtitle: "", sections: [], rows: [] };
    var sections = [];
    var all = [];
    for (var s = 0; s < page.sections.length; s++) {
        var section = page.sections[s];
        var rows = [];
        for (var r = 0; r < section.rows.length; r++) {
            var row = section.rows[r];
            if (!rowVisible(row, ctx, 0)) continue;
            if (row.type === "list") rows = rows.concat(listRows(row, ctx));
            else rows.push(resolveRow(row, ctx));
        }
        if (rows.length === 0) continue;
        var keys = [];
        for (var k = 0; k < (section.keys || []).length; k++) {
            // textOwn: the text while the focus is on an own entry (an own power-off video).
            var spec = section.keys[k];
            keys.push({ cap: spec.cap, text: ctx.t(spec.text), textOwn: spec.textOwn ? ctx.t(spec.textOwn) : "" });
        }
        // heading: a large title of its own with a text at the right, as "Neu in 1.0" and its date.
        var heading = typeof section.heading === "function" ? section.heading(ctx) :
                      (section.heading ? { title: ctx.t(section.heading), aside: "" } : null);
        // A title may depend on the TV, as the active profile's name.
        var sectionTitle = typeof section.title === "function" ? section.title(ctx) :
                           (section.title ? ctx.t(section.title) : "");
        sections.push({ title: sectionTitle, rows: rows,
                        note: section.note ? ctx.t(call(section.note, ctx)) : "",
                        columns: section.columns || 0, keys: keys, heading: heading });
        all = all.concat(rows);
    }
    var title = typeof page.title === "function" ? page.title(ctx) : ctx.t(page.title);
    var subtitle = call(page.subtitle, ctx);
    if (!subtitle && area.perSource && pageId === area.page.id && store.state.source) {
        subtitle = ctx.t("detail.applies_to", { source: store.state.source });
    } else if (subtitle && typeof page.subtitle !== "function") {
        subtitle = ctx.t(subtitle);
    }
    var hero = typeof page.hero === "function" ? page.hero(ctx) : null;
    return { id: page.id, title: title, subtitle: subtitle || "", sections: sections, rows: all, hero: hero,
             note: page.note ? ctx.t(call(page.note, ctx)) : "", custom: page.custom || "",
             target: page.target || "" };
}

// The page of a choice: one row per visible value, the current one checked.
function resolveChoice(store, i18n, areaId, row, param) {
    var ctx = context(store, areaId, i18n);
    ctx.param = param;
    var current = rowRawValue(row, ctx);
    var options = choiceOptions(row, ctx);
    var rows = [];
    for (var i = 0; i < options.length; i++) {
        var selected = options[i].selected !== undefined ? options[i].selected
                                                         : String(options[i].value) === String(current);
        rows.push({ id: "option:" + options[i].value, type: "option", title: options[i].label,
                    subtitle: options[i].active ? "" : ctx.t("reason.not_available_now"),
                    value: "", disabled: !options[i].active, focusable: true,
                    selected: selected, option: options[i].value, write: options[i].write,
                    action: options[i].action, params: options[i].params, row: row });
    }
    return { id: "choice:" + row.id, title: ctx.t(row.title), subtitle: "",
             sections: [{ title: "", rows: rows, note: row.note ? ctx.t(row.note) : "" }], rows: rows,
             note: row.note ? ctx.t(row.note) : "" };
}

// The payload LG's own settings app sends. Picture values of a mode also mark that mode
// as changed, the way LG does it, so its "Reset" knows what to reset.
function writeRequest(store, row, value, ctx) {
    var key = rowKey(row, ctx);
    var parts = splitKey(key);
    var settings = {};
    var whole = ctx.val(key);
    if (typeof row.field === "string") {
        var fields = {};
        if (whole && typeof whole === "object") {
            for (var f in whole) fields[f] = whole[f];
        }
        fields[row.field] = value;
        settings[parts.name] = fields;
    } else if (typeof row.member === "string") {
        // value is the new state of the member in the list.
        var list = Array.isArray(whole) ? whole.slice() : [];
        var at = list.indexOf(row.member);
        if (value && at < 0) list.push(row.member);
        if (!value && at >= 0) list.splice(at, 1);
        settings[parts.name] = list;
    } else if (row.bit !== undefined) {
        // value is the new state of the bit; the mask keeps its type.
        var mask = numberOf(whole);
        mask = value ? (mask | (1 << row.bit)) : (mask & ~(1 << row.bit));
        settings[parts.name] = typeof whole === "string" ? String(mask) : mask;
    } else if (typeof row.member === "function") {
        var copy = {};
        if (whole && typeof whole === "object") {
            for (var part in whole) copy[part] = whole[part];
        }
        copy[row.member(ctx)] = value;
        settings[parts.name] = copy;
    } else {
        settings[parts.name] = value;
    }
    var extras = [call(row.extra, ctx), call(row.alsoWrite, ctx)];
    for (var e = 0; e < extras.length; e++) {
        for (var name in extras[e] || {}) settings[name] = extras[e][name];
    }
    if (parts.category === "picture" && parts.name !== "pictureMode") {
        var desc = ctx.desc(key);
        var dims = desc && desc.dimension ? desc.dimension : [];
        var mode = ctx.val("picture.pictureMode");
        if (dims.indexOf("pictureMode") >= 0 && mode) {
            var modified = ctx.val("picture.pictureSettingModified") || {};
            if (modified[mode] !== true) {
                var marked = {};
                for (var m in modified) marked[m] = modified[m];
                marked[mode] = true;
                settings.pictureSettingModified = marked;
            }
        }
    }
    return { category: parts.category, settings: settings, notifySelf: false };
}

function nextToggleValue(row, ctx) {
    if (typeof row.member === "string" || row.bit !== undefined) return !toggleOn(row, ctx);
    var on = row.on !== undefined ? row.on : "on";
    var off = row.off !== undefined ? row.off : "off";
    return toggleOn(row, ctx) ? off : on;
}

function sliderStep(row, ctx, direction) {
    var range = sliderRange(row, ctx);
    var current = numberOf(rowRawValue(row, ctx));
    return Math.max(range.min, Math.min(range.max, current + direction * range.step));
}

// Search over every row this TV shows: names, own search terms and LG's terms.
function normalize(value) {
    return String(value).toLowerCase().replace(/ä/g, "a").replace(/ö/g, "o").replace(/ü/g, "u")
                        .replace(/ß/g, "ss").replace(/[^a-z0-9 ]/g, " ");
}

function searchIndex(store, i18n) {
    var entries = [];
    for (var a = 0; a < areas.length; a++) {
        var area = areas[a];
        var ctx = context(store, area.id, i18n);
        ctx.area = area;
        var areaTitle = ctx.t(area.title);
        // chain: the pages below the area to open, each with the row that leads there.
        var visit = function (pageId, path, depth, chain) {
            var page = pageOf(area, pageId);
            if (!page || depth > 3) return;
            for (var s = 0; s < page.sections.length; s++) {
                var rows = page.sections[s].rows;
                for (var r = 0; r < rows.length; r++) {
                    var row = rows[r];
                    // A card and a block of notes are no setting of their own.
                    if (row.type === "list" || row.type === "info" || row.type === "statusCard" ||
                        row.type === "notes" || !rowVisible(row, ctx, 0)) continue;
                    var title = typeof row.title === "function" ? row.title(ctx) : ctx.t(row.title);
                    var terms = row.search ? ctx.t(row.search) : "";
                    var shown = row.type === "toggle" ? ctx.t(toggleOn(row, ctx) ? "value.on" : "value.off") :
                                (row.type === "page" ? "" : rowValue(row, ctx));
                    entries.push({ area: area.id, page: pageId, row: row.id, title: title, path: path,
                                   chain: chain, terms: normalize(title + " " + terms), value: shown });
                    if (row.type === "page") {
                        visit(row.page, path + " › " + title, depth + 1, chain.concat([{ page: row.page, rowId: row.id }]));
                    }
                }
            }
        };
        visit(area.page.id, areaTitle, 0, []);
    }
    return entries;
}

function search(entries, query, limit) {
    var wanted = normalize(query).trim();
    if (wanted === "") return [];
    var words = wanted.split(/ +/);
    var starts = [];
    var contains = [];
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        var all = true;
        for (var w = 0; w < words.length; w++) {
            if (entry.terms.indexOf(words[w]) < 0) all = false;
        }
        if (!all) continue;
        if (normalize(entry.title).indexOf(words[0]) === 0) starts.push(entry);
        else contains.push(entry);
    }
    return starts.concat(contains).slice(0, limit || 30);
}
