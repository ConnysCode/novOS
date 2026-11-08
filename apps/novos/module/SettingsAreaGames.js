.pragma library

// Area 04 "Spiele": LG's Game Optimizer app (com.webos.app.gameoptimizer) rebuilt natively.
// Keys and conditions follow its bundle and docs/lg-settings/schnellmenue-und-apps.md,
// section 2.4. The values follow the running input (dimension gameInput, for the picture
// values also dynamicRange and gameGenre).
//
// LG's rule for almost every row (Lb() in its bundle): the Game Optimizer must be on for
// the running HDMI input, other.gameMode[gameInput] === "on".

// The running input as LG names it in other.gameMode: "hdmi1" … "hdmi4".
function input(ctx) {
    if (ctx.state.input) return ctx.state.input;
    var match = /^com\.webos\.app\.hdmi(\d+)$/.exec(ctx.state.foreground || "");
    return match ? "hdmi" + match[1] : "";
}

function inputOfPort(ctx, port) {
    var items = ctx.list("inputs");
    for (var i = 0; i < items.length; i++) {
        if (items[i].port === port) return items[i];
    }
    return null;
}

// One switch per HDMI input for the page "inputs". Only inputs the TV lists appear.
function inputRow(port) {
    return { id: "hdmi" + port, type: "toggle", key: "other.gameMode", title: "row.hdmi_" + port,
             member: function () { return "hdmi" + port; },
             subtitle: function (ctx) {
                 var item = inputOfPort(ctx, port);
                 return item && item.title !== ctx.t("row.hdmi_" + port) ? item.title : "";
             },
             requires: function (ctx) { return inputOfPort(ctx, port) !== null; } };
}

function onHdmi(ctx) {
    return input(ctx).indexOf("hdmi") === 0;
}

function optimizerOn(ctx) {
    var modes = ctx.val("other.gameMode");
    return onHdmi(ctx) && modes !== undefined && modes !== null && modes[input(ctx)] === "on";
}

// The two reasons every Game Optimizer row shares, in this order.
var needsOptimizer = [
    { when: function (ctx) { return !onHdmi(ctx); }, reason: "reason.hdmi_only" },
    { when: function (ctx) { return !optimizerOn(ctx); }, reason: "reason.optimizer_off" }
];

function withOptimizer(extra) {
    return needsOptimizer.concat(extra || []);
}

function soundModeGame(ctx) {
    return ctx.val("sound.soundMode") === "game";
}

// Outputs for which the Game Optimizer offers Dolby Atmos.
var atmosOutputs = ["tv_speaker", "tv_external_speaker", "tv_speaker_external_arc", "tv_speaker_headphone",
                    "tv_speaker_bluetooth", "tv_speaker_optical_arc", "external_arc"];

var masteringDisabled = [
    { when: function (ctx) { return ctx.val("picture.hdrDynamicToneMapping") !== "off"; },
      reason: "reason.tone_mapping_on" },
    { when: function (ctx) {
        var value = ctx.val("picture.DtmProfessional");
        return !(value === true || value === "true");
    }, reason: "reason.professional_off" }
];

var area = {
    id: "games",
    icon: "games",
    title: "area.games",
    perSource: true,
    configs: ["tv.model.soundModeType"],
    watch: ["other.gameMode", "sound.soundMode", "sound.soundOutput", "picture.eyeComfortMode"],

    page: {
        id: "games",
        title: "area.games",
        sections: [
            { rows: [
                { id: "optimizer", type: "toggle", key: "other.gameMode", member: input,
                  title: "row.game_optimizer", subtitle: "detail.game_optimizer", search: "search.game_optimizer",
                  disabled: [{ when: function (ctx) { return !onHdmi(ctx); }, reason: "reason.hdmi_only" }] },
                { id: "perInput", type: "page", page: "inputs", title: "page.inputs", subtitle: "detail.inputs" }
            ] },
            { title: "section.adjust", rows: [
                { id: "refresh", type: "page", page: "refresh", title: "page.refresh",
                  summary: ["other.gameOptimization", "other.enableALLM"], search: "search.refresh" },
                { id: "genre", type: "page", page: "genre", title: "page.genre",
                  summary: ["other.gameGenre", "other.blackStabilizer"], search: "search.genre" },
                { id: "hdr", type: "page", page: "hdr", title: "page.hdr",
                  summary: ["picture.hdrDynamicToneMapping"], search: "search.hdr" },
                { id: "sound", type: "page", page: "sound", title: "page.sound",
                  summary: ["sound.aigamesound", "sound.supportATMOS"] },
                { id: "wide", type: "page", page: "wide", title: "page.wide",
                  summary: ["other.gameScreenRatio", "other.gameScreenPosition"], search: "search.wide" },
                { id: "dashboard", type: "page", page: "dashboard", title: "page.dashboard",
                  summary: ["other.enableQuickGame", "other.gameUIColor"], search: "search.dashboard" }
            ] }
        ]
    },

    pages: {
        // On or off for every HDMI input at once (LG: one switch per input in the app).
        inputs: {
            id: "inputs",
            title: "page.inputs",
            sections: [
                { rows: [inputRow(1), inputRow(2), inputRow(3), inputRow(4)] }
            ]
        },

        refresh: {
            id: "refresh",
            title: "page.refresh",
            sections: [
                { rows: [
                    { id: "vrr", type: "toggle", key: "other.gameOptimization", title: "row.vrr",
                      subtitle: "detail.vrr", search: "search.vrr", disabled: withOptimizer() },
                    { id: "freesync", type: "choice", key: "other.freesync", title: "row.freesync",
                      search: "search.freesync", disabled: withOptimizer() },
                    { id: "allm", type: "toggle", key: "other.enableALLM", title: "row.allm",
                      subtitle: "detail.allm", search: "search.allm", disabled: withOptimizer() },
                    { id: "inputLag", type: "choice", key: "other.inputOptimization", title: "row.input_lag",
                      search: "search.input_lag", disabled: withOptimizer() },
                    { id: "qft", type: "toggle", key: "other.enableQFT", title: "row.qft",
                      subtitle: "detail.qft", disabled: withOptimizer() },
                    { id: "highFrameRate", type: "toggle", key: "other.enable144HzBooster",
                      title: "row.high_frame_rate", subtitle: "detail.high_frame_rate", disabled: withOptimizer() }
                ] }
            ]
        },

        genre: {
            id: "genre",
            title: "page.genre",
            sections: [
                { rows: [
                    { id: "genre", type: "choice", key: "other.gameGenre", title: "row.genre",
                      disabled: withOptimizer() }
                ] },
                { title: "section.picture", rows: [
                    { id: "blackStabilizer", type: "slider", key: "other.blackStabilizer",
                      title: "row.black_stabilizer", disabled: withOptimizer() },
                    { id: "whiteStabilizer", type: "slider", key: "other.whiteStabilizer",
                      title: "row.white_stabilizer", disabled: withOptimizer() },
                    { id: "contrast", type: "slider", key: "other.gameAdjustContrast", title: "row.contrast",
                      disabled: withOptimizer() },
                    { id: "blackLevel", type: "slider", key: "other.gameBlackLevel", title: "row.black_level",
                      disabled: withOptimizer() },
                    { id: "sharpness", type: "slider", key: "other.gameSharpness", title: "row.sharpness",
                      disabled: withOptimizer() },
                    { id: "colorDepth", type: "slider", key: "other.gameColorDepth", title: "row.color_depth",
                      disabled: withOptimizer() },
                    // LG: only with VRR or FreeSync on.
                    { id: "darkAreas", type: "slider", key: "other.lowLevelAdjustment", title: "row.dark_areas",
                      format: "signed",
                      disabled: withOptimizer([{ when: function (ctx) {
                          var vrr = ctx.val("other.gameOptimization");
                          var freesync = ctx.val("other.freesync");
                          return vrr !== "on" && (freesync === undefined || freesync === "off");
                      }, reason: "reason.needs_vrr" }]) },
                    { id: "darkRoom", type: "choice", key: "other.darkMode", title: "row.dark_room",
                      search: "search.dark_room", disabled: withOptimizer() },
                    { id: "blueLight", type: "choice", key: "other.blueLight", title: "row.blue_light",
                      disabled: withOptimizer([{ when: function (ctx) {
                          return ctx.val("picture.eyeComfortMode") === "on";
                      }, reason: "reason.eye_comfort_on" }]) }
                ] },
                { rows: [
                    { id: "reset", type: "action", action: "resetGameGenre", title: "row.reset_genre",
                      subtitle: "detail.reset_genre",
                      confirm: { title: "confirm.reset_genre_title", text: "confirm.reset_genre_text",
                                 confirm: "confirm.reset_genre_button" },
                      disabled: withOptimizer() }
                ] }
            ]
        },

        // The picture values of an HDR signal. LG shows them only while one runs.
        hdr: {
            id: "hdr",
            title: "page.hdr",
            sections: [
                { rows: [
                    { id: "toneMapping", type: "choice", key: "picture.hdrDynamicToneMapping",
                      title: "row.tone_mapping", subtitle: "detail.tone_mapping", search: "search.tone_mapping" },
                    { id: "professional", type: "toggle", key: "picture.DtmProfessional", title: "row.professional",
                      on: true, off: false, onValues: [true, "true"],
                      disabled: [{ when: function (ctx) { return ctx.val("picture.hdrDynamicToneMapping") !== "off"; },
                                   reason: "reason.tone_mapping_on" }] },
                    { id: "mastering1k", type: "slider", key: "picture.DtmMastering1k", title: "row.mastering_1k",
                      disabled: masteringDisabled },
                    { id: "mastering4k", type: "slider", key: "picture.DtmMastering4k", title: "row.mastering_4k",
                      disabled: masteringDisabled },
                    { id: "mastering10k", type: "slider", key: "picture.DtmMastering10k", title: "row.mastering_10k",
                      disabled: masteringDisabled }
                ] }
            ]
        },

        sound: {
            id: "sound",
            title: "page.sound",
            sections: [
                { rows: [
                    { id: "aiGameSound", type: "toggle", key: "sound.aigamesound", title: "row.ai_game_sound",
                      subtitle: "detail.ai_game_sound",
                      disabled: withOptimizer([{ when: function (ctx) { return !soundModeGame(ctx); },
                                                 reason: "reason.sound_mode_game" }]) },
                    { id: "equalizerOn", type: "toggle", key: "sound.gameTVEqualizer", title: "row.game_equalizer",
                      disabled: withOptimizer([{ when: function (ctx) { return !soundModeGame(ctx); },
                                                 reason: "reason.sound_mode_game" }]) },
                    // The ten bands are one array (sound.gameTVEqualizer10band); LG's app edits them.
                    { id: "equalizerBands", type: "lgApp", title: "row.game_equalizer_bands",
                      app: { id: "com.webos.app.gameoptimizer", params: {} },
                      requires: function (ctx) { return ctx.has("sound.gameTVEqualizer"); },
                      disabled: withOptimizer([{ when: function (ctx) {
                          return !soundModeGame(ctx) || ctx.val("sound.gameTVEqualizer") !== "on";
                      }, reason: "reason.equalizer_off" }]) },
                    { id: "atmos", type: "toggle", key: "sound.supportATMOS", title: "row.dolby_atmos",
                      requires: function (ctx) { return ctx.cfg("tv.model.soundModeType") === "Dolby Atmos"; },
                      disabled: withOptimizer([{ when: function (ctx) {
                          return atmosOutputs.indexOf(ctx.val("sound.soundOutput") || "") < 0;
                      }, reason: "reason.atmos_output" }]) }
                ] }
            ]
        },

        wide: {
            id: "wide",
            title: "page.wide",
            sections: [
                { rows: [
                    { id: "ratio", type: "choice", key: "other.gameScreenRatio", title: "row.screen_ratio",
                      disabled: withOptimizer() },
                    { id: "position", type: "choice", key: "other.gameScreenPosition", title: "row.screen_position",
                      disabled: withOptimizer([{ when: function (ctx) {
                          return ctx.val("other.gameScreenRatio") === "16:9";
                      }, reason: "reason.ratio_16_9" }]) }
                ] }
            ]
        },

        dashboard: {
            id: "dashboard",
            title: "page.dashboard",
            sections: [
                { rows: [
                    { id: "enable", type: "toggle", key: "other.enableQuickGame", title: "row.dashboard",
                      subtitle: "detail.dashboard" },
                    { id: "color", type: "choice", key: "other.gameUIColor", title: "row.menu_color" }
                ] }
            ]
        }
    }
};
