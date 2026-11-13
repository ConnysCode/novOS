.pragma library

// Area 11, System. From LG's System › Sprache, Standort, Zeit & Timer and Support ›
// Software-Update, Speicheroptimierung, Zuhause-/Demo-Modus. Timers live under Energie & Timer.
//
// Software-Update is LG's firmware; novOS updates itself under Über novOS. An LG update can
// cost the root access and with it novOS, so the page starts with the Homebrew Channel's
// block that the setup offers ("LG-Systemupdates sperren", see SettingsData). While it is
// off, the page searches, installs and cancels as LG's Support › Software-Update does and
// switches LG's automatic updates; installing and switching them on ask first. An update
// that runs or waits shows in any case.

function zoneName(ctx) {
    var zone = ctx.val("time.timeZone");
    if (!zone || typeof zone !== "object") return "";
    return zone.City ? zone.City + (zone.Country ? ", " + zone.Country : "") : (zone.ZoneID || "");
}

// ---- LG's software update ------------------------------------------------------------

function blocked(ctx) {
    return ctx.state.blockUpdates === true;
}

function allowed(ctx) {
    return ctx.state.blockUpdates === false;
}

// The flag is off, but LG's servers stay pointed to the TV until the next restart.
function stillBlocked(ctx) {
    return allowed(ctx) && ctx.state.blockedNow === true;
}

function lgStatus(ctx) {
    return (ctx.state.lgStatus || {}).status || "";
}

function lgRunning(ctx) {
    var status = lgStatus(ctx);
    return status === "in progress" || status === "ExternalChipInstall" || status === "pending";
}

// States without a button in LG's page: the update is done, booked or paused.
function lgWaiting(ctx) {
    var status = lgStatus(ctx);
    return status === "completed" || status === "schedule detected" || status === "warm reserved" ||
           status === "paused";
}

function lgChecking(ctx) {
    return ctx.state.lgChecking === true || lgStatus(ctx) === "check update";
}

// LG's version number as LG shows it: 0x33317501 is "33.31.75".
function lgVersion(value) {
    if (typeof value !== "number") return String(value || "");
    var hex = "00000000" + value.toString(16);
    var text = "";
    for (var at = hex.length - 3, part = 5; part >= 0; at--, part--) {
        text = hex[at] + text;
        if (part === 2 || part === 4) text = "." + text;
    }
    return text;
}

// The update LG found: by this search, or by an earlier one LG remembers. checkUpdate
// answers {"returnValue": true, "flagUpdate": false, "version": 0} when there is none.
function lgOffer(ctx) {
    var status = lgStatus(ctx);
    if (status === "canceled" || status === "failed" || lgRunning(ctx) || lgWaiting(ctx)) return null;
    var found = ctx.state.lgCheck;
    if (found && found.returnValue === true && (found.flagUpdate === true || found.version)) {
        return { version: lgVersion(found.version) };
    }
    var seen = ctx.state.lgVersionChecked;
    if (seen && seen.flagUpdate === true) return { version: lgVersion(seen.version) };
    return null;
}

function lgCheckText(ctx) {
    if (lgChecking(ctx)) return "";
    var status = lgStatus(ctx);
    if (status === "failed") return ctx.t("detail.lg_failed");
    if (status === "canceled") return ctx.t("detail.lg_canceled");
    var found = ctx.state.lgCheck;
    if (found) {
        if (found.returnValue !== true) return ctx.t("detail.lg_none_offline");
        if (lgOffer(ctx) === null) return ctx.t("detail.lg_none");
    }
    return ctx.t("detail.lg_check");
}

function lgRunningText(ctx) {
    var status = lgStatus(ctx);
    if (status === "pending") return ctx.t("detail.lg_paused");
    if (status === "ExternalChipInstall") return ctx.t("detail.lg_installing");
    return ctx.t("detail.lg_running");
}

function lgWaitingText(ctx) {
    var status = lgStatus(ctx);
    if (status === "completed") return ctx.t("detail.lg_completed");
    if (status === "schedule detected") return ctx.t("detail.lg_reserved");
    return ctx.t("detail.lg_paused");
}

function blockText(ctx) {
    if (ctx.state.blockError) return ctx.t("detail.block_failed");
    if (ctx.state.blockBusy) return ctx.t("detail.block_saving");
    if (blocked(ctx) && ctx.state.blockedNow !== true) return ctx.t("detail.block_after_restart");
    if (stillBlocked(ctx)) return ctx.t("detail.unblock_after_restart");
    return ctx.t(blocked(ctx) ? "detail.block_on" : "detail.block_off");
}

var updateBusy = [{ when: function (ctx) { return ctx.state.blockBusy === true; }, reason: "detail.block_saving" },
                  { when: function (ctx) { return ctx.state.updateBusy === true; }, reason: "reason.update_running" }];
var afterRestart = [{ when: stillBlocked, reason: "reason.after_restart" }];

var area = {
    id: "system",
    icon: "system",
    title: "area.system",
    keys: ["time.timeZone", "support.automaticUpdate"],
    page: {
        id: "system",
        title: "area.system",
        sections: [
            {
                rows: [
                    { id: "language", type: "page", page: "language",
                      title: "row.language_region",
                      subtitle: function (ctx) { return ctx.state.menuLanguage || ""; },
                      search: "search.language_region" },
                    { id: "dateTime", type: "page", page: "dateTime",
                      title: "row.date_time", summary: ["time.autoClock"], search: "search.date_time" },
                    { id: "voice", type: "page", page: "voice",
                      title: "row.voice", subtitle: "detail.voice", search: "search.voice",
                      requires: function (ctx) { return ctx.state.voiceAvailable === true; } }
                ]
            },
            {
                title: "section.software",
                rows: [
                    { id: "update", type: "page", page: "update",
                      title: "row.software_update",
                      subtitle: function (ctx) { return ctx.state.firmware || ""; },
                      value: function (ctx) {
                          if (lgRunning(ctx)) return ctx.t("value.lg_updating");
                          return allowed(ctx) && lgOffer(ctx) ? ctx.t("value.lg_available") : "";
                      },
                      search: "search.software_update" },
                    { id: "storage", type: "page", page: "storage",
                      title: "row.storage", search: "search.storage",
                      subtitle: function (ctx) {
                          if (!(ctx.state.storageTotal > 0)) return "";
                          return ctx.t("detail.storage_free", { free: (ctx.state.storageFree / 1024).toFixed(1),
                                                               total: (ctx.state.storageTotal / 1024).toFixed(1) });
                      } }
                ]
            },
            {
                title: "section.reset",
                rows: [
                    // LG's Zuhause-/Demo-Modus is left out (decision of 11 November 2026).
                    // Destructive and not reversible: LG's own System page with the focus on
                    // its reset entry. LG asks there and explains what is deleted.
                    { id: "factoryReset", type: "lgApp",
                      app: { id: "com.palm.app.settings", params: { target: "System", item: "resetSettings" } },
                      title: "row.factory_reset", subtitle: "detail.factory_reset", search: "search.factory_reset" }
                ]
            }
        ]
    },
    pages: {
        language: {
            id: "language",
            title: "page.language_region",
            sections: [
                {
                    rows: [
                        // Host action "language": the panel's own list, writes localeInfo like
                        // LG (UI, FMT, TV, keyboards; the audio language stays).
                        { id: "menuLanguage", type: "action", action: "language",
                          title: "row.menu_language", search: "search.menu_language",
                          value: function (ctx) { return ctx.state.menuLanguage || ""; } },
                        { id: "moreLanguages", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "Language" } },
                          title: "row.more_languages", subtitle: "detail.more_languages",
                          search: "search.more_languages" }
                    ]
                },
                {
                    title: "section.region",
                    rows: [
                        // LG: Standort. Broadcast country and LG services country can reset the
                        // TV, so LG's page with its warnings stays in charge.
                        { id: "location", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "Location" } },
                          title: "row.location", search: "search.location",
                          subtitle: function (ctx) { return ctx.state.country || ""; } }
                        // The weather location is left out: novOS shows no weather.
                    ]
                }
            ]
        },
        dateTime: {
            id: "dateTime",
            title: "page.date_time",
            sections: [
                {
                    rows: [
                        // LG writes time.autoClock and also com.palm.systemservice/setPreferences
                        // {"useNetworkTime": <bool>}. Host action "autoTime" does the second.
                        { id: "autoClock", type: "toggle", key: "time.autoClock", onChange: "autoTime",
                          title: "row.auto_clock", subtitle: "detail.auto_clock", search: "search.auto_clock" },
                        { id: "timeZone", type: "info", focusable: false, title: "row.time_zone",
                          value: zoneName,
                          requires: function (ctx) { return zoneName(ctx) !== ""; } },
                        // Manual time, date, time zone and custom zone: LG's page, it knows the
                        // zone list of every country.
                        { id: "setTime", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "DateTime" } },
                          title: "row.set_time", subtitle: "detail.set_time", search: "search.set_time" }
                    ]
                }
            ]
        },
        voice: {
            id: "voice",
            title: "page.voice",
            sections: [
                {
                    rows: [
                        // LG: AI-Dienst › Einstellungen der Spracherkennung.
                        { id: "voiceSettings", type: "lgApp",
                          app: { id: "com.webos.app.aiplatformsupport",
                                 params: { activateType: "view", launchMode: "settings", caller: "com.palm.app.settings" } },
                          title: "row.voice_settings", subtitle: "detail.voice_settings",
                          search: "search.voice_settings" },
                        // LG: AI-Dienst › Hilfe für Spracherkennung.
                        { id: "voiceHelp", type: "lgApp",
                          app: { id: "com.webos.app.aiplatformsupport",
                                 params: { activateType: "view", launchMode: "guide", caller: "com.palm.app.settings" } },
                          title: "row.voice_help", search: "search.voice_help" }
                    ]
                }
            ]
        },
        update: {
            id: "update",
            title: "page.software_update",
            subtitle: "detail.software_update",
            sections: [
                {
                    rows: [
                        { id: "version", type: "info", focusable: false, title: "row.software_version",
                          value: function (ctx) { return ctx.state.firmware || ""; } },
                        { id: "webOS", type: "info", focusable: false, title: "row.webos_version",
                          value: function (ctx) { return ctx.state.webOS || ""; } }
                    ]
                },
                {
                    rows: [
                        // The setup's switch. Off asks first; both take effect with the next restart.
                        { id: "blockUpdates", type: "toggle", key: "novos.blockUpdates", action: "blockUpdates",
                          title: "row.block_updates", subtitle: blockText, search: "search.block_updates",
                          requires: function (ctx) { return ctx.state.blockUpdates !== undefined; },
                          disabled: updateBusy },
                        // An update LG started, from now or from before the block.
                        { id: "lgCancel", type: "action", action: "lgUpdateCancel", title: "row.lg_cancel",
                          subtitle: lgRunningText,
                          value: function (ctx) {
                              var progress = ctx.state.lgProgress;
                              return lgStatus(ctx) === "in progress" && typeof progress === "number" ?
                                     ctx.t("value.percent", { percent: progress }) : "";
                          },
                          requires: lgRunning },
                        { id: "lgWaiting", type: "info", focusable: false, title: "row.lg_update",
                          value: lgWaitingText, requires: lgWaiting },
                        { id: "lgInstall", type: "action", action: "lgUpdateInstall", title: "row.lg_install",
                          subtitle: function (ctx) {
                              var offer = lgOffer(ctx) || {};
                              var size = (ctx.state.lgStatus || {}).size || 0;
                              return ctx.t(size ? "detail.lg_offer_size" : "detail.lg_offer",
                                           { version: offer.version, size: size });
                          },
                          requires: function (ctx) { return allowed(ctx) && lgOffer(ctx) !== null; },
                          disabled: afterRestart },
                        { id: "lgCheck", type: "action", action: "lgUpdateCheck", title: "row.lg_check",
                          subtitle: lgCheckText, search: "search.software_update",
                          value: function (ctx) { return lgChecking(ctx) ? ctx.t("value.checking") : ""; },
                          requires: function (ctx) {
                              return allowed(ctx) && !lgRunning(ctx) && lgStatus(ctx) !== "completed" &&
                                     (ctx.state.lgStatus || {}).platformUpgrade !== true;
                          },
                          disabled: afterRestart },
                        // LG's switch; on asks first and, without LG's general terms, opens them.
                        { id: "autoUpdateSwitch", type: "toggle", key: "support.automaticUpdate",
                          action: "lgAutoUpdate", title: "row.auto_update", subtitle: "detail.auto_update",
                          search: "search.auto_update", requires: allowed },
                        // While blocked it does nothing, so it is only shown.
                        { id: "autoUpdate", type: "info", focusable: false, title: "row.auto_update",
                          value: function (ctx) {
                              var value = ctx.val("support.automaticUpdate");
                              return value === undefined ? "" : ctx.label("support.automaticUpdate", value);
                          },
                          requires: function (ctx) { return !allowed(ctx) && ctx.has("support.automaticUpdate"); } }
                    ]
                }
            ]
        },
        storage: {
            id: "storage",
            title: "page.storage",
            sections: [
                {
                    rows: [
                        // luna://com.webos.service.attachedstoragemanager/getProperties
                        // {"deviceId": "INTERNAL_STORAGE"}, totalSpace and freeSpace in MB.
                        { id: "free", type: "info", focusable: false, title: "row.storage_free",
                          value: function (ctx) {
                              if (!(ctx.state.storageTotal > 0)) return "";
                              return ctx.t("detail.storage_free", { free: (ctx.state.storageFree / 1024).toFixed(1),
                                                                   total: (ctx.state.storageTotal / 1024).toFixed(1) });
                          } },
                        { id: "optimize", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "MemoryOptimizer" } },
                          title: "row.memory_optimizer", subtitle: "detail.memory_optimizer",
                          search: "search.memory_optimizer" }
                    ]
                }
            ]
        }
    }
};
