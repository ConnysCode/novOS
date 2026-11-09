.pragma library

// Über novOS › novOS-Update (page "novOS-Update" of the design, K3-NovUpdate-1 … 8): a
// StatusCard with the state (current, searching, available or ready, loading, installing,
// no connection), the release notes of the version it is about, the settings (automatic
// updates at night, test versions) and, for 14 days after an update, the way back to the
// version before it with the user data it had (docs/setup-update-plan.md, "Zurück zur
// vorigen Version").
//
// SettingsData talks to the updater (novos-setupd behind novOS' supervisor, see
// docs/setup-update-plan.md) and puts what it answers into ctx.state, already in the TV's
// language: novosVersion, updateCheck (the last answer of the channel), updateBusy and
// updateCommand, updateStage, updatePercent, updateBytes, updateTotal, updateEta,
// updateError(Kind), updateChecked, updateTonight, notesInstalled and notesAvailable
// ({ date, items }), rollbackVersion and rollbackUntil, rollbackSince (dates in the TV's
// language; empty: no way back).

function check(ctx) {
    return ctx.state.updateCheck || null;
}

// A release newer than the one running that this TV can take.
function offered(ctx) {
    var found = check(ctx);
    return !!found && found.newer === true && (found.problems || []).length === 0 &&
           found.available !== ctx.state.novosVersion;
}

function ready(ctx) {
    return offered(ctx) && check(ctx).downloaded === true;
}

function running(ctx, command) {
    return ctx.state.updateBusy === true && (!command || ctx.state.updateCommand === command);
}

function installing(ctx) {
    return running(ctx, "update") || running(ctx, "rollback");
}

function megabytes(bytes) {
    return bytes > 0 ? Math.max(1, Math.round(bytes / 1000000)) : 0;
}

function timeLeft(ctx, seconds) {
    if (seconds === null || seconds === undefined) return "";
    if (seconds < 45) return ctx.t("card.time_seconds");
    var minutes = Math.round(seconds / 60);
    return minutes <= 1 ? ctx.t("card.time_minute") : ctx.t("card.time_minutes", { minutes: minutes });
}

// The card on top of the page, one state at a time.
function card(ctx) {
    var found = check(ctx) || {};
    var installed = ctx.state.novosVersion || "";
    var available = found.available || "";
    if (running(ctx, "download")) {
        var total = ctx.state.updateTotal || found.size || 0;
        var done = ctx.state.updateBytes || 0;
        var left = timeLeft(ctx, ctx.state.updateEta);
        var share = total > 0 ? done / total : 0;
        return { icon: "download", title: ctx.t("card.loading", { version: available }),
                 text: ctx.t("card.loading_text"), progress: share,
                 progressText: ctx.t("card.loaded_of", { done: Math.round(done / 1000000), total: megabytes(total) }) +
                               (left ? " · " + left : ""),
                 progressValue: ctx.t("value.percent", { percent: Math.round(share * 100) }),
                 buttons: [{ label: ctx.t("button.cancel"), action: "cancelUpdate", focus: true }] };
    }
    if (installing(ctx)) {
        var target = ctx.state.updateTarget || available;
        return { icon: "download", title: ctx.t("card.installing", { version: target }),
                 text: ctx.t("card.installing_text"), progress: (ctx.state.updatePercent || 0) / 100,
                 progressText: "", progressValue: ctx.t("value.percent", { percent: ctx.state.updatePercent || 0 }),
                 buttons: [] };
    }
    if (running(ctx, "check") || running(ctx, "channel")) {
        return { icon: "spinner", title: ctx.t("card.checking"), text: ctx.t("card.installed_is", { version: installed }),
                 buttons: [{ label: ctx.t("button.checking"), disabled: true }] };
    }
    if (ctx.state.updateError) {
        var offline = ctx.state.updateErrorKind === "offline";
        var buttons = [{ label: ctx.t("button.retry"), action: "checkUpdates", focus: true }];
        if (offline) buttons.push({ label: ctx.t("button.network"), action: "openNetwork" });
        return { icon: "alert", title: ctx.t(offline ? "card.offline" : "card.failed"),
                 text: ctx.t(offline ? "card.offline_text" : "card.installed_is", { version: installed }),
                 buttons: buttons };
    }
    if (offered(ctx)) {
        var planned = ctx.state.updateTonight === available;
        return { icon: "download", title: ctx.t(ready(ctx) ? "card.ready" : "card.available", { version: available }),
                 text: ctx.t("card.offer_text", { size: megabytes(found.size) }),
                 buttons: [{ label: ctx.t("button.install_now"), action: "installUpdate", focus: true },
                           { label: ctx.t(planned ? "button.tonight_planned" : "button.tonight"),
                             action: "tonightUpdate", params: { version: planned ? "" : available } }] };
    }
    if (found.newer && (found.problems || []).length > 0) {
        return { icon: "alert", title: ctx.t("card.not_for_tv", { version: available }),
                 text: ctx.t("card.installed_is", { version: installed }),
                 buttons: [{ label: ctx.t("button.check"), action: "checkUpdates", focus: true }] };
    }
    return { icon: "check", title: ctx.t("card.up_to_date", { version: installed }),
             text: ctx.state.updateChecked ? ctx.t("card.last_check", { when: ctx.state.updateChecked }) :
                                              ctx.t("card.never"),
             buttons: [{ label: ctx.t("button.check"), action: "checkUpdates", focus: true }] };
}

// The notes of the version the card is about: the offered one, else the installed one.
function notesFor(ctx) {
    if (offered(ctx) && !running(ctx, "rollback") && ctx.state.notesAvailable) {
        return { version: check(ctx).available, notes: ctx.state.notesAvailable };
    }
    return { version: ctx.state.novosVersion || "", notes: ctx.state.notesInstalled || null };
}

function hasNotes(ctx) {
    var found = notesFor(ctx);
    return !!found.notes && (found.notes.items || []).length > 0;
}

// Über novOS: the line of the update row and the head block.
function rowSubtitle(ctx) {
    var found = check(ctx) || {};
    if (running(ctx, "download")) return ctx.t("card.loading", { version: found.available || "" });
    if (installing(ctx)) return ctx.t("card.installing", { version: ctx.state.updateTarget || found.available || "" });
    if (offered(ctx)) return ctx.t(ready(ctx) ? "detail.update_ready_to_install" : "card.available",
                                   { version: found.available });
    return "";
}

function rowValue(ctx) {
    if (offered(ctx)) return ctx.t("value.version_available", { version: check(ctx).available });
    return check(ctx) ? ctx.t("value.up_to_date") : "";
}

function heroTitle(ctx) {
    var version = ctx.state.novosVersion ? ctx.t("detail.version", { version: ctx.state.novosVersion }) : "";
    if (version && offered(ctx)) return ctx.t("detail.version_with_update", { version: ctx.state.novosVersion,
                                                                             available: check(ctx).available });
    return version;
}

// ---- Zurück zur vorigen Version ----------------------------------------------------

function canGoBack(ctx) {
    return !!ctx.state.rollbackVersion && !installing(ctx) && !running(ctx, "download");
}

var pages = {
    update: {
        id: "update",
        title: "row.software_update",
        sections: [
            {
                rows: [
                    { id: "status", type: "statusCard", title: "row.software_update", card: card }
                ]
            },
            {
                heading: function (ctx) {
                    var found = notesFor(ctx);
                    return { title: ctx.t("heading.new_in", { version: found.version }),
                             aside: found.notes ? found.notes.date || "" : "" };
                },
                rows: [
                    { id: "notes", type: "notes", title: "heading.notes", requires: hasNotes,
                      notes: function (ctx) { return notesFor(ctx).notes.items; } }
                ]
            },
            {
                heading: "heading.settings",
                rows: [
                    { id: "autoUpdate", type: "toggle", key: "novos.autoUpdate", on: true, off: false,
                      title: "row.auto_update", subtitle: "detail.auto_update", search: "search.auto_update",
                      disabled: [{ when: function (ctx) { return installing(ctx); }, reason: "reason.update_running" }] },
                    { id: "betaChannel", type: "toggle", key: "novos.betaChannel", on: true, off: false,
                      title: "row.test_versions", subtitle: "detail.test_versions", search: "search.update_channel",
                      disabled: [{ when: function (ctx) { return installing(ctx) || running(ctx, "download"); },
                                   reason: "reason.update_running" }] },
                    // In place of a list of every version: only the way back, while it lasts.
                    { id: "rollback", type: "action", action: "rollbackVersion", requires: canGoBack,
                      title: function (ctx) { return ctx.t("row.rollback", { version: ctx.state.rollbackVersion }); },
                      subtitle: function (ctx) { return ctx.t("detail.rollback", { date: ctx.state.rollbackUntil }); },
                      search: "search.rollback",
                      paramsOf: function (ctx) { return { version: ctx.state.rollbackVersion }; },
                      confirm: { title: "confirm.rollback_title", text: "confirm.rollback_text",
                                 confirm: "confirm.rollback_button",
                                 params: function (ctx) {
                                     return { version: ctx.state.rollbackVersion, date: ctx.state.rollbackSince };
                                 } } }
                ]
            }
        ]
    }
};
