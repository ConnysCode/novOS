.pragma library

// Area "Profile" (K3-Profil-Einst, K3-Profil-Einst-Ganz), between Datenschutz and System.
// A profile is an LG account signed in on this TV (docs/profile-functions.md). On top the
// active profile, then every profile on this TV (OK switches, the active one carries
// "Aktiv"), adding one, everything about the active profile, and at the bottom its data,
// signing out and removing it. The lists and actions come from the host's ProfileStore
// (SettingsData.qml); the calls are LG's own (docs/profile-sign-in.md).
//
// Pages of their own: "edit" (name and colour, ProfileEdit.qml) and "signIn" (a code from
// LG for a phone, ProfileSignIn.qml with bin/novos-login.py).

function active(ctx) {
    return ctx.state.profileActive || null;
}

function signedIn(ctx) {
    return active(ctx) !== null;
}

function nameOf(ctx) {
    var profile = active(ctx);
    return profile ? profile.nick : "";
}

var area = {
    id: "profile",
    icon: "profile",
    title: "area.profile",
    page: {
        id: "profile",
        title: "area.profile",
        sections: [
            {
                rows: [
                    // The active profile as a card; signing in when there is none.
                    { id: "active", type: "list", source: "profileActive" },
                    { id: "signInFirst", type: "page", page: "signIn", title: "row.sign_in",
                      subtitle: "detail.sign_in", search: "search.add",
                      requires: function (ctx) { return ctx.state.profileKnown === true && !signedIn(ctx); } }
                ]
            },
            {
                title: "section.on_tv",
                rows: [
                    { id: "profiles", type: "list", source: "profiles" },
                    { id: "add", type: "page", page: "signIn", title: "row.add", search: "search.add",
                      requires: signedIn }
                ]
            },
            {
                title: nameOf,
                rows: [
                    { id: "edit", type: "page", page: "edit", title: "row.edit", subtitle: "detail.edit",
                      search: "search.edit", requires: signedIn },
                    { id: "voiceId", type: "page", page: "voice", title: "row.voice_id",
                      value: function (ctx) {
                          var profile = active(ctx);
                          return ctx.t(profile && profile.voiceId ? "value.voice_recorded" : "value.voice_none");
                      },
                      search: "search.voice_id",
                      requires: function (ctx) { return signedIn(ctx) && ctx.state.voiceAvailable === true; } },
                    { id: "autoSignIn", type: "toggle", action: "profileAutoSignIn", title: "row.auto_sign_in",
                      subtitle: function (ctx) { return ctx.t("detail.auto_sign_in", { name: nameOf(ctx) }); },
                      isOn: function (value, ctx) { var profile = active(ctx); return !!profile && profile.autoSignIn; },
                      search: "search.auto_sign_in", requires: signedIn },
                    // Country, linked LG services and the sign-in history stay LG's page.
                    { id: "account", type: "lgApp", app: { id: "com.webos.app.membership", params: {} },
                      title: "row.account", subtitle: "detail.account", search: "search.account",
                      requires: signedIn }
                ]
            },
            {
                title: "section.data",
                note: "detail.belongs",
                rows: [
                    // As under Datenschutz: LG deletes through its own services with the device id.
                    { id: "deleteData", type: "lgApp",
                      app: { id: "com.palm.app.settings", params: { target: "DeletePersonalInfo" } },
                      title: "row.delete_data", search: "search.delete_data", requires: signedIn },
                    { id: "signOut", type: "action", action: "profileSignOut", title: "row.sign_out",
                      search: "search.sign_out", requires: signedIn,
                      paramsOf: function (ctx) { return { userNo: active(ctx) ? active(ctx).userNo : "" }; },
                      confirm: { title: "confirm.sign_out_title", text: "confirm.sign_out_text",
                                 confirm: "button.sign_out",
                                 params: function (ctx) { return { name: nameOf(ctx) }; } } },
                    { id: "remove", type: "action", action: "profileRemove", title: "row.remove", danger: true,
                      search: "search.remove", requires: signedIn,
                      paramsOf: function (ctx) { return { userNo: active(ctx) ? active(ctx).userNo : "" }; },
                      confirm: { title: "confirm.remove_title", text: "confirm.remove_text",
                                 confirm: "button.remove", safe: true,
                                 params: function (ctx) { return { name: nameOf(ctx) }; } } }
                ]
            }
        ]
    },
    pages: {
        edit: {
            id: "edit",
            title: "row.edit",
            subtitle: function (ctx) { return ctx.t("detail.local_only"); },
            custom: "profileEdit",
            sections: []
        },
        // Voice ID (K3-Profil-Einst-StimmID). Recording and deleting are LG's voice app.
        voice: {
            id: "voice",
            title: "row.voice_id",
            sections: [
                {
                    rows: [
                        { id: "voiceState", type: "info", focusable: false,
                          title: function (ctx) {
                              var profile = active(ctx);
                              return ctx.t(profile && profile.voiceId ? "voice.recorded" : "voice.none",
                                           { name: nameOf(ctx) });
                          },
                          subtitle: "voice.detail" },
                        { id: "voiceRecord", type: "lgApp",
                          app: { id: "com.webos.app.aiplatformsupport",
                                 params: { activateType: "view", launchMode: "settings", caller: "com.palm.app.settings" } },
                          title: function (ctx) {
                              var profile = active(ctx);
                              return ctx.t(profile && profile.voiceId ? "voice.record_again" : "voice.record");
                          },
                          subtitle: "voice.record_detail" }
                    ]
                }
            ]
        },
        signIn: {
            id: "signIn",
            title: "signin.title",
            subtitle: function (ctx) { return ctx.t("signin.subtitle"); },
            custom: "profileSignIn",
            sections: []
        }
    }
};
