import QtQuick 2.12
import WebOSServices 1.0
import "."

// The TV's profiles, as LG's accountmanager keeps them: one per LG account signed in on
// this TV, one of them active. Every window that shows profiles has one store. All calls
// are the ones LG's own account app makes (docs/profile-sign-in.md):
//
//   read      getLoginUserData { serviceName: "LGE", subscribe: true }
//   switch    loginAccount { mode: "accountSwitching", userNo, accountType: "LGE" }
//   edit      updateAccountData { userNo, userData: <whole userData, changed fields> }
//   sign out  logoutAccount { userNo, mode: "shallow" }
//   remove    deleteAccount { userNo }
//
// Editing changes only the TV's copy, never the LG account. With NovosSettings.demoProfiles
// two made-up profiles join the real one, and everything done to them stays in memory.
Item {
    id: store

    property bool demo: NovosSettings.demoProfiles

    // A profile: { userNo, id, nick, initial, tint, active, voiceId, autoSignIn, country,
    //              accountType, security, demo, data } (data is LG's userData as it came).
    property var active: null
    property var others: []
    readonly property var all: active ? [active].concat(others) : others
    property bool known: false
    property bool signedIn: active !== null

    // The profile being switched to while LG's apps and services follow, else null.
    property var switching: null
    property real switchStarted: 0

    // kind: "signedIn" (a profile new on this TV became active), "activeChanged" (someone
    // else switched), "signedOut", "removed", "switched" (a switch of this store), "failed"
    signal notice(string kind, var profile)

    property var lgData: null          // last answer of getLoginUserData
    property var demoState: null       // { active: userNo, list: [...] } once demo started

    readonly property string serviceUrl: "luna://com.webos.service.accountmanager"

    function request() {
        service.call(serviceUrl, "/getLoginUserData", JSON.stringify({ serviceName: "LGE", subscribe: true }));
    }

    // After a change: one plain read, the subscription stays the only one.
    function reread() {
        service.call(serviceUrl, "/getLoginUserData", JSON.stringify({ serviceName: "LGE" }));
    }

    Component.onCompleted: request()
    onDemoChanged: rebuild()

    // ---- reading -----------------------------------------------------------------------
    function profileOf(data, isActive) {
        if (!data || !data.userNumber) return null;
        var nick = String(data.profileNick || data.iconNick || data.userID || "");
        var tint = String(data.profileBg || GlassStyle.profileColors[0]).toUpperCase();
        return {
            userNo: String(data.userNumber), id: String(data.id || ""), nick: nick,
            initial: String(data.iconNick || nick).charAt(0).toUpperCase(), tint: tint,
            active: isActive === true, voiceId: data.useVoiceId === true,
            autoSignIn: data.autoSignIn !== false, country: String(data.countryCode || ""),
            accountType: String(data.accountType || ""), security: String(data.m_security || "notUseSecurity"),
            defaultNick: data.defaultNick === true, demo: false, data: data
        };
    }

    function demoProfiles() {
        return [
            { userNo: "demo-lea", id: "", nick: "Lea", initial: "L", tint: "#3DA287", active: false, voiceId: true,
              autoSignIn: true, country: "DE", accountType: "LGE", security: "notUseSecurity", demo: true, data: null },
            { userNo: "demo-jonas", id: "", nick: "Jonas", initial: "J", tint: "#F27121", active: false, voiceId: false,
              autoSignIn: true, country: "DE", accountType: "GGL", security: "notUseSecurity", demo: true, data: null,
              expired: true }
        ];
    }

    function rebuild() {
        var list = [];
        var current = null;
        if (lgData) {
            current = profileOf(lgData.userData, true);
            var more = lgData.multipleLoginUserData || [];
            for (var i = 0; i < more.length; i++) {
                var other = profileOf(more[i], false);
                if (other && (!current || other.userNo !== current.userNo)) list.push(other);
            }
        }
        if (demo) {
            // A stand-in made before LG answered gives way to the real profile.
            if (demoState !== null && demoState.standIn && current) demoState = null;
            if (demoState === null) {
                var start = demoProfiles();
                if (!current) {
                    current = { userNo: "demo-morian", id: "", nick: "Morian", initial: "M", tint: "#339BDD",
                                active: true, voiceId: true, autoSignIn: true, country: "DE", accountType: "LGE",
                                security: "notUseSecurity", demo: true, data: null };
                }
                demoState = { active: current.userNo, list: [current].concat(list, start),
                              standIn: current.demo === true };
            }
            var everyone = demoState.list;
            current = null;
            list = [];
            for (var j = 0; j < everyone.length; j++) {
                var entry = copy(everyone[j]);
                entry.active = entry.userNo === demoState.active;
                if (entry.active) current = entry;
                else list.push(entry);
            }
        } else {
            demoState = null;
        }
        active = current;
        others = list;
    }

    function copy(profile) {
        var result = {};
        for (var key in profile) result[key] = profile[key];
        return result;
    }

    function byNumber(userNo) {
        var everyone = all;
        for (var i = 0; i < everyone.length; i++) {
            if (everyone[i].userNo === userNo) return everyone[i];
        }
        return null;
    }

    // ---- changing ----------------------------------------------------------------------
    function switchTo(userNo) {
        var target = byNumber(userNo);
        if (!target || target.active || switching) return;
        switching = target;
        switchStarted = Date.now();
        if (target.demo || (active && active.demo)) {
            demoSwitch.restart();
            return;
        }
        service.call(serviceUrl, "/loginAccount", JSON.stringify({
            serviceName: "LGE", accountType: "LGE", mode: "accountSwitching", userNo: userNo }));
        switchGiveUp.restart();
    }

    function finishSwitch(ok) {
        var target = switching;
        switching = null;
        switchGiveUp.stop();
        notice(ok ? "switched" : "failed", target);
    }

    function update(userNo, nick, tint) {
        var target = byNumber(userNo);
        if (!target) return;
        var name = String(nick).trim() || target.nick;
        if (target.demo) {
            changeDemo(userNo, { nick: name, initial: name.charAt(0).toUpperCase(), tint: tint });
            return;
        }
        var data = copy(target.data);
        data.profileNick = name;
        data.iconNick = name.charAt(0);
        data.profileBg = tint;
        data.defaultNick = false;
        service.call(serviceUrl, "/updateAccountData", JSON.stringify({ serviceName: "LGE", userNo: userNo, userData: data }));
    }

    function setAutoSignIn(userNo, on) {
        var target = byNumber(userNo);
        if (!target) return;
        if (target.demo) {
            changeDemo(userNo, { autoSignIn: on });
            return;
        }
        var data = copy(target.data);
        data.autoSignIn = on;
        service.call(serviceUrl, "/updateAccountData", JSON.stringify({ serviceName: "LGE", userNo: userNo, userData: data }));
    }

    function signOut(userNo) {
        var target = byNumber(userNo);
        if (!target) return;
        if (target.demo) {
            dropDemo(userNo);
            notice("signedOut", target);
            return;
        }
        pendingNotice = { kind: "signedOut", profile: target };
        service.call(serviceUrl, "/logoutAccount", JSON.stringify({ serviceName: "LGE", userNo: userNo, mode: "shallow" }));
    }

    function remove(userNo) {
        var target = byNumber(userNo);
        if (!target) return;
        if (target.demo) {
            dropDemo(userNo);
            notice("removed", target);
            return;
        }
        pendingNotice = { kind: "removed", profile: target };
        service.call(serviceUrl, "/deleteAccount", JSON.stringify({ serviceName: "LGE", userNo: userNo }));
    }

    property var pendingNotice: null

    function changeDemo(userNo, fields) {
        if (!demoState) return;
        var list = demoState.list.map(function (entry) {
            if (entry.userNo !== userNo) return entry;
            var changed = copy(entry);
            for (var key in fields) changed[key] = fields[key];
            return changed;
        });
        demoState = { active: demoState.active, list: list, standIn: demoState.standIn };
        rebuild();
    }

    function dropDemo(userNo) {
        if (!demoState) return;
        var list = demoState.list.filter(function (entry) { return entry.userNo !== userNo; });
        var current = demoState.active;
        if (current === userNo) current = list.length > 0 ? list[0].userNo : "";
        demoState = { active: current, list: list, standIn: demoState.standIn };
        rebuild();
    }

    Timer {
        id: demoSwitch
        interval: 1400
        onTriggered: {
            if (!store.switching) return;
            if (store.demoState) store.demoState = { active: store.switching.userNo, list: store.demoState.list,
                                                     standIn: store.demoState.standIn };
            store.rebuild();
            store.finishSwitch(true);
        }
    }

    // LG forces a switch after its own deadline; this one only frees the screen.
    Timer {
        id: switchGiveUp
        interval: 20000
        onTriggered: if (store.switching) store.finishSwitch(false)
    }

    Service {
        id: service
        appId: "com.webos.app.quicksettings"
        onResponse: {
            var response = JSON.parse(payload);
            if (method === "/getLoginUserData") {
                if (response.returnValue === false) return;
                var before = store.active ? store.active.userNo : "";
                var knownBefore = store.all.map(function (profile) { return profile.userNo; });
                store.lgData = response;
                store.known = true;
                store.rebuild();
                var after = store.active ? store.active.userNo : "";
                if (store.switching && !store.switching.demo && after === store.switching.userNo) store.finishSwitch(true);
                else if (store.primed && !store.switching && after !== "" && after !== before) {
                    store.notice(knownBefore.indexOf(after) >= 0 ? "activeChanged" : "signedIn", store.active);
                }
                store.primed = true;
            } else if (method === "/loginAccount") {
                if (response.returnValue === false && store.switching) store.finishSwitch(false);
            } else if (method === "/logoutAccount" || method === "/deleteAccount") {
                var waiting = store.pendingNotice;
                store.pendingNotice = null;
                if (waiting) store.notice(response.returnValue === false ? "failed" : waiting.kind, waiting.profile);
                store.reread();
            } else if (method === "/updateAccountData") {
                store.reread();
            }
        }
        onError: {
            if (method === "/loginAccount" && store.switching) store.finishSwitch(false);
        }
    }

    property bool primed: false
}
