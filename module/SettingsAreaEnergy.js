.pragma library

// Area 07 "Energie & Timer" of the settings modal. Keys and writes as in LG's
// "Allgemein › Energiesparen" and "System › Zeit & Timer › Timer", see
// docs/lg-settings/alle-einstellungen.md. The sleep timer, the timer times, the
// screen off and the power-on switch run as host actions like in the quick panel.

function clock(hour, minute) {
    var h = Number(hour);
    var m = Number(minute);
    if (isNaN(h) || isNaN(m)) return "";
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

function timerValue(ctx, prefix) {
    if (ctx.val("time." + prefix + "Enable") !== "on") return ctx.t("value.off");
    return clock(ctx.val("time." + prefix + "Hour"), ctx.val("time." + prefix + "Minute"));
}

// LG keeps the repeat days as a bitmask in a string: bit 0 is Sunday, bit 6 Saturday.
var dayOrder = [1, 2, 3, 4, 5, 6, 0];
var dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

function repeatValue(ctx, key) {
    var mask = parseInt(ctx.val(key), 10) || 0;
    if (mask === 0) return ctx.t("value.repeat_once");
    if (mask === 127) return ctx.t("value.repeat_daily");
    if (mask === 62) return ctx.t("value.repeat_weekdays");
    if (mask === 65) return ctx.t("value.repeat_weekend");
    var names = [];
    for (var i = 0; i < dayOrder.length; i++) {
        if (mask & (1 << dayOrder[i])) names.push(ctx.t("value.day_short." + dayNames[dayOrder[i]]));
    }
    return names.join(", ");
}

function dayRows(key) {
    var rows = [];
    for (var i = 0; i < dayOrder.length; i++) {
        var day = dayOrder[i];
        rows.push({ id: "day_" + dayNames[day], type: "toggle", key: key, bit: day,
                    title: "row.day." + dayNames[day] });
    }
    return rows;
}

function sleepValue(ctx) {
    var minutes = ctx.state.sleepMinutes || 0;
    if (minutes <= 0) return ctx.t("value.off");
    return ctx.t("value.sleep_remaining", { minutes: minutes });
}

function offTimerOff(ctx) {
    return ctx.val("time.offTimerEnable") !== "on";
}

var area = {
    id: "energy",
    icon: "energy",
    title: "area.energy",
    // Only read: they decide visibility and locks, no row of their own.
    reads: ["timer.noMenuAutoOff15Min", "picture.ScreenOff", "time.onTimerHour", "time.onTimerMinute",
            "time.onTimerAppId", "time.offTimerHour", "time.offTimerMinute"],
    page: {
        id: "energy",
        title: "area.energy",
        sections: [
            {
                title: "section.energy_saving",
                rows: [
                    { id: "energySaving", type: "choice", key: "picture.energySaving",
                      title: "row.energy_saving", subtitle: "detail.energy_saving",
                      search: "search.energy_saving" },
                    // LG asks for it right after choosing "Auto".
                    { id: "energySavingAutoMin", type: "slider", key: "picture.energySavingAutoMin",
                      title: "row.minimum_brightness",
                      disabled: [{ when: function (ctx) { return ctx.val("picture.energySaving") !== "auto"; },
                                   reason: "reason.energy_saving_not_auto" }] },
                    { id: "screenOff", type: "action", action: "screenOff",
                      title: "row.screen_off", subtitle: "detail.screen_off", search: "search.screen_off",
                      requires: function (ctx) { return ctx.desc("picture.ScreenOff") !== undefined; },
                      disabled: [{ when: function (ctx) {
                                       var desc = ctx.desc("picture.ScreenOff");
                                       return desc && desc.ui && desc.ui.active === false;
                                   },
                                   reason: "reason.screen_off_app" }] }
                ]
            },
            {
                title: "section.auto_off",
                rows: [
                    { id: "automaticStandBy", type: "choice", key: "time.automaticStandBy",
                      title: "row.auto_off_idle", subtitle: "detail.auto_off_idle", search: "search.auto_off" },
                    // LG hides the 15-minute switch where the regulation makes it mandatory.
                    { id: "autoOff15Min", type: "toggle", key: "time.autoOff15Min",
                      title: "row.auto_off_no_signal", subtitle: "detail.auto_off_no_signal",
                      search: "search.auto_off",
                      requires: function (ctx) { return ctx.val("timer.noMenuAutoOff15Min") !== "on"; } },
                    { id: "noSignalAutoOff", type: "toggle", key: "time.noSignalAutoOff",
                      title: "row.auto_off_no_signal", subtitle: "detail.auto_off_no_signal",
                      search: "search.auto_off" },
                    { id: "noOperationAutoOff", type: "choice", key: "time.noOperationAutoOff",
                      title: "row.auto_off_no_operation", search: "search.auto_off" },
                    // Without an LG menu. LG marks the key invisible, so it shows only with hiddenOk.
                    { id: "autoPowerOff2Hour", type: "toggle", key: "timer.autoPowerOff2Hour", hiddenOk: true,
                      title: "row.auto_off_two_hours", subtitle: "detail.auto_off_two_hours",
                      search: "search.auto_off" }
                ]
            },
            {
                title: "section.timer",
                rows: [
                    { id: "timers", type: "page", page: "timers", title: "row.timers",
                      subtitle: function (ctx) {
                          return ctx.t("detail.timers_summary", { sleep: sleepValue(ctx),
                                                                  on: timerValue(ctx, "onTimer"),
                                                                  off: timerValue(ctx, "offTimer") });
                      },
                      search: "search.timers" }
                ]
            },
            {
                title: "section.start",
                rows: [
                    { id: "quickStartMode", type: "toggle", key: "option.quickStartMode",
                      title: "row.quick_start", subtitle: "detail.quick_start", search: "search.quick_start" },
                    { id: "standByLight", type: "toggle", key: "option.standByLight",
                      title: "row.standby_light", subtitle: "detail.standby_light", search: "search.standby_light" }
                ]
            }
        ]
    },
    pages: {
        timers: {
            id: "timers",
            title: "page.timers",
            sections: [
                {
                    rows: [
                        { id: "sleepTimer", type: "action", action: "sleepTimer", title: "row.sleep_timer",
                          value: sleepValue, search: "search.sleep_timer" },
                        { id: "onTimer", type: "page", page: "onTimer", title: "row.on_timer",
                          subtitle: function (ctx) { return timerValue(ctx, "onTimer"); },
                          search: "search.on_timer" },
                        { id: "offTimer", type: "page", page: "offTimer", title: "row.off_timer",
                          subtitle: function (ctx) { return timerValue(ctx, "offTimer"); },
                          search: "search.off_timer" }
                    ]
                },
                {
                    title: "section.auto_off",
                    rows: [
                        { id: "autoOff2HourOnTimer", type: "toggle", key: "time.autoOff2HourOnTimer",
                          title: "row.auto_off_after_timer", subtitle: "detail.auto_off_after_timer",
                          search: "search.auto_off" }
                    ]
                }
            ]
        },
        onTimer: {
            id: "onTimer",
            title: "page.on_timer",
            sections: [
                {
                    rows: [
                        // The host also moves onTimerAppId from Live TV to Home, see the report.
                        { id: "onTimerEnable", type: "toggle", key: "time.onTimerEnable", action: "onTimerEnable",
                          title: "row.timer_enable" },
                        { id: "onTimerTime", type: "action", action: "timerTime", params: { timer: "on" },
                          title: "row.timer_time",
                          value: function (ctx) { return clock(ctx.val("time.onTimerHour"), ctx.val("time.onTimerMinute")); } },
                        { id: "onTimerRepeat", type: "page", page: "onTimerRepeat", title: "row.timer_repeat",
                          subtitle: function (ctx) { return repeatValue(ctx, "time.onTimerWeekday"); },
                          requires: function (ctx) { return ctx.has("time.onTimerWeekday"); } },
                        { id: "onTimerVolume", type: "slider", key: "time.onTimerVolume", title: "row.timer_volume" },
                        // Input and channel need LG's lists of inputs and tuned channels.
                        { id: "onTimerSource", type: "lgApp", title: "row.timer_source",
                          subtitle: "detail.timer_source",
                          app: { id: "com.palm.app.settings", params: { target: "TimerPowerOn" } } }
                    ]
                }
            ]
        },
        onTimerRepeat: {
            id: "onTimerRepeat",
            title: "page.timer_repeat",
            subtitle: "detail.timer_repeat",
            sections: [{ rows: dayRows("time.onTimerWeekday") }]
        },
        offTimer: {
            id: "offTimer",
            title: "page.off_timer",
            sections: [
                {
                    rows: [
                        { id: "offTimerEnable", type: "toggle", key: "time.offTimerEnable", title: "row.timer_enable" },
                        { id: "offTimerTime", type: "action", action: "timerTime", params: { timer: "off" },
                          title: "row.timer_time",
                          value: function (ctx) { return clock(ctx.val("time.offTimerHour"), ctx.val("time.offTimerMinute")); },
                          disabled: [{ when: offTimerOff, reason: "reason.timer_off" }] },
                        { id: "offTimerRepeat", type: "page", page: "offTimerRepeat", title: "row.timer_repeat",
                          subtitle: function (ctx) { return repeatValue(ctx, "time.offTimerWeekday"); },
                          requires: function (ctx) { return ctx.has("time.offTimerWeekday"); },
                          disabled: [{ when: offTimerOff, reason: "reason.timer_off" }] }
                    ]
                }
            ]
        },
        offTimerRepeat: {
            id: "offTimerRepeat",
            title: "page.timer_repeat",
            subtitle: "detail.timer_repeat_off",
            sections: [{ rows: dayRows("time.offTimerWeekday") }]
        }
    }
};
