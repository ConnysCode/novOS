.pragma library

// Area 11, System. From LG's System › Sprache, Standort, Zeit & Timer and Support ›
// Software-Update, Speicheroptimierung, Zuhause-/Demo-Modus. Timers live under Energie & Timer.
// Software updates are only shown: an update can cost the root access, so novOS neither
// searches for one nor switches automatic updates.

function zoneName(ctx) {
    var zone = ctx.val("time.timeZone");
    if (!zone || typeof zone !== "object") return "";
    return zone.City ? zone.City + (zone.Country ? ", " + zone.Country : "") : (zone.ZoneID || "");
}

var area = {
    id: "system",
    icon: "system",
    title: "area.system",
    keys: ["time.timeZone", "support.automaticUpdate", "option.storeMode"],
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
                    // LG's own Zuhause-/Demo-Modus page: store mode needs LG's warning and
                    // starts LG's demo app.
                    { id: "storeMode", type: "lgApp",
                      app: { id: "com.palm.app.settings", params: { target: "HomeStoreMode" } },
                      title: "row.store_mode", search: "search.store_mode",
                      subtitle: function (ctx) {
                          var mode = ctx.val("option.storeMode");
                          return mode ? ctx.label("option.storeMode", mode) : "";
                      },
                      requires: function (ctx) { return ctx.has("option.storeMode"); } },
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
                          subtitle: function (ctx) { return ctx.state.country || ""; } },
                        { id: "weather", type: "lgApp",
                          app: { id: "com.webos.app.weatherlocation", params: {} },
                          title: "row.weather_location", search: "search.weather_location" }
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
                          value: function (ctx) { return ctx.state.webOS || ""; } },
                        // Read only. LG's switch asks for its terms first; switching it on could
                        // install an update that removes root.
                        { id: "autoUpdate", type: "info", focusable: false, title: "row.auto_update",
                          value: function (ctx) {
                              var value = ctx.val("support.automaticUpdate");
                              return value === undefined ? "" : ctx.label("support.automaticUpdate", value);
                          },
                          requires: function (ctx) { return ctx.has("support.automaticUpdate"); } }
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
