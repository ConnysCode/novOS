#!/usr/bin/env node
// Checks module/GameMode.js outside the TV: when the gear key opens the game bar,
// against the cases of LG's rule (QuickSettingsMain.qml, Utils.isAvailableGameMode).
//
//   node game-check.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs.readFileSync(path.join(__dirname, "module/GameMode.js"), "utf8").replace(".pragma library", "");
const GameMode = {};
vm.createContext(GameMode);
vm.runInContext(source, GameMode, { filename: "GameMode.js" });

const on = { gameMode: { hdmi1: "off", hdmi3: "off", hdmi4: "on" }, gameInput: "hdmi4",
             pictureMode: "game", soundMode: "aiSoundPlus", enableQuickGame: "on" };
const front = ["com.webos.app.hdmi4"];
const single = { mode: "full", apps: [], usageType: "" };
const sxs = { mode: "sxs", controlMode: "none", usageType: "normal",
              apps: [{ appId: "com.webos.app.hdmi4", order: 0 }, { appId: "com.webos.app.youtube.leanback.v4", order: 1 }] };
const pipSub = { mode: "pip", mainAppId: "com.webos.app.livetv", controlMode: "none", usageType: "normal",
                 apps: [{ appId: "com.webos.app.livetv", order: 0 }, { appId: "com.webos.app.hdmi4", order: 1 }] };
const pipMain = Object.assign({}, pipSub, { mainAppId: "com.webos.app.hdmi4" });
const dual = { mode: "sxs", usageType: "dual_monitor", apps: [{ appId: "com.webos.app.hdmi4", order: 0 }] };

const cases = [
    ["all four hold", on, front, single, true],
    ["sound mode game instead of picture mode", Object.assign({}, on, { pictureMode: "standard", soundMode: "game" }), front, single, true],
    ["HDR game picture mode", Object.assign({}, on, { pictureMode: "hdrGame" }), front, single, true],
    ["Dolby Vision game picture mode", Object.assign({}, on, { pictureMode: "dolbyHdrGame" }), front, single, true],
    ["optimizer off for the input", Object.assign({}, on, { gameInput: "hdmi3" }), ["com.webos.app.hdmi3"], single, false],
    ["no game mode at all", Object.assign({}, on, { pictureMode: "hdrStandard" }), front, single, false],
    ["dashboard switched off", Object.assign({}, on, { enableQuickGame: "off" }), front, single, false],
    ["another app in front", on, ["com.webos.app.youtube.leanback.v4"], single, false],
    ["no foreground known", on, [], single, false],
    ["no multiview status", on, front, null, true],
    ["side by side", on, front, sxs, true],
    ["PIP with the game small", on, front, pipSub, false],
    ["PIP with the game as main picture", on, front, pipMain, true],
    ["dual PC monitor", on, front, dual, false],
    ["no game input", Object.assign({}, on, { gameInput: "" }), front, single, false],
    ["input that is not HDMI", Object.assign({}, on, { gameInput: "ip", gameMode: { ip: "on" } }), ["com.webos.app.livetv"], single, false],
    ["state from the TV on 9 Nov 2026", { gameMode: { hdmi1: "off", hdmi2: "off", hdmi3: "off", hdmi4: "on" }, gameInput: "hdmi3",
        pictureMode: "hdrStandard", soundMode: "aiSoundPlus", enableQuickGame: "on" }, ["com.webos.app.hdmi3"],
        { mode: "full", apps: [], usageType: "" }, false]
];

let failed = 0;
for (const [name, settings, foreground, multiview, expected] of cases) {
    const result = GameMode.isGameMode(settings, foreground, multiview);
    if (result !== expected) {
        failed++;
        console.log(`FAIL ${name}: ${result}, expected ${expected}`);
    }
}

const checks = [
    ["dark room steps", ["off", "level1", "level2"].map(GameMode.nextDarkStep).join(), "level1,level2,off"],
    ["genre key", GameMode.genreKey("Sports"), "sports"],
    ["unknown genre", GameMode.genreKey("Racing"), "standard"],
    ["empty status list", GameMode.statusList([]).join(), GameMode.defaultStatusList.join()],
    ["vrr", ["vrr", "off", "gsync", "freesync", "?"].map(GameMode.vrrState).join(), "on,off,gsync,freesync,"],
    ["second slot", [GameMode.secondSlot(true, true), GameMode.secondSlot(false, true), GameMode.secondSlot(false, false)].join(),
        "vrr,aiGameSound,whiteStabilizer"]
];
for (const [name, result, expected] of checks) {
    if (result !== expected) {
        failed++;
        console.log(`FAIL ${name}: ${result}, expected ${expected}`);
    }
}

console.log(failed === 0 ? `ok: ${cases.length + checks.length} cases` : `${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
