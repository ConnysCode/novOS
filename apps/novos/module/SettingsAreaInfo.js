.pragma library

// Area 12, Über novOS (K3-Struktur-UeberNovOS). Replaces LG's Support and TV information:
// on top the word mark with novOS's version and the TV it runs on, then Software, Dieser
// Fernseher, Hilfe and Rechtliches. Device values come from the host, which reads them as
// LG does; serial number, ESN and Widevine ID are only shown, never stored or logged.
// LG's own firmware update stays under System.
//
// Software › Software-Update checks the channel, installs and switches between Stable and
// Beta. SettingsData talks to the updater: novOS' supervisor starts the newest signed setup
// release for each command (install/tv/novos-updater.py), see docs/setup-update-plan.md.
// Left out until novOS has them: release notes, installing at night and a project page.

function storage(ctx) {
    if (!(ctx.state.storageTotal > 0)) return "";
    return ctx.t("detail.storage_value", { free: (ctx.state.storageFree / 1024).toFixed(1),
                                          total: (ctx.state.storageTotal / 1024).toFixed(1) });
}

function shown(value) {
    return function (ctx) { return ctx.state[value] || ""; };
}

function known(value) {
    return function (ctx) { return !!ctx.state[value]; };
}

// ---- Software-Update -------------------------------------------------------------------

function check(ctx) {
    return ctx.state.updateCheck || null;
}

// A release newer than the one running that this TV can take.
function offered(ctx) {
    var found = check(ctx);
    return !!found && found.newer === true && (found.problems || []).length === 0 &&
           found.available !== ctx.state.novosVersion;
}

function running(ctx, command) {
    return ctx.state.updateBusy === true && (!command || ctx.state.updateCommand === command);
}

function sizeOf(found) {
    return found && found.size > 0 ? Math.max(1, Math.round(found.size / 1000000)) : 0;
}

// The line below the version on the update page: what novOS knows right now.
function updateStatus(ctx) {
    var found = check(ctx);
    if (running(ctx, "update")) {
        var version = found && found.available || "";
        if (ctx.state.updateStage === "download") {
            return ctx.t("detail.update_loading", { version: version, percent: ctx.state.updatePercent || 0 });
        }
        return ctx.t("detail.update_installing", { version: version });
    }
    if (running(ctx, "check") || running(ctx, "channel")) return ctx.t("detail.update_checking");
    if (ctx.state.updateError) {
        var kind = ctx.state.updateErrorKind;
        if (kind === "offline") return ctx.t("detail.update_offline");
        if (kind === "missing") return ctx.t("detail.update_missing");
        return ctx.t("detail.update_failed");
    }
    if (!found) return ctx.t("detail.update_never");
    if (offered(ctx)) return ctx.t("detail.update_ready", { version: found.available });
    if (found.newer && (found.problems || []).length > 0) {
        return ctx.t("detail.update_not_for_tv", { version: found.available });
    }
    return ctx.t("detail.up_to_date");
}

function modelLine(ctx) {
    return ctx.state.modelName ? "LG " + ctx.state.modelName : "";
}

// The tvName as LG keeps it carries "[LG] " in front.
function tvName(ctx) {
    return String(ctx.state.tvName || "").replace(/^\[LG\]\s*/, "");
}

var area = {
    id: "info",
    icon: "info",
    title: "area.info",
    keys: ["picture.pictureTest", "sound.soundTest"],
    page: {
        id: "info",
        title: "area.info",
        // Head block: "novOS", version, and what it runs on.
        hero: function (ctx) {
            var version = ctx.state.novosVersion ? ctx.t("detail.version", { version: ctx.state.novosVersion }) : "";
            var parts = [];
            if (ctx.state.webOS) parts.push(ctx.t("detail.webos", { version: ctx.state.webOS }));
            if (modelLine(ctx)) parts.push(modelLine(ctx));
            return { title: version, text: parts.length > 0 ? ctx.t("detail.runs_on", { what: parts.join(" · ") }) : "" };
        },
        note: "note.independent",
        sections: [
            {
                title: "section.software",
                rows: [
                    { id: "built", type: "info", focusable: false, title: "row.built",
                      value: shown("novosBuilt"), requires: known("novosBuilt") },
                    { id: "softwareUpdate", type: "page", page: "update", title: "row.software_update",
                      search: "search.software_update",
                      value: function (ctx) {
                          if (running(ctx, "update")) return ctx.t("value.updating");
                          return offered(ctx) ? ctx.t("value.update_available") : "";
                      } }
                ]
            },
            {
                title: "section.this_tv",
                rows: [
                    { id: "model", type: "info", focusable: false, title: "row.model",
                      value: modelLine, requires: known("modelName") },
                    // Same flow as Netzwerk › TV-Name: network.deviceName with "[LG] ".
                    { id: "tvName", type: "action", action: "tvName", title: "row.name", value: tvName,
                      search: "search.tv_name" },
                    { id: "details", type: "page", page: "details", title: "row.all_details",
                      subtitle: "detail.all_details", search: "search.about_tv" }
                ]
            },
            {
                title: "section.help",
                rows: [
                    // LG: Support › Bildschirm-Selbstdiagnose.
                    { id: "pictureTest", type: "lgApp",
                      app: { id: "com.webos.app.customersupport", params: { target: "pictureTest" } },
                      title: "row.picture_test", subtitle: "detail.picture_test", search: "search.picture_test",
                      requires: function (ctx) { return ctx.has("picture.pictureTest"); },
                      disabled: [{ when: function (ctx) { return ctx.desc("picture.pictureTest").ui.active === false; },
                                   reason: "reason.not_available_now" }] },
                    // LG: Support › Ton-Selbstdiagnose.
                    { id: "soundTest", type: "lgApp",
                      app: { id: "com.webos.app.customersupport", params: { target: "soundTest" } },
                      title: "row.sound_test", subtitle: "detail.sound_test", search: "search.sound_test",
                      requires: function (ctx) { return ctx.has("sound.soundTest"); },
                      disabled: [{ when: function (ctx) { return ctx.desc("sound.soundTest").ui.active === false; },
                                   reason: "reason.not_available_now" }] },
                    { id: "userGuide", type: "lgApp",
                      app: { id: "com.webos.app.tvuserguide", params: {} },
                      title: "row.user_guide", search: "search.user_guide" }
                ]
            },
            {
                title: "section.legal",
                rows: [
                    // The launcher's pictures come from Wikimedia Commons, each with its credit line.
                    { id: "imageCredits", type: "info", focusable: false, title: "row.image_credits",
                      value: function (ctx) { return ctx.t("detail.image_credits_value"); } },
                    { id: "openSource", type: "lgApp",
                      app: { id: "com.palm.app.settings", params: { target: "PolicyNotice", item: "openSourceLicenses" } },
                      title: "row.open_source", subtitle: "detail.open_source", search: "search.open_source" },
                    { id: "legalNotice", type: "lgApp",
                      app: { id: "com.palm.app.settings", params: { target: "LegalNotice" } },
                      title: "row.legal_notice", search: "search.legal_notice" }
                ]
            }
        ]
    },
    pages: {
        update: {
            id: "update",
            title: "row.software_update",
            hero: function (ctx) {
                var version = ctx.state.novosVersion ? ctx.t("detail.version", { version: ctx.state.novosVersion }) : "";
                return { title: version, text: updateStatus(ctx) };
            },
            note: "note.update_restart",
            sections: [
                {
                    rows: [
                        { id: "installUpdate", type: "action", action: "installUpdate", title: "row.install_update",
                          subtitle: function (ctx) {
                              var found = check(ctx) || {};
                              var channel = ctx.label("novos.updateChannel", found.channel || ctx.state.updateChannel);
                              var size = sizeOf(found);
                              return ctx.t(size ? "detail.update_offer_size" : "detail.update_offer",
                                           { version: found.available, channel: channel, size: size });
                          },
                          value: function (ctx) {
                              return running(ctx, "update") ? ctx.t("value.percent", { percent: ctx.state.updatePercent || 0 }) : "";
                          },
                          // Pressed again while it runs, it does nothing (SettingsData).
                          requires: function (ctx) { return offered(ctx) || running(ctx, "update"); } },
                        { id: "checkUpdates", type: "action", action: "checkUpdates", title: "row.check_updates",
                          search: "search.software_update",
                          subtitle: function (ctx) {
                              return ctx.state.updateChecked ? ctx.t("detail.last_check", { when: ctx.state.updateChecked }) : "";
                          },
                          value: function (ctx) {
                              return running(ctx, "check") || running(ctx, "channel") ? ctx.t("value.checking") : "";
                          },
                          disabled: [{ when: function (ctx) { return running(ctx, "update"); },
                                       reason: "reason.update_running" }] },
                        { id: "updateChannel", type: "choice", key: "novos.updateChannel", values: ["stable", "beta"],
                          title: "row.update_channel", subtitle: "detail.update_channel", search: "search.update_channel",
                          disabled: [{ when: function (ctx) { return running(ctx, "update"); },
                                       reason: "reason.update_running" }] }
                    ]
                }
            ]
        },
        details: {
            id: "details",
            title: "row.all_details",
            sections: [
                {
                    rows: [
                        { id: "model", type: "info", title: "row.model",
                          value: modelLine, requires: known("modelName") },
                        // luna://com.palm.systemservice/deviceInfo/query
                        // {"parameters": ["product_id", "serial_number"]}
                        { id: "modelCode", type: "info", title: "row.model_code",
                          value: shown("modelCode"), requires: known("modelCode") },
                        { id: "serial", type: "info", title: "row.serial_number",
                          value: shown("serialNumber"), requires: known("serialNumber") }
                    ]
                },
                {
                    title: "section.software",
                    rows: [
                        // luna://com.palm.systemservice/osInfo/query {"parameters": ["core_os_release"]}
                        { id: "webOS", type: "info", title: "row.webos_version",
                          value: shown("webOS"), requires: known("webOS") },
                        { id: "firmware", type: "info", title: "row.firmware",
                          value: shown("firmware"), requires: known("firmware") },
                        { id: "storage", type: "info", title: "row.storage",
                          value: storage, requires: function (ctx) { return ctx.state.storageTotal > 0; } }
                    ]
                },
                {
                    title: "section.network",
                    rows: [
                        // luna://com.webos.service.connectionmanager/getinfo {}
                        { id: "wiredMac", type: "info", title: "row.mac_wired",
                          value: shown("wiredMac"), requires: known("wiredMac") },
                        { id: "wifiMac", type: "info", title: "row.mac_wifi",
                          value: shown("wifiMac"), requires: known("wifiMac") }
                    ]
                },
                {
                    // luna://com.webos.service.sm/crypto/checkSeStore {"id": ["esn", "widevine"]}, as LG.
                    title: "section.drm",
                    rows: [
                        { id: "esn", type: "info", title: "row.esn",
                          value: shown("esn"), requires: known("esn") },
                        { id: "widevine", type: "info", title: "row.widevine",
                          value: shown("widevine"), requires: known("widevine") }
                    ]
                }
            ]
        }
    }
};
