.pragma library
.import "SettingsUpdate.js" as Update

// Area 12, Über novOS (K3-Struktur-UeberNovOS). Replaces LG's Support and TV information:
// on top the word mark with novOS's version and the TV it runs on, then Software, Dieser
// Fernseher, Hilfe and Rechtliches. Device values come from the host, which reads them as
// LG does; serial number, ESN and Widevine ID are only shown, never stored or logged.
// LG's own firmware update stays under System.
//
// Software › novOS-Update is the design's page "novOS-Update" (SettingsUpdate.js): state,
// release notes, automatic updates, test versions and the way back after an update.
// Projektseite opens novOS' repository in LG's browser.

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
            var version = Update.heroTitle(ctx);
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
                      search: "search.software_update", subtitle: Update.rowSubtitle, value: Update.rowValue },
                    { id: "projectPage", type: "lgApp", title: "row.project_page", search: "search.project_page",
                      value: function (ctx) { return ctx.t("value.project_page"); },
                      app: { id: "com.webos.app.browser", params: { target: "https://github.com/ConnysCode/novOS" } } }
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
        update: Update.pages.update,
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
