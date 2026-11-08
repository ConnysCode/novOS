.pragma library

// Area 06 "Oberfläche" of the settings modal. LG's part comes from "System ›
// Zusätzliche Einstellungen" (Home settings, screen saver, pointer options); the
// novOS part are values novOS keeps itself in GlassStyle.qml (category "novos").
// Rows for novOS parts without a stored value (backgrounds per source, quick panel
// entries) are left out until those values exist.

function audioGuidanceOn(ctx) {
    return ctx.val("option.audioGuidance") === "on";
}

function hasProfile(ctx, name) {
    var list = ctx.cfg("profile.list");
    return !!list && list.indexOf(name) >= 0;
}

// LG's "Power On Screen": one list over two keys. "Home" sets homeAutoLaunch, an
// input sets selectedInputApp, "Recent Input" clears both. checkHomeAutoLaunchValue
// tells LG that the user chose.
function powerOnOptions(ctx) {
    var home = ctx.val("general.homeAutoLaunch") === "on";
    var input = ctx.val("general.selectedInputApp") || "off";
    var options = [
        { id: "home", label: ctx.t("value.power_on_screen.launcher"), selected: home,
          write: { category: "general", settings: { homeAutoLaunch: "on", selectedInputApp: "off",
                                                    checkHomeAutoLaunchValue: "user" } } },
        { id: "recent", label: ctx.t("value.power_on_screen.recent"), selected: !home && input === "off",
          write: { category: "general", settings: { homeAutoLaunch: "off", selectedInputApp: "off",
                                                    checkHomeAutoLaunchValue: "user" } } }
    ];
    var desc = ctx.desc("general.selectedInputApp");
    var values = desc && desc.values && desc.values.arrayExt ? desc.values.arrayExt : [];
    for (var i = 0; i < values.length; i++) {
        var value = values[i].value;
        if (value === "off" || values[i].visible === false) continue;
        options.push({ id: value, label: ctx.t("value.power_on_screen.input", { port: value.replace("_", " ") }),
                       selected: !home && input === value,
                       write: { category: "general", settings: { homeAutoLaunch: "off", selectedInputApp: value,
                                                                 checkHomeAutoLaunchValue: "user" } } });
    }
    return options;
}

var area = {
    id: "interface",
    icon: "interface",
    title: "area.interface",
    configs: ["profile.list"],
    reads: ["option.audioGuidance", "general.selectedInputApp"],
    page: {
        id: "interface",
        title: "area.interface",
        sections: [
            {
                title: "section.home",
                rows: [
                    { id: "powerOnScreen", type: "choice", key: "general.homeAutoLaunch", options: powerOnOptions,
                      title: "row.power_on_screen", subtitle: "detail.power_on_screen", search: "search.power_on_screen",
                      // LifeStyle screens (StanbyMe and others) have their own start screen.
                      requires: function (ctx) { return !hasProfile(ctx, "lifeStyle"); } }
                ]
            },
            {
                title: "section.notice",
                rows: [
                    { id: "hideInputBanner", type: "toggle", key: "novos.hideInputBanner", on: true, off: false,
                      title: "row.hide_input_banner", subtitle: "detail.hide_input_banner", search: "search.input_banner" }
                ]
            },
            {
                title: "section.screen_saver",
                rows: [
                    // LG notes that the user changed the time, as LG's own menu does.
                    { id: "screenSaverTimer", type: "choice", key: "option.screenSaverTimer",
                      alsoWrite: { checkChangedScreenSaverTimerByUser: "user" },
                      title: "row.screen_saver_time", subtitle: "detail.screen_saver_time", search: "search.screen_saver" }
                ]
            },
            {
                title: "section.keyboard",
                rows: [
                    { id: "keyboardMode", type: "choice", key: "novos.keyboardMode", values: ["qwertz", "t9"],
                      title: "row.keyboard_mode", subtitle: "detail.keyboard_mode", search: "search.keyboard" },
                    { id: "keyboardLanguages", type: "lgApp", title: "row.keyboard_languages",
                      subtitle: "detail.keyboard_languages", search: "search.keyboard",
                      app: { id: "com.palm.app.settings",
                             params: { path: ["General", "System", "Language", "KeyboardLanguage"] } } }
                ]
            },
            {
                title: "section.remote",
                rows: [
                    { id: "pointerSpeed", type: "choice", key: "option.pointerSpeed", values: ["slow", "normal", "fast"],
                      title: "row.pointer_speed", search: "search.pointer",
                      disabled: [{ when: audioGuidanceOn, reason: "reason.audio_guidance_on" }] },
                    { id: "pointerSize", type: "choice", key: "option.pointerSize", values: ["small", "medium", "large"],
                      title: "row.pointer_size", search: "search.pointer",
                      disabled: [{ when: audioGuidanceOn, reason: "reason.audio_guidance_on" }] },
                    { id: "hints", type: "page", page: "hints", title: "row.hints",
                      summary: ["option.baloonHelp", "option.animationGuide"], search: "search.hints" }
                ]
            }
        ]
    },
    pages: {
        hints: {
            id: "hints",
            title: "page.hints",
            subtitle: "detail.hints",
            sections: [
                {
                    rows: [
                        { id: "baloonHelp", type: "toggle", key: "option.baloonHelp", title: "row.balloon_help",
                          subtitle: "detail.balloon_help" },
                        { id: "animationGuide", type: "toggle", key: "option.animationGuide", title: "row.animation_guide",
                          subtitle: "detail.animation_guide" }
                    ]
                }
            ]
        }
    }
};
