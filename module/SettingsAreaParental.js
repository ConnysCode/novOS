.pragma library

// Area 09, Kindersicherung. Built after LG's System › Sicherheit and the family care app
// (com.webos.app.familycare). Every change behind the parental lock goes through LG's own
// PIN prompt (luna://com.webos.notification/createPincodePrompt, promptType "parental"),
// exactly like LG: the PIN is never read, shown or compared here, the prompt only answers
// "matched". Locks with long LG lists (apps, inputs, channels) open LG's own page after the
// prompt, the way family care does it.

function locksOn(ctx) {
    return ctx.val("lock.parentalControl") === true;
}

var area = {
    id: "parental",
    icon: "parental",
    title: "area.parental",
    configs: ["tv.hw.tunerless"],
    keys: ["lock.parentalControl", "lock.offUsageTimeFlag"],
    page: {
        id: "parental",
        title: "area.parental",
        subtitle: "detail.parental",
        sections: [
            {
                title: "section.pin",
                rows: [
                    // LG: Sicherheit › Die Funktion aktivieren. Writes lock.parentalControl
                    // true/false only after the prompt matched.
                    { id: "locksEnabled", type: "toggle", key: "lock.parentalControl",
                      on: true, off: false, pin: "parental",
                      title: "row.locks_enabled", subtitle: "detail.locks_enabled",
                      search: "search.locks_enabled" },
                    // LG: Sicherheit › Passwort zurücksetzen, the system prompt "set_match"
                    // asks for the current PIN and then the new one.
                    { id: "changePin", type: "action", action: "pinPrompt",
                      params: { promptType: "set_match" },
                      title: "row.change_pin", search: "search.change_pin" }
                ]
            },
            {
                title: "section.locks",
                rows: [
                    // LG: Sicherheit › TV-Programmsperren (DVB). Other regions use other
                    // rating keys; there the descriptor is missing and the row hides.
                    { id: "rating", type: "choice", key: "lock.parentalGuidance", pin: "parental",
                      title: "row.rating", search: "search.rating",
                      disabled: [{ when: function (ctx) { return !locksOn(ctx); }, reason: "reason.locks_off" }] },
                    // Family care: PIN, then com.webos.app.channeledit with target channelLock.
                    { id: "channelLocks", type: "lgApp", pin: "parental",
                      app: { id: "com.webos.app.channeledit", params: { target: "channelLock" } },
                      title: "row.channel_locks", search: "search.channel_locks",
                      requires: function (ctx) { return ctx.cfg("tv.hw.tunerless") !== true; },
                      disabled: [{ when: function (ctx) { return !locksOn(ctx); }, reason: "reason.locks_off" }] },
                    // Family care: PIN, then LG's settings on ApplicationLocks.
                    { id: "appLocks", type: "lgApp", pin: "parental",
                      app: { id: "com.palm.app.settings", params: { target: "ApplicationLocks" } },
                      title: "row.app_locks", search: "search.app_locks",
                      disabled: [{ when: function (ctx) { return !locksOn(ctx); }, reason: "reason.locks_off" }] },
                    // Family care: PIN, then LG's settings on InputLocks (lock.inputBlock).
                    { id: "inputLocks", type: "lgApp", pin: "parental",
                      app: { id: "com.palm.app.settings", params: { target: "InputLocks" } },
                      title: "row.input_locks", search: "search.input_locks",
                      disabled: [{ when: function (ctx) { return !locksOn(ctx); }, reason: "reason.locks_off" }] }
                ]
            },
            {
                title: "section.screen_time",
                rows: [
                    // The time lock writes a coupled set (offUsageTimeFlag, usageTimeStart,
                    // usageTimeEnd, dailyRepeatFlag, unlockDate) with LG's own time format and
                    // limits (10 min to 23 h 50). That stays in family care, which asks for the PIN.
                    { id: "screenTime", type: "lgApp",
                      app: { id: "com.webos.app.familycare", params: { target: "parental" } },
                      title: "row.screen_time",
                      subtitle: function (ctx) {
                          return ctx.t(ctx.val("lock.offUsageTimeFlag") === "on" ? "detail.screen_time_on"
                                                                                 : "detail.screen_time_off");
                      },
                      search: "search.screen_time" }
                ]
            },
            {
                title: "section.volume_limit",
                rows: [
                    // Same write as LG's quick menu and family care, no PIN there either.
                    { id: "volumeLimit", type: "toggle", key: "lock.offHearingProtectFlag",
                      title: "row.volume_limit", subtitle: "detail.volume_limit",
                      search: "search.volume_limit" },
                    { id: "volumeLimitMax", type: "slider", key: "lock.offHearingProtectMaxVolume",
                      title: "row.volume_limit_max",
                      disabled: [{ when: function (ctx) { return ctx.val("lock.offHearingProtectFlag") !== "on"; },
                                   reason: "reason.volume_limit_off" }] }
                ]
            },
            {
                rows: [
                    { id: "usageStats", type: "lgApp",
                      app: { id: "com.webos.app.familycare", params: {} },
                      title: "row.usage_stats", subtitle: "detail.usage_stats",
                      search: "search.usage_stats" }
                ]
            }
        ]
    },
    pages: {}
};
