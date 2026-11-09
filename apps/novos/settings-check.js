#!/usr/bin/env node
// Builds every page of the settings modal outside the TV: the catalogs and the engine
// run in Node against values and descriptors read from a TV, with the same text lookup
// as lib/ui/I18n.qml. It finds script errors, missing texts and pages that stay empty
// before anything goes to the TV.
//
//   node settings-check.js keys                 prints the keys to read, per category
//   node settings-check.js run <state.json> [de] builds all pages; state from fetch below
//
// The state file comes from the TV, read only:
//   node settings-check.js keys > /tmp/keys.json && sh settings-fetch.sh /tmp/keys.json > state.json
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const MODULE = path.join(__dirname, "module");
const LIB = path.join(__dirname, "../../lib/ui");

// Loads a .pragma library file and its .import lines into one sandbox per file.
function loadLibrary(file, cache) {
    if (cache[file]) return cache[file];
    const source = fs.readFileSync(path.join(MODULE, file), "utf8");
    const sandbox = { console };
    const lines = source.split("\n").map((line) => {
        const match = line.match(/^\.import "(.+)" as (\w+)/);
        if (match) {
            sandbox[match[2]] = loadLibrary(match[1], cache);
            return "";
        }
        return line.startsWith(".pragma") ? "" : line;
    });
    vm.createContext(sandbox);
    vm.runInContext(lines.join("\n"), sandbox, { filename: file });
    cache[file] = sandbox;
    return sandbox;
}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
        return {};
    }
}

// The same lookup as I18n.qml: own language, then English, then "namespace/key".
function makeI18n(language, missing) {
    const tables = {};
    function table(lang, namespace) {
        const id = lang + ":" + namespace;
        if (!tables[id]) {
            if (namespace === "settings") tables[id] = readJson(path.join(MODULE, "i18n/settings/common", lang + ".json"));
            else if (namespace.startsWith("settings_")) {
                tables[id] = readJson(path.join(MODULE, "i18n/settings", namespace.slice(9), lang + ".json"));
            } else {
                // The app's texts and lib/ui's, merged by namespace as lib/ui/stage.py does.
                tables[id] = readJson(path.join(MODULE, "i18n", lang + ".json"))[namespace] ||
                             readJson(path.join(LIB, "i18n", lang + ".json"))[namespace] || {};
            }
        }
        return tables[id];
    }
    return {
        t(namespace, key, params) {
            let text = table(language, namespace)[key];
            if (text === undefined) text = table("en", namespace)[key];
            if (text === undefined) text = namespace + "/" + key;
            for (const name in params || {}) text = text.split("{" + name + "}").join(String(params[name]));
            return text;
        }
    };
}

function main() {
    const mode = process.argv[2];
    const engine = loadLibrary("SettingsEngine.js", {});
    if (mode === "keys") {
        process.stdout.write(JSON.stringify({ keys: engine.collectKeys(), configs: engine.collectConfigs() }, null, 1));
        return;
    }
    const state = readJson(process.argv[3]);
    const language = process.argv[4] || "de";
    const store = engine.newStore();
    for (const response of state.values || []) engine.applyValues(store, response);
    for (const response of state.descs || []) {
        const results = response.results || [];
        const category = response.asked ? response.asked.category : (results[0] || {}).category;
        engine.applyDescs(store, response, { category, keys: (response.asked || {}).keys || [] });
    }
    Object.assign(store.configs, state.configs || {});
    Object.assign(store.state, state.state || {});
    Object.assign(store.lists, state.lists || {});
    if (state.apps) store.apps = state.apps;

    const missingTexts = new Set();
    const i18n = makeI18n(language, missingTexts);
    let pages = 0;
    let rows = 0;
    const empty = [];
    const errors = [];
    for (const area of engine.areas) {
        const pageIds = [area.page.id].concat(Object.keys(area.pages || {}));
        console.log("\n## " + i18n.t("settings_" + area.id, area.title) + " (" + area.id + ")");
        for (const pageId of pageIds) {
            let page;
            try {
                page = engine.resolvePage(store, i18n, area.id, pageId, state.param && state.param[area.id]);
            } catch (error) {
                errors.push(area.id + "/" + pageId + ": " + error.message);
                continue;
            }
            pages++;
            if (page.rows.length === 0) empty.push(area.id + "/" + pageId);
            console.log("  [" + pageId + "] " + page.title + (page.subtitle ? " — " + page.subtitle : ""));
            for (const text of [page.title, page.subtitle]) {
                if (/settings(_\w+)?\//.test(text)) missingTexts.add(area.id + "/" + pageId + ": " + text);
            }
            for (const row of page.rows) {
                rows++;
                for (const text of [row.title, row.subtitle, row.value]) {
                    if (/settings(_\w+)?\//.test(String(text))) missingTexts.add(area.id + "/" + pageId + "/" + row.id + ": " + text);
                }
                const mark = row.type === "toggle" ? (row.on ? "[x]" : "[ ]") : row.value;
                console.log("    " + (row.disabled ? "~ " : "- ") + row.title + (mark ? " = " + mark : "") +
                            (row.subtitle ? "  (" + row.subtitle + ")" : "") + "  <" + row.type + ">");
                // A StatusCard and a block of notes: what they hold, with the texts checked too.
                if (row.type === "statusCard") {
                    const c = row.card;
                    for (const text of [c.title, c.text, c.progressText, c.progressValue]
                        .concat((c.buttons || []).map((b) => b.label))) {
                        if (/settings(_\w+)?\//.test(String(text))) missingTexts.add(area.id + "/" + row.id + ": " + text);
                    }
                    console.log("        [" + c.icon + "] " + c.title + " | " + (c.text || "") +
                                (c.progress >= 0 ? " | " + c.progressText + " " + c.progressValue : "") +
                                " | " + (c.buttons || []).map((b) => (b.disabled ? "~" : "") + b.label).join(" / "));
                }
                if (row.type === "notes") {
                    console.log("        " + row.notes.map((n) => "• " + n.title).join("  "));
                }
                if (row.type === "choice") {
                    try {
                        const choice = engine.resolveChoice(store, i18n, area.id, row.row);
                        for (const option of choice.rows) {
                            if (/settings(_\w+)?\//.test(option.title)) missingTexts.add(area.id + "/" + row.id + " option: " + option.title);
                        }
                        console.log("        " + choice.rows.map((option) => (option.selected ? "*" : "") + option.title).join(" | "));
                    } catch (error) {
                        errors.push(area.id + "/" + pageId + "/" + row.id + ": " + error.message);
                    }
                }
            }
        }
    }
    try {
        const index = engine.searchIndex(store, i18n);
        console.log("\nsearch index: " + index.length + " entries; 'schlaf' -> " +
                    engine.search(index, "schlaf", 5).map((entry) => entry.title).join(", "));
    } catch (error) {
        errors.push("search: " + error.message);
    }
    console.log("\n" + pages + " pages, " + rows + " visible rows");
    console.log("empty pages: " + (empty.join(", ") || "none"));
    console.log("missing texts: " + ([...missingTexts].join(", ") || "none"));
    console.log("errors: " + (errors.join("\n  ") || "none"));
    if (errors.length > 0) process.exitCode = 1;
}

main();
