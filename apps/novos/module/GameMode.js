.pragma library

// When the gear key opens the game bar instead of the panel. LG's rule from its
// QuickSettingsMain.qml (AppModeCheck) and Utils.isAvailableGameMode on webOS 10.3.2,
// taken over unchanged (docs/game-overlay-plan.md, "Wann es erscheint"):
//
//   1. the Game Optimizer is on for the game input: other.gameMode[gameInput] === "on",
//   2. a game picture mode or the game sound mode,
//   3. other.enableQuickGame === "on" (the "Spiele-Dashboard" switch),
//   4. the HDMI app of the game input is in the foreground, not as a dual PC monitor;
//      in Multi View only as the main picture of PIP or as part of SXS.

var gamePictureModes = ["game", "hdrGame", "dolbyHdrGame"];
var gameSoundMode = "game";
var dualMonitor = "dual_monitor";

// "hdmi3" → "com.webos.app.hdmi3"; any other input has no game bar.
function appOfInput(gameInput) {
    return /^hdmi[1-4]$/.test(gameInput || "") ? "com.webos.app." + gameInput : "";
}

// The order of an app in multiviewcontroller's list for its controlMode.
function orderOfControl(controlMode) {
    var orders = { main: 0, sub: 1, sub2: 2, sub3: 3 };
    return orders[controlMode] !== undefined ? orders[controlMode] : -1;
}

// Point 4: foreground is the appIds of applicationManager/getForegroundAppInfo
// (extraInfo: true), multiview the status of multiviewcontroller/getStatus.
function gameInFront(gameInput, foreground, multiview) {
    var appId = appOfInput(gameInput);
    if (appId === "" || !foreground || foreground.indexOf(appId) < 0) return false;
    var status = multiview || {};
    if (status.usageType === dualMonitor) return false;
    var apps = status.apps || [];
    if (apps.length === 0) return true;
    var control = status.controlMode || "";
    var listed = false;
    for (var i = 0; i < apps.length; i++) {
        if (apps[i].appId === appId &&
            (control === "" || control === "none" || apps[i].order === orderOfControl(control))) {
            listed = true;
        }
    }
    return listed && ((status.mode === "pip" && status.mainAppId === appId) || status.mode === "sxs");
}

// settings: { gameMode, enableQuickGame, gameInput, pictureMode, soundMode } as read from
// settingsservice; gameInput comes from the dimension of the category "other".
function isGameMode(settings, foreground, multiview) {
    var values = settings || {};
    var modes = values.gameMode || {};
    if (!values.gameInput || modes[values.gameInput] !== "on") return false;
    if (gamePictureModes.indexOf(values.pictureMode) < 0 && values.soundMode !== gameSoundMode) return false;
    if (values.enableQuickGame !== "on") return false;
    return gameInFront(values.gameInput, foreground, multiview);
}

// The four live values of the bar, in LG's order (other.gameDashboardStatusList). LG's
// factory list stands in when the TV has none or an empty one.
var defaultStatusList = ["fps", "vrr_aiGameSound_whiteStabilizer", "blackStabilizer", "lowLatency"];

function statusList(list) {
    return list && list.length > 0 ? list.slice(0, 4) : defaultStatusList.slice();
}

// The genres in LG's order, their value as settingsservice writes it and the key of
// their text in the namespace "game".
var genres = [
    { value: "Standard", key: "standard" },
    { value: "FPS", key: "fps" },
    { value: "RPG", key: "rpg" },
    { value: "RTS", key: "rts" },
    { value: "Sports", key: "sports" },
    { value: "USER", key: "user" }
];

function genreKey(value) {
    for (var i = 0; i < genres.length; i++) {
        if (genres[i].value === value) return genres[i].key;
    }
    return "standard";
}

// Dark Room: OK steps on, as LG's dashboard does.
var darkSteps = ["off", "level1", "level2"];

function nextDarkStep(current) {
    var index = darkSteps.indexOf(current);
    return darkSteps[(index + 1) % darkSteps.length];
}

// "vrr" → on, "off" → off, G-Sync and FreeSync by name; anything else unknown.
function vrrState(vrrType) {
    var known = { vrr: "on", on: "on", off: "off", gsync: "gsync", freesync: "freesync" };
    return known[vrrType] || "";
}

// Which value stands in the second slot: VRR where the TV has it (other.gameOptimization
// or other.freesync visible), else AI game sound where the sound has a game mode, else the
// white stabilizer. LG's Interfaces.qml: checkSupportVRR and getSoundModeValues.
function secondSlot(supportVrr, hasGameSound) {
    if (supportVrr) return "vrr";
    if (hasGameSound) return "aiGameSound";
    return "whiteStabilizer";
}
