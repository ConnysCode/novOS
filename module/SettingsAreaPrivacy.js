.pragma library

// Area 10, Datenschutz & Werbung. Every ad and tracking switch of LG in one place, also the
// two keys LG shows in no menu (option.webOSPromotionVideo, option.watchedListCollection).
// Writes are the ones of LG's settings app (com.palm.app.settings, Support › Datenschutz,
// System › Zusätzliche Einstellungen, Allgemein › AI-Dienst, Sender › HbbTV).
// Nothing here switches anything off by itself: defaults at setup belong to the installer.

var area = {
    id: "privacy",
    icon: "privacy",
    title: "area.privacy",
    // general.adCookie gates LG's "Werbung" page, LG never writes it. nativeConsentAd gates the
    // CMP entry.
    keys: ["general.adCookie", "general.nativeConsentAd", "option.livePlus"],
    page: {
        id: "privacy",
        title: "area.privacy",
        subtitle: "detail.privacy",
        sections: [
            {
                title: "section.advertising",
                rows: [
                    { id: "advertising", type: "page", page: "advertising",
                      title: "row.personalized_ads", subtitle: "detail.personalized_ads",
                      summary: ["general.lmt"], search: "search.personalized_ads",
                      requires: function (ctx) { return ctx.has("general.adCookie"); } },
                    { id: "homePromotion", type: "toggle", key: "general.homePromotion",
                      title: "row.home_promotion", search: "search.home_promotion" },
                    { id: "screenSaverAd", type: "toggle", key: "general.screenSaverAd",
                      title: "row.screen_saver_ad", search: "search.screen_saver_ad" },
                    { id: "livePlus", type: "toggle", key: "option.livePlus",
                      title: "row.live_plus", subtitle: "detail.live_plus", search: "search.live_plus" },
                    { id: "livePromotion", type: "toggle", key: "option.livePromotion",
                      title: "row.live_promotion", search: "search.live_promotion",
                      disabled: [{ when: function (ctx) { return ctx.val("option.livePlus") !== "on"; },
                                   reason: "reason.live_plus_off" }] },
                    // No LG menu. The key exists in LG's settings schema and is "on" by default.
                    { id: "promotionVideo", type: "toggle", key: "option.webOSPromotionVideo",
                      title: "row.promotion_video", subtitle: "detail.promotion_video",
                      search: "search.promotion_video" }
                ]
            },
            {
                title: "section.recommendation",
                rows: [
                    { id: "contentRecommendation", type: "toggle", key: "other.contentRecommendation",
                      title: "row.content_recommendation", search: "search.content_recommendation" },
                    { id: "smartTips", type: "toggle", key: "general.aiNudge",
                      title: "row.smart_tips", search: "search.smart_tips" },
                    { id: "smartTipsSettings", type: "toggle", key: "general.aiSettingsNudge",
                      title: "row.smart_tips_settings", search: "search.smart_tips" },
                    // LG: AI-Empfehlungen › Who.Where.What? Hidden by the descriptor where it
                    // does not exist.
                    { id: "broadcastInfo", type: "toggle", key: "option.broadcastInfoNoti",
                      title: "row.broadcast_info", search: "search.broadcast_info" }
                ]
            },
            {
                title: "section.data",
                rows: [
                    // No LG menu.
                    { id: "watchedList", type: "toggle", key: "option.watchedListCollection",
                      title: "row.watched_list", subtitle: "detail.watched_list",
                      search: "search.watched_list" },
                    // US only, the descriptor hides it elsewhere.
                    { id: "doNotSell", type: "toggle", key: "general.doNotSellMyPersonalInformation",
                      title: "row.do_not_sell", search: "search.do_not_sell" },
                    { id: "permissions", type: "page", page: "permissions",
                      title: "row.app_permissions", subtitle: "detail.app_permissions",
                      search: "search.app_permissions" },
                    { id: "hbbtv", type: "page", page: "hbbtv",
                      title: "row.hbbtv", summary: ["option.hbbTvDnt"], search: "search.hbbtv" },
                    // LG: Datenschutz › Meine persönlichen Informationen löschen. LG deletes
                    // through usercontextmanager, thinqai and userintentmanager with the LG
                    // device id and needs the network, so it stays LG's page.
                    { id: "deleteData", type: "lgApp",
                      app: { id: "com.palm.app.settings", params: { target: "DeletePersonalInfo" } },
                      title: "row.delete_personal_info", search: "search.delete_personal_info" }
                ]
            },
            {
                title: "section.agreement",
                rows: [
                    { id: "agreements", type: "lgApp",
                      app: { id: "com.webos.app.firstuse-overlay", params: { target: "eula", context: "all" } },
                      title: "row.user_agreements", search: "search.user_agreements" },
                    // LG: luna://com.webos.service.admanager/launchCMPApp {"forceStatus": true},
                    // only with network.
                    { id: "cmp", type: "action", action: "cmpSettings",
                      title: "row.cmp_settings", subtitle: "detail.cmp_settings", search: "search.cmp_settings",
                      requires: function (ctx) { return ctx.has("general.nativeConsentAd"); },
                      disabled: [{ when: function (ctx) { return ctx.state.online !== true; },
                                   reason: "reason.needs_internet" }] },
                    // Voice ID and personalized AI live in LG's voice settings; the same row
                    // stands under System › Sprachsteuerung.
                    { id: "voiceId", type: "lgApp",
                      app: { id: "com.webos.app.aiplatformsupport",
                             params: { activateType: "view", launchMode: "settings", caller: "com.palm.app.settings" } },
                      title: "row.voice_id", subtitle: "detail.voice_id", search: "search.voice_id",
                      requires: function (ctx) { return ctx.state.voiceAvailable === true; } }
                ]
            }
        ]
    },
    pages: {
        advertising: {
            id: "advertising",
            title: "page.advertising",
            subtitle: "detail.advertising",
            sections: [
                {
                    rows: [
                        // luna://com.webos.service.sm/deviceid/getIDs {"idType": ["IFAID"], "origin": "read"}.
                        // Some TVs answer "Unsupported device ID type"; then both rows stay away.
                        { id: "adId", type: "info", focusable: false, title: "row.ad_id",
                          value: function (ctx) { return ctx.state.adId || ""; },
                          requires: function (ctx) { return !!ctx.state.adId; } },
                        // luna://com.webos.service.admanager/resetIFA {}, then read the id again.
                        { id: "resetAdId", type: "action", action: "resetAdId",
                          requires: function (ctx) { return !!ctx.state.adId; },
                          title: "row.reset_ad_id", subtitle: "detail.reset_ad_id", search: "search.reset_ad_id",
                          confirm: { title: "confirm.reset_ad_id_title", text: "confirm.reset_ad_id_text",
                                     confirm: "confirm.reset_ad_id_button" } },
                        { id: "limitTracking", type: "toggle", key: "general.lmt",
                          title: "row.limit_ad_tracking", subtitle: "detail.limit_ad_tracking",
                          search: "search.limit_ad_tracking" }
                    ]
                }
            ]
        },
        permissions: {
            id: "permissions",
            title: "page.app_permissions",
            subtitle: "detail.permissions_page",
            sections: [
                {
                    rows: [
                        { id: "camera", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "Camera" } },
                          title: "row.camera", search: "search.camera" },
                        { id: "microphone", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "MicroPhone" } },
                          title: "row.microphone", search: "search.microphone" },
                        { id: "nearby", type: "lgApp",
                          app: { id: "com.palm.app.settings", params: { target: "NearbyDevice" } },
                          title: "row.nearby_devices", search: "search.nearby_devices" }
                    ]
                }
            ]
        },
        hbbtv: {
            id: "hbbtv",
            title: "page.hbbtv",
            subtitle: "detail.hbbtv",
            sections: [
                {
                    rows: [
                        // LG writes "on"/"off". The key has a value but no descriptor on
                        // 10.3.2, so it needs descOptional.
                        { id: "doNotTrack", type: "toggle", key: "option.hbbTvDnt", descOptional: true,
                          title: "row.do_not_track", subtitle: "detail.do_not_track", search: "search.do_not_track" },
                        { id: "deviceId", type: "toggle", key: "option.hbbTvDeviceId",
                          onValues: ["on", "onByUser"],
                          title: "row.hbbtv_device_id", subtitle: "detail.hbbtv_device_id",
                          search: "search.hbbtv_device_id" },
                        // luna://com.webos.service.wampluggable.hbbtv/resetDeviceId {}
                        { id: "resetDeviceId", type: "action", action: "resetHbbtvId",
                          title: "row.reset_hbbtv_id", subtitle: "detail.reset_hbbtv_id",
                          requires: function (ctx) { return ctx.has("option.hbbTvDeviceId"); },
                          confirm: { title: "confirm.reset_hbbtv_id_title", text: "detail.reset_hbbtv_id",
                                     confirm: "confirm.reset_button" } },
                        // LG writes "onByUser"/"offByUser" and reads "on" and "onByUser" as on.
                        { id: "thirdPartyCookie", type: "toggle", key: "option.thirdPartyCookie",
                          on: "onByUser", off: "offByUser", onValues: ["on", "onByUser"],
                          title: "row.third_party_cookie", search: "search.third_party_cookie" },
                        // luna://com.webos.service.wampluggable.hbbtv/resetDialConnection {}
                        { id: "connectionHistory", type: "action", action: "resetHbbtvConnections",
                          title: "row.delete_connection_history", subtitle: "detail.delete_connection_history",
                          requires: function (ctx) { return ctx.has("option.hbbTvDeviceId"); },
                          confirm: { title: "row.delete_connection_history", text: "detail.delete_connection_history",
                                     confirm: "confirm.delete_button", danger: true } }
                    ]
                }
            ]
        }
    }
};
