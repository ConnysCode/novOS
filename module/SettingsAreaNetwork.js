.pragma library

// Area 05 "Netzwerk" of the settings modal. The state comes from the host
// (connectionmanager/getStatus, wifi/getstatus), Wi-Fi runs through novOS' own flow
// in WifiSetup.qml. Manual IP and DNS stay in LG's network overlay, IP control in
// LG's installer app, both opened the way LG's settings open them.

function statusText(ctx) {
    var state = ctx.state.network;
    if (state === "wifi") {
        return ctx.t(ctx.state.online ? "detail.status_wifi_online" : "detail.status_wifi_offline",
                     { name: ctx.state.wifiName || "" });
    }
    if (state === "wired") {
        return ctx.t(ctx.state.online ? "detail.status_wired_online" : "detail.status_wired_offline");
    }
    return ctx.t("detail.status_none");
}

var area = {
    id: "network",
    icon: "network",
    title: "area.network",
    configs: ["tv.model.supportLAN"],
    page: {
        id: "network",
        title: "area.network",
        subtitle: statusText,
        sections: [
            {
                title: "section.connection",
                rows: [
                    { id: "wifi", type: "action", action: "wifiSetup", title: "row.wifi",
                      subtitle: function (ctx) {
                          return ctx.state.network === "wired" ? ctx.t("detail.cable_priority") : "";
                      },
                      value: function (ctx) {
                          return ctx.state.network === "wifi" ? ctx.state.wifiName || "" : ctx.t("value.not_connected");
                      },
                      search: "search.wifi" },
                    // WifiSetup asks before it forgets, with the focus on Cancel.
                    { id: "wifiForget", type: "action", action: "wifiForget", danger: true, title: "row.wifi_forget",
                      requires: function (ctx) { return ctx.state.network === "wifi" && ctx.state.wifiProfile > 0; } },
                    { id: "lan", type: "info", focusable: false, title: "row.lan",
                      requires: function (ctx) { return ctx.cfg("tv.model.supportLAN") !== false; },
                      value: function (ctx) {
                          return ctx.t(ctx.state.network === "wired" ? "value.connected" : "value.not_connected");
                      } }
                ]
            },
            {
                title: "section.details",
                rows: [
                    { id: "ipAddress", type: "info", focusable: false, title: "row.ip_address",
                      requires: function (ctx) { return ctx.state.network === "wifi" || ctx.state.network === "wired"; },
                      value: function (ctx) { return ctx.state.ipAddress || ""; } },
                    { id: "ipDns", type: "lgApp", title: "row.ip_dns", subtitle: "detail.ip_dns", search: "search.ip_dns",
                      app: { id: "com.webos.app.firstuse-overlay", params: { target: "network" } } },
                    { id: "tvName", type: "action", action: "tvName", title: "row.tv_name", subtitle: "detail.tv_name",
                      value: function (ctx) { return ctx.state.tvName || ""; }, search: "search.tv_name" }
                ]
            },
            {
                title: "section.advanced",
                rows: [
                    { id: "ipControl", type: "lgApp", title: "row.ip_control", subtitle: "detail.ip_control",
                      search: "search.ip_control",
                      app: { id: "com.webos.app.installation", params: {} } },
                    { id: "setId", type: "slider", key: "option.setId", title: "row.set_id", subtitle: "detail.set_id",
                      search: "search.ip_control" }
                ]
            }
        ]
    }
};
