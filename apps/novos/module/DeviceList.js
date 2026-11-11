.pragma library

// The device list of the settings (TON-A, board K3-Einst-Geraeteliste and the Bausteine of
// K3-Einst-Bluetooth-Audio): one list to find, pair, connect, disconnect and remove radio
// devices, the same wherever it shows. Catalogs build their pages from these pieces:
//
//   headSection(spec)       a block without focus over the list: a hint, counters (QG-1)
//   registeredSection(spec) "Angemeldete Geräte (n)", the paired devices, each opens its page
//   availableSection(spec)  "Anschließbare Geräte (n)", found devices, the empty hint, "Suchen"
//   pairedRow / foundRow    what a row of a device shows, for a list row of one's own
//   searchRow(spec)         "Suchen", "Sucht …" while it searches, "Erneut versuchen" without service
//   deviceRows(spec)        Verbinden or Trennen and "Gerät entfernen" of a device's page; with
//                           footer: true the buttons "Trennen" and "Entfernen" of a device dialog
//   deviceSubtitle(...)     "Verbunden · Kopfhörer" under the page title
//
// The host (BluetoothDevices.qml for Bluetooth) keeps the lists in the store: entries
// { id, title, kind, state, … } with state connected, connecting, pairing, disconnecting,
// disconnected, failed or found. spec names the lists, actions and states:
//   { source: "bluetooth", found: "bluetoothFound", page: "bluetoothDevice",
//     connect: "btAudioConnect", disconnect: "btAudioDisconnect", remove: "btAudioRemove",
//     search: "btAudioSearch", searching: "btAudioSearching", ready: "btAudioReady" }
// Texts are in the shared namespace settings (module/i18n/settings/common), "device.*".
// More in spec, for TON-D/TON-E: when (the sections show only while it holds, as WOWCAST
// without Wi-Fi), searchingHint (a spinner block while it searches and found nothing),
// emptyHint ({ icon, title, text } instead of the Bluetooth one), noneMore (a line instead of
// the empty block while a device is registered), locked (more greyed-out rules for Verbinden).

var busyStates = ["connecting", "pairing", "disconnecting"];

// Row symbols (icons/row-<name>.png); the gamepad is the one of the inputs.
var icons = { headphones: "headphones", speaker: "speaker", soundbar: "soundbar",
              gamepad: "source-gamepad", keyboard: "keyboard", mouse: "mouse", wowcast: "soundbar" };

function kindIcon(kind) {
    return icons[kind] || "bluetooth";
}

// btaudiosrc names no kind of device. The name tells headphones and soundbars apart well
// enough for a symbol; everything else counts as a speaker.
function audioKind(name) {
    var text = String(name || "");
    if (/(head|kopfh|buds|pods|earphone|earbud|\bwh-|\bwf-|quietcomfort|momentum|beats|casque|auricular)/i.test(text))
        return "headphones";
    if (/(sound ?bar|\bS\d{2}[A-Z]{1,3}\b|\bSP\d|\bSN\d|\bSC\d)/i.test(text)) return "soundbar";
    return "speaker";
}

function kindText(ctx, kind) {
    return ctx.t("device.kind_" + (icons[kind] ? kind : "unknown"));
}

function isBusy(item) {
    return !!item && busyStates.indexOf(item.state) >= 0;
}

function anyBusy(ctx, spec) {
    var lists = [ctx.list(spec.source), spec.found ? ctx.list(spec.found) : []];
    for (var l = 0; l < lists.length; l++) {
        for (var i = 0; i < lists[l].length; i++) {
            if (isBusy(lists[l][i])) return true;
        }
    }
    return false;
}

function stateText(ctx, item) {
    if (!item) return "";
    if (item.state === "failed") return ctx.t("device.failed");
    if (item.state === "found") return kindText(ctx, item.kind);
    return ctx.t("device." + (busyStates.indexOf(item.state) >= 0 || item.state === "connected" ? item.state
                                                                                                 : "disconnected"));
}

function item(ctx, source, id) {
    var items = ctx.list(source);
    for (var i = 0; i < items.length; i++) {
        if (items[i].id === id) return items[i];
    }
    return null;
}

function searching(ctx, spec) {
    return ctx.state[spec.searching] === true;
}

// A paired device: symbol, name, its state below, a chevron to its page. While it connects
// or disconnects a spinner stands at the right and the row takes no OK.
// note: an own second line instead of the state, as "Aktuelle Ausgabe" (TON-B).
function pairedRow(ctx, entry, note) {
    var busy = isBusy(entry);
    var own = note ? note(ctx, entry) : "";
    return { title: entry.title, icon: kindIcon(entry.kind), subtitle: own || stateText(ctx, entry),
             busy: busy, inert: busy, tone: entry.state === "failed" ? "warning" : "" };
}

// A found device: symbol, name and its kind; OK pairs and connects it in the row. Failed it
// says so in the warning colour and offers to try again.
function foundRow(ctx, entry, spec) {
    var busy = isBusy(entry);
    var failed = entry.state === "failed";
    return { title: entry.title, icon: kindIcon(entry.kind),
             subtitle: failed || busy ? stateText(ctx, entry) : kindText(ctx, entry.kind),
             tone: failed ? "warning" : "", value: failed ? ctx.t("device.retry") : "",
             busy: busy, inert: busy || anyBusy(ctx, spec), mark: "",
             action: spec.connect, params: { id: entry.id } };
}

// The block over the list. block(ctx) gives { icon, text, counters: [{ icon, count, label }] }.
function headSection(block) {
    return { rows: [{ id: "deviceHead", type: "block", block: block }] };
}

function registeredSection(spec) {
    return {
        title: function (ctx) { return ctx.t("device.registered", { count: ctx.list(spec.source).length }); },
        rows: [
            { id: "paired", type: "list", source: spec.source, page: spec.page,
              decorate: function (ctx, entry) { return pairedRow(ctx, entry, spec.note); } },
            { id: "nonePaired", type: "info", title: "device.none_paired", focusable: false,
              requires: function (ctx) { return ctx.list(spec.source).length === 0; } }
        ]
    };
}

function unavailable(ctx, spec) {
    return ctx.state[spec.ready] === false;
}

function shows(ctx, spec) {
    return typeof spec.when !== "function" || spec.when(ctx);
}

// "Suchen" at the end of a list; spec.searchLocked: more reasons to take no OK.
function searchRow(spec) {
    return { id: "search", type: "action", action: spec.search,
             requires: function (ctx) { return shows(ctx, spec); },
             title: function (ctx) {
                 if (searching(ctx, spec)) return ctx.t("device.searching");
                 return ctx.t(unavailable(ctx, spec) ? "device.retry" : "row.search");
             },
             icon: function (ctx) { return searching(ctx, spec) ? "" : "search"; },
             iconBusy: function (ctx) { return searching(ctx, spec); },
             inert: function (ctx) {
                 return searching(ctx, spec) || anyBusy(ctx, spec) ||
                        (typeof spec.searchLocked === "function" && spec.searchLocked(ctx));
             } };
}

// The empty block: no service, nothing found, or (searchingHint) a search that runs.
function emptyHint(ctx, spec) {
    if (unavailable(ctx, spec)) {
        var gone = spec.unavailableHint || { icon: "bluetooth-off-32", title: "device.unavailable",
                                             text: "device.unavailable_hint" };
        return { icon: gone.icon, title: ctx.t(gone.title), text: ctx.t(gone.text) };
    }
    if (searching(ctx, spec)) {
        return { spinner: true, title: ctx.t("device.searching_title"), text: ctx.t("device.searching_hint") };
    }
    var own = spec.emptyHint;
    if (own) return { icon: own.icon, title: ctx.t(own.title), text: ctx.t(own.text) };
    return { icon: "bluetooth-32", title: ctx.t("device.none_found"), text: ctx.t("device.none_found_hint") };
}

// Found devices, then the empty hint, then "Suchen". While it searches the last row turns into
// "Sucht …" with a spinner and keeps the focus where it is.
function availableSection(spec) {
    function empty(ctx) {
        return ctx.list(spec.found).length === 0;
    }
    // noneMore: a device is registered, an empty list says so in a line.
    function oneLine(ctx) {
        return !!spec.noneMore && ctx.list(spec.source).length > 0 && !unavailable(ctx, spec);
    }
    return {
        title: function (ctx) { return ctx.t("device.available", { count: ctx.list(spec.found).length }); },
        rows: [
            { id: "found", type: "list", source: spec.found,
              requires: function (ctx) { return shows(ctx, spec); },
              decorate: function (ctx, entry) { return foundRow(ctx, entry, spec); } },
            { id: "foundHint", type: "hint",
              requires: function (ctx) {
                  if (!shows(ctx, spec) || oneLine(ctx)) return false;
                  return unavailable(ctx, spec) ||
                         (empty(ctx) && (!searching(ctx, spec) || spec.searchingHint === true));
              },
              hint: function (ctx) { return emptyHint(ctx, spec); } },
            { id: "noneMore", type: "info", focusable: false,
              title: function (ctx) { return ctx.t(spec.noneMore || ""); },
              requires: function (ctx) { return shows(ctx, spec) && oneLine(ctx) && empty(ctx) && !searching(ctx, spec); } },
            searchRow(spec)
        ]
    };
}

// "Verbunden · Kopfhörer" (kindFirst: "Gamepad · Verbunden", as QG-1 writes it).
function deviceSubtitle(ctx, entry, kindFirst) {
    if (!entry) return "";
    var parts = [stateText(ctx, entry), kindText(ctx, entry.kind)];
    if (isBusy(entry)) return parts[0];
    return (kindFirst ? parts.reverse() : parts).join(" · ");
}

// Verbinden or Trennen, then "Gerät entfernen"; both greyed out while the device connects or
// disconnects, both ask first (WifiSetup.openDialog, focus on "Abbrechen").
// spec.disconnectText: the second line of the question to disconnect, own per use.
function deviceRows(spec) {
    function entry(ctx) {
        return item(ctx, spec.source, ctx.param);
    }
    function names(ctx) {
        var found = entry(ctx);
        return { name: found ? found.title : "" };
    }
    var locked = [{ when: function (ctx) { return isBusy(entry(ctx)); }, reason: "reason.not_available_now" }];
    var footer = spec.footer === true;
    return [
        { id: "connect", type: "action", action: spec.connect, title: "row.connect", footer: footer,
          paramsOf: function (ctx) { return { id: ctx.param }; },
          requires: function (ctx) { var found = entry(ctx); return !!found && found.state !== "connected" &&
                                                                    found.state !== "disconnecting"; },
          disabled: locked.concat(spec.locked || []) },
        { id: "disconnect", type: "action", action: spec.disconnect, title: "row.disconnect", footer: footer,
          paramsOf: function (ctx) { return { id: ctx.param }; },
          requires: function (ctx) { var found = entry(ctx); return !!found && (found.state === "connected" ||
                                                                               found.state === "disconnecting"); },
          disabled: locked,
          confirm: { title: "confirm.disconnect_title", text: spec.disconnectText || "confirm.disconnect_text",
                     confirm: "confirm.disconnect_button", danger: false, params: names } },
        { id: "remove", type: "action", action: spec.remove, title: footer ? "row.remove" : "row.remove_device",
          danger: true, footer: footer,
          paramsOf: function (ctx) { return { id: ctx.param }; },
          requires: function (ctx) { return !!entry(ctx); },
          disabled: locked,
          confirm: { title: "confirm.remove_title", text: spec.removeText || "confirm.remove_text",
                     confirm: "confirm.remove_button", danger: true, params: names } }
    ];
}
