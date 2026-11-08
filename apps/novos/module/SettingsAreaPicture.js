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
                    "picture.whiteBalanceRedOffset", "picture.whiteBalanceGreenOffset", "picture.whiteBalanceBlueOffset"],
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
                // The 10 and 20 point steps keep one value per signal level; LG's own screen
                // with its test levels does that better than a list here.
                { rows: [
                    { id: "wbMultiPoint", type: "lgApp", title: "row.wb_multi_point", subtitle: "detail.wb_multi_point",
                      app: { id: "com.palm.app.settings", params: { target: "WhiteBalance" } },
                      requires: function (ctx) { return !twoPoint(ctx); } }
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
