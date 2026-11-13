.pragma library

// 01 Bild. LG's Picture tab and the picture part of AI Service, flattened to Bild › Seite
// › Auswahl. Keys, values and locks follow LG's settings app (docs/lg-settings). All
// values except the FILMMAKER auto start and the blue light filter belong to the current
// input and picture mode; the service applies them there by itself.

// LG greys the picture values while an ISF calibration holds the current mode.
function isfLocked(ctx) {
    var isf = ctx.val("picture.isfMode");
    var mode = ctx.val("picture.pictureMode");
    return typeof isf === "object" && isf !== null && !!isf[mode] && isf[mode] !== "none";
}

var isfLock = { when: isfLocked, reason: "reason.isf_calibrated" };

// Energy saving at auto or max drives the panel brightness itself.
var energyLock = {
    when: function (ctx) {
        var saving = ctx.val("picture.energySaving");
        return saving === "auto" || saving === "max";
    },
    reason: "reason.energy_saving_controls"
};

// The six colours of the fine tune share one key each, picked by the selected colour.
function colorKey(prefix) {
    return function (ctx) {
        var color = ctx.val("picture.colorManagementColorSystem") || "red";
        return "picture.colorManagement" + prefix + color.charAt(0).toUpperCase() + color.slice(1);
    };
}

var colorNames = ["Red", "Green", "Blue", "Cyan", "Magenta", "Yellow"];

function colorWatch(prefix) {
    var keys = [];
    for (var i = 0; i < colorNames.length; i++) keys.push("picture.colorManagement" + prefix + colorNames[i]);
    return keys;
}

var fineTuneLock = {
    when: function (ctx) { return ctx.val("picture.dynamicColor") !== "user"; },
    reason: "reason.fine_tune_needs_user"
};

// Two point white balance: gain for the bright point, offset for the dark one.
function whiteBalanceKey(color) {
    return function (ctx) {
        return "picture.whiteBalance" + color + (ctx.val("picture.whiteBalancePoint") === "low" ? "Offset" : "Gain");
    };
}

function twoPoint(ctx) {
    return ctx.val("picture.whiteBalanceMethod") === "2";
}

// 10 and 20 point white balance (K3-Einst-Weissabgleich): LG keeps one array per value with
// an entry per point. "20 Punkte" has 22 points. Two ways to pick the point, as LG's own
// screen: by signal level ("10", "22"; the level is a setting of its own, whiteBalanceIre,
// and the arrays count their entries in the order the descriptor lists the levels) or by
// code value ("10code", "22code"; whiteBalanceCodeValue holds the position, the codes
// come from getSystemSettingValues per mastering luminance, SettingsData.readWhiteBalanceCodes).
// The maximum luminance is a single value, set at level 100 only, and only by signal level.
function method(ctx) {
    return String(ctx.val("picture.whiteBalanceMethod"));
}

function multiPoint(ctx) {
    return ["10", "22", "10code", "22code"].indexOf(method(ctx)) >= 0;
}

function tenPoint(ctx) {
    return method(ctx).indexOf("10") === 0;
}

function byCode(ctx) {
    return method(ctx).indexOf("code") > 0;
}

function wbKey(name) {
    return function (ctx) { return "picture." + name + (tenPoint(ctx) ? "10pt" : ""); };
}

var wbLevel = { id: "wbLevel", type: "levels", keyOf: wbKey("whiteBalanceIre"), label: "row.wb_level",
                group: 0, wide: true,
                // While the descriptor lists no levels: LG's levels, lowest first.
                fallback: function (ctx) {
                    return tenPoint(ctx) ? [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
                                         : [2.5, 5, 7.5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
                                            65, 70, 75, 80, 85, 90, 95, 100];
                },
                format: function (value, ctx) {
                    return ctx.t("value.wb_level", { value: String(value).replace(".", ctx.t("format.decimal_mark")) });
                } };

// The codes of the current mastering luminance, highest last as LG lists them.
function wbCodes(ctx) {
    var all = ctx.list(tenPoint(ctx) ? "whiteBalanceCodes10" : "whiteBalanceCodes");
    var codes = all ? all[ctx.val("other.masterLuminanceLevel")] : null;
    var entries = [];
    // The position as LG keeps it, a string ("21").
    for (var i = 0; Array.isArray(codes) && i < codes.length; i++) entries.push({ value: String(i), label: String(codes[i]) });
    return entries;
}

var wbCode = { id: "wbCode", type: "levels", group: 0, wide: true, label: "row.wb_code",
               keyOf: function (ctx) { return "picture.whiteBalanceCodeValue" + (tenPoint(ctx) ? "10pt" : ""); },
               entries: wbCodes };

function wbAtTop(ctx) {
    return Number(ctx.val(wbKey("whiteBalanceIre")(ctx))) === 100;
}

function wbColumn(id, name, label, dot) {
    return { id: id, type: "slider", keyOf: wbKey(name), index: "level", label: label, dot: dot || "",
             center: 0, format: "signed", group: 1 };
}

function wbColumns(ctx) {
    var columns = [byCode(ctx) ? wbCode : wbLevel,
                   wbColumn("wbLuminance", "adjustingLuminance", "row.wb_luminance"),
                   wbColumn("wbRed", "whiteBalanceRed", "row.red", "channelRed"),
                   wbColumn("wbGreen", "whiteBalanceGreen", "row.green", "channelGreen"),
                   wbColumn("wbBlue", "whiteBalanceBlue", "row.blue", "channelBlue")];
    if (!byCode(ctx)) {
        columns.push({ id: "wbMaxLuminance", type: "slider", key: "picture.whiteBalanceLuminance",
                       label: "row.wb_max_luminance", group: 2, wide: true,
                       disabled: [{ when: function (ctx) { return !wbAtTop(ctx); }, reason: "reason.wb_only_at_100" }] });
    }
    return columns;
}

// "20 Punkte · Angepasst" while a value at some point is not 0.
function wbPointsText(ctx) {
    var points = ctx.label("picture.whiteBalanceMethod", method(ctx));
    var names = ["adjustingLuminance", "whiteBalanceRed", "whiteBalanceGreen", "whiteBalanceBlue"];
    for (var n = 0; n < names.length; n++) {
        var values = ctx.val(wbKey(names[n])(ctx));
        for (var i = 0; Array.isArray(values) && i < values.length; i++) {
            if (Number(values[i]) !== 0) return points + " · " + ctx.t("value.adjusted");
        }
    }
    return points;
}

var area = {
    id: "picture",
    icon: "picture",
    title: "area.picture",
    perSource: true,
    watch: ["picture.pictureSettingModified", "picture.isfMode", "picture.energySaving", "picture.colorSystem",
            "picture.applyToAllInput"],
    page: {
        id: "picture",
        title: "area.picture",
        sections: [
            { rows: [
                { id: "pictureMode", type: "choice", key: "picture.pictureMode", title: "row.picture_mode",
                  search: "search.picture_mode",
                  disabled: [{ when: isfLocked, reason: "reason.isf_calibrated" }] },
                { id: "format", type: "page", page: "format", title: "row.format",
                  value: function (ctx) {
                      var ratio = ctx.val("aspectRatio.arcPerApp");
                      return ratio ? ctx.label("aspectRatio.arcPerApp", ratio) : "";
                  } }
            ] },
            { title: "section.adjust", rows: [
                { id: "brightness", type: "page", page: "brightness", title: "row.brightness_contrast",
                  summary: ["picture.backlight", "picture.localDimming"], search: "search.brightness" },
                { id: "color", type: "page", page: "color", title: "row.color",
                  summary: ["picture.colorTemperature", "picture.colorGamut"], search: "search.color" },
                { id: "clarity", type: "page", page: "clarity", title: "row.clarity",
                  summary: ["picture.truMotionMode", "picture.superResolution"], search: "search.clarity" },
                { id: "automatic", type: "page", page: "automatic", title: "row.automatic",
                  summary: ["aiPicture.ai_Picture", "picture.eyeComfortMode"], search: "search.automatic" }
            ] },
            { title: "section.more", rows: [
                { id: "filmMakerAuto", type: "toggle", key: "picture.filmMakerMode", title: "row.film_maker_auto",
                  subtitle: "detail.film_maker_auto", search: "search.film_maker" },
                { id: "pictureWizard", type: "lgApp", app: { id: "com.webos.app.picturewizard", params: {} },
                  title: "row.picture_wizard", subtitle: "detail.picture_wizard", search: "search.picture_wizard",
                  // LG offers the wizard only where the TV lists the personalised mode.
                  requires: function (ctx) {
                      var desc = ctx.desc("picture.pictureMode");
                      var values = desc && desc.values && desc.values.arrayExt ? desc.values.arrayExt : [];
                      for (var i = 0; i < values.length; i++) {
                          if (values[i].value === "personalized" && values[i].visible !== false) return true;
                      }
                      return false;
                  } }
            ] },
            { rows: [
                { id: "applyAll", type: "action", action: "applyPictureToAll", title: "row.apply_to_all",
                  needs: ["picture.applyToAllInput"],
                  disabled: [isfLock, { when: function (ctx) {
                      var desc = ctx.desc("picture.applyToAllInput");
                      return !!desc && desc.ui && desc.ui.active === false;
                  }, reason: "reason.not_available_now" }],
                  confirm: { title: "confirm.apply_all_title", text: "confirm.apply_all_text",
                             confirm: "confirm.apply_all_button", safe: true } },
                { id: "reset", type: "action", action: "resetPicture", title: "row.reset",
                  disabled: [isfLock],
                  confirm: { title: "confirm.reset_title", text: "confirm.reset_text", confirm: "confirm.reset_button" } }
            ] }
        ]
    },
    pages: {
        brightness: {
            id: "brightness",
            title: "row.brightness_contrast",
            sections: [{ rows: [
                { id: "backlight", type: "slider", key: "picture.backlight", title: "row.backlight", step: 1,
                  search: "search.backlight", disabled: [isfLock, energyLock] },
                { id: "contrast", type: "slider", key: "picture.contrast", title: "row.contrast", disabled: [isfLock] },
                { id: "blackLevel", type: "slider", key: "picture.brightness", title: "row.black_level",
                  search: "search.black_level", disabled: [isfLock] },
                { id: "dynamicContrast", type: "choice", key: "picture.dynamicContrast", title: "row.dynamic_contrast",
                  disabled: [isfLock] },
                { id: "peakBrightness", type: "choice", key: "picture.peakBrightness", title: "row.peak_brightness" },
                { id: "toneMapping", type: "choice", key: "picture.hdrDynamicToneMapping", title: "row.tone_mapping",
                  search: "search.tone_mapping" },
                { id: "hgig", type: "toggle", key: "picture.hgig", title: "row.hgig" },
                { id: "expressionEnhancer", type: "choice", key: "picture.expressionEnhancer",
                  title: "row.expression_enhancer" },
                { id: "gamma", type: "choice", key: "picture.gamma", title: "row.gamma", disabled: [isfLock] },
                { id: "nearBlack", type: "slider", key: "picture.nearBlackDetail", title: "row.near_black",
                  format: "signed" },
                { id: "videoRange", type: "choice", key: "picture.blackLevel", title: "row.video_range",
                  member: function (ctx) { return ctx.val("picture.colorSystem"); },
                  search: "search.video_range" },
                { id: "localDimming", type: "choice", key: "picture.localDimming", title: "row.local_dimming",
                  search: "search.local_dimming", disabled: [isfLock] },
                { id: "ambientLight", type: "toggle", key: "picture.filmmakerAmbientLight",
                  title: "row.film_maker_ambient" }
            ] }]
        },
        color: {
            id: "color",
            title: "row.color",
            sections: [
                { rows: [
                    { id: "colorDepth", type: "slider", key: "picture.color", title: "row.color_depth",
                      disabled: [isfLock] },
                    { id: "tint", type: "slider", key: "picture.tint", title: "row.tint", format: "tint",
                      disabled: [isfLock] },
                    { id: "colorGamut", type: "choice", key: "picture.colorGamut", title: "row.color_gamut",
                      search: "search.color_gamut", disabled: [isfLock] },
                    { id: "colorTemperature", type: "slider", key: "picture.colorTemperature",
                      title: "row.color_temperature", format: "temperature", search: "search.color_temperature",
                      disabled: [isfLock] }
                ] },
                { title: "section.fine", rows: [
                    { id: "whiteBalance", type: "page", page: "whiteBalance", title: "row.white_balance",
                      subtitle: "detail.white_balance", search: "search.white_balance" },
                    { id: "fineTune", type: "page", page: "fineTune", title: "row.fine_tune",
                      subtitle: "detail.fine_tune", search: "search.fine_tune" },
                    { id: "memoryColors", type: "page", page: "memoryColors", title: "row.memory_colors",
                      subtitle: "detail.memory_colors", search: "search.memory_colors" }
                ] }
            ]
        },
        whiteBalance: {
            id: "whiteBalance",
            title: "row.white_balance",
            watch: ["picture.whiteBalanceRedGain", "picture.whiteBalanceGreenGain", "picture.whiteBalanceBlueGain",
                    "picture.whiteBalanceRedOffset", "picture.whiteBalanceGreenOffset", "picture.whiteBalanceBlueOffset",
                    "picture.whiteBalanceIre", "picture.whiteBalanceIre10pt", "picture.whiteBalanceLuminance",
                    "picture.adjustingLuminance", "picture.adjustingLuminance10pt",
                    "picture.whiteBalanceRed", "picture.whiteBalanceRed10pt",
                    "picture.whiteBalanceGreen", "picture.whiteBalanceGreen10pt",
                    "picture.whiteBalanceBlue", "picture.whiteBalanceBlue10pt",
                    "picture.whiteBalanceCodeValue", "picture.whiteBalanceCodeValue10pt",
                    "picture.keyListForCopyWb", "other.masterLuminanceLevel"],
            sections: [
                { rows: [
                    { id: "wbTemperature", type: "slider", key: "picture.colorTemperature",
                      title: "row.color_temperature", format: "temperature", disabled: [isfLock] },
                    { id: "wbMethod", type: "choice", key: "picture.whiteBalanceMethod", title: "row.wb_method" },
                    { id: "wbPoint", type: "choice", key: "picture.whiteBalancePoint", title: "row.wb_point",
                      requires: twoPoint }
                ] },
                { title: "section.two_point", rows: [
                    { id: "wbRed", type: "slider", keyOf: whiteBalanceKey("Red"), title: "row.red",
                      format: "signed", requires: twoPoint },
                    { id: "wbGreen", type: "slider", keyOf: whiteBalanceKey("Green"), title: "row.green",
                      format: "signed", requires: twoPoint },
                    { id: "wbBlue", type: "slider", keyOf: whiteBalanceKey("Blue"), title: "row.blue",
                      format: "signed", requires: twoPoint }
                ] },
                // The 10 and 20 point steps keep one value per signal level: a bar over the
                // picture with the level and its values (BandEditor.qml).
                { rows: [
                    { id: "wbMultiPoint", type: "bands", title: "row.wb_points",
                      keyOf: function (ctx) { return byCode(ctx) ? wbCode.keyOf(ctx) : wbKey("whiteBalanceIre")(ctx); },
                      subtitle: wbPointsText, columns: wbColumns,
                      // As LG: back to the TV's values for every key of keyListForCopyWb.
                      button: { label: "row.reset", danger: true, action: "resetWhiteBalance",
                                confirm: { title: "confirm.wb_reset_title", text: "confirm.wb_reset_text",
                                           confirm: "confirm.wb_reset_button", danger: true } },
                      // "Weißabgleich · 20 Punkte"; the column names the code value.
                      editorTitle: function (ctx) {
                          return ctx.t("title.wb_editor", { points: ctx.label("picture.whiteBalanceMethod",
                                                                                method(ctx).replace("code", "")) });
                      },
                      requires: multiPoint }
                ] }
            ]
        },
        fineTune: {
            id: "fineTune",
            title: "row.fine_tune",
            watch: colorWatch("Saturation").concat(colorWatch("Hue")).concat(colorWatch("Luminance")),
            sections: [{ rows: [
                { id: "dynamicColor", type: "choice", key: "picture.dynamicColor", title: "row.color_adjustment" },
                { id: "colorSystem", type: "choice", key: "picture.colorManagementColorSystem",
                  title: "row.select_color", disabled: [fineTuneLock] },
                { id: "saturation", type: "slider", keyOf: colorKey("Saturation"), title: "row.saturation",
                  format: "signed", disabled: [fineTuneLock] },
                { id: "hue", type: "slider", keyOf: colorKey("Hue"), title: "row.hue", format: "signed",
                  disabled: [fineTuneLock] },
                { id: "luminance", type: "slider", keyOf: colorKey("Luminance"), title: "row.luminance",
                  format: "signed", disabled: [fineTuneLock] }
            ] }]
        },
        // No LG menu shows these three; the service keeps them per input and mode.
        memoryColors: {
            id: "memoryColors",
            title: "row.memory_colors",
            note: "note.memory_colors",
            sections: [{ rows: [
                { id: "skin", type: "slider", key: "picture.skinColor", title: "row.skin_color", format: "signed" },
                { id: "sky", type: "slider", key: "picture.skyColor", title: "row.sky_color", format: "signed" },
                { id: "grass", type: "slider", key: "picture.grassColor", title: "row.grass_color", format: "signed" }
            ] }]
        },
        clarity: {
            id: "clarity",
            title: "row.clarity",
            sections: [
                { rows: [
                    { id: "sharpness", type: "slider", key: "picture.sharpness", title: "row.sharpness",
                      disabled: [isfLock] },
                    { id: "superResolution", type: "choice", key: "picture.superResolution",
                      title: "row.super_resolution", disabled: [isfLock] },
                    { id: "noiseReduction", type: "choice", key: "picture.noiseReduction",
                      title: "row.noise_reduction", disabled: [isfLock] },
                    { id: "mpegNoise", type: "choice", key: "picture.mpegNoiseReduction",
                      title: "row.mpeg_noise_reduction", disabled: [isfLock] },
                    { id: "smoothGradation", type: "choice", key: "picture.smoothGradation",
                      title: "row.smooth_gradation", disabled: [isfLock] },
                    { id: "realCinema", type: "toggle", key: "picture.realCinema", title: "row.real_cinema",
                      search: "search.real_cinema" },
                    { id: "precisionDetail", type: "toggle", key: "picture.dolbyPrecisionDetail",
                      title: "row.precision_detail" }
                ] },
                { title: "section.motion", rows: [
                    { id: "truMotion", type: "choice", key: "picture.truMotionMode", title: "row.tru_motion",
                      search: "search.tru_motion", disabled: [isfLock] },
                    { id: "judder", type: "slider", key: "picture.truMotionJudder", title: "row.judder",
                      requires: function (ctx) { return ctx.val("picture.truMotionMode") === "user"; } },
                    { id: "blur", type: "slider", key: "picture.truMotionBlur", title: "row.blur",
                      requires: function (ctx) { return ctx.val("picture.truMotionMode") === "user"; } }
                ] }
            ]
        },
        automatic: {
            id: "automatic",
            title: "row.automatic",
            sections: [{ rows: [
                { id: "aiPicture", type: "toggle", key: "aiPicture.ai_Picture", title: "row.ai_picture",
                  subtitle: "detail.ai_picture", search: "search.ai_picture" },
                { id: "aiBrightness", type: "toggle", key: "aiPicture.ai_Brightness", title: "row.ai_brightness",
                  subtitle: "detail.ai_brightness", search: "search.ai_brightness" },
                { id: "aiGenre", type: "toggle", key: "aiPicture.ai_Genre", title: "row.ai_genre",
                  subtitle: "detail.ai_genre" },
                { id: "blueLight", type: "toggle", key: "picture.eyeComfortMode", title: "row.blue_light",
                  subtitle: "detail.blue_light", search: "search.blue_light" },
                { id: "motionEyeCare", type: "toggle", key: "picture.motionEyeCare", title: "row.motion_eye_care",
                  subtitle: "detail.motion_eye_care", disabled: [isfLock] }
            ] }]
        },
        format: {
            id: "format",
            title: "row.format",
            sections: [
                { rows: [
                    { id: "aspectRatio", type: "choice", key: "aspectRatio.arcPerApp", title: "row.aspect_ratio",
                      search: "search.aspect_ratio" },
                    { id: "justScan", type: "choice", key: "aspectRatio.justScan", title: "row.just_scan",
                      search: "search.just_scan" }
                ] },
                { title: "section.position", rows: [
                    { id: "position", type: "page", page: "position", title: "row.position_size",
                      subtitle: "detail.position_size" }
                ] }
            ]
        },
        position: {
            id: "position",
            title: "row.position_size",
            note: "note.position_size",
            sections: [{ rows: [
                { id: "hPosition", type: "slider", key: "picture.hPosition", title: "row.h_position", format: "signed" },
                { id: "vPosition", type: "slider", key: "picture.vPosition", title: "row.v_position", format: "signed" },
                { id: "hSize", type: "slider", key: "picture.hSize", title: "row.h_size", format: "signed" },
                { id: "vSize", type: "slider", key: "picture.vSize", title: "row.v_size", format: "signed" }
            ] }]
        }
    }
};
