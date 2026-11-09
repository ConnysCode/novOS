import QtQuick 2.12
import QtQml 2.12
import WebOSServices 1.0
import "."
import "GameMode.js" as GameMode

// What the game bar needs from the TV beyond the shared settings store.
//
// check() asks, in five small calls, whether the gear key opens the bar (LG's rule in
// GameMode.js) and answers with decided() once all are in, or with false after
// checkTimeout. live runs the frame rate and VRR subscription of the game input, as LG's
// dashboard does (utp.extinputs: bind, then getVRRInfo every second); it ends with live.
Item {
    id: status

    property string appId: "com.webos.app.quicksettings"
    property bool live: false

    // The result of the last check.
    property bool checking: false
    property var settings: ({})
    property var foreground: []
    property var multiview: null
    readonly property string gameInput: settings.gameInput || ""

    // Live values; -1 and "" while the TV has not answered.
    property int frameRate: -1
    property string vrrType: ""
    property string pipelineId: ""
    property string liveError: ""             // the last refusal of utp.extinputs, for the preview

    readonly property int checkTimeout: 400
    readonly property int vrrInterval: 1000
    property int answers: 0
    readonly property int expectedAnswers: 5

    signal decided(bool game)

    function check() {
        checking = true;
        answers = 0;
        settings = {};
        foreground = [];
        multiview = null;
        checkTimer.restart();
        call(checkService, "luna://com.webos.settingsservice", "/getSystemSettings",
             { category: "other", keys: ["gameMode", "enableQuickGame"] });
        call(checkService, "luna://com.webos.settingsservice", "/getSystemSettings",
             { category: "picture", keys: ["pictureMode"] });
        call(checkService, "luna://com.webos.settingsservice", "/getSystemSettings",
             { category: "sound", keys: ["soundMode"] });
        call(checkService, "luna://com.webos.applicationManager", "/getForegroundAppInfo", { extraInfo: true });
        call(checkService, "luna://com.webos.service.multiviewcontroller", "/getStatus", {});
    }

    function finish(game) {
        if (!checking) return;
        checking = false;
        checkTimer.stop();
        decided(game);
    }

    function answer(method, response) {
        if (!checking) return;
        var next = {};
        for (var name in settings) next[name] = settings[name];
        if (method === "/getSystemSettings") {
            var values = response.settings || {};
            if (response.category === "other") {
                next.gameMode = values.gameMode;
                next.enableQuickGame = values.enableQuickGame;
                next.gameInput = response.dimension ? response.dimension.gameInput : "";
            } else if (response.category === "picture") {
                next.pictureMode = values.pictureMode;
            } else if (response.category === "sound") {
                next.soundMode = values.soundMode;
            }
            settings = next;
        } else if (method === "/getForegroundAppInfo") {
            var apps = response.foregroundAppInfo || [];
            var ids = [];
            for (var i = 0; i < apps.length; i++) ids.push(apps[i].appId);
            if (ids.length === 0 && response.appId) ids.push(response.appId);
            foreground = ids;
        } else if (method === "/getStatus") {
            multiview = response.status || null;
        }
        answers++;
        if (answers >= expectedAnswers) finish(GameMode.isGameMode(settings, foreground, multiview));
    }

    // Multi View side by side, as LG's dashboard starts it.
    function launchMultiView() {
        call(actionService, "luna://com.webos.service.multiviewcontroller", "/launchMode",
             { mode: "sxs", usageType: "normal" });
    }

    function call(service, uri, method, params) {
        service.call(uri, method, JSON.stringify(params));
    }

    Timer {
        id: checkTimer
        interval: status.checkTimeout
        onTriggered: status.finish(false)
    }

    Service {
        id: checkService
        appId: status.appId
        onResponse: status.answer(method, JSON.parse(payload))
        onError: status.answer(method, {})
    }

    Service {
        id: actionService
        appId: status.appId
    }

    onLiveChanged: {
        if (!live) {
            frameRate = -1;
            vrrType = "";
            pipelineId = "";
            liveError = "";
        }
    }

    // The subscription lives as long as the instantiator holds its service: leaving live
    // destroys it, which ends the subscription on the bus. (A Loader takes only items.)
    Instantiator {
        active: status.live
        delegate: Service {
            id: liveService
            appId: status.appId
            // As LG's panel did on every press of the gear key: no parameters.
            Component.onCompleted: call("luna://com.webos.service.utp.extinputs", "/bind", "{}")
            onResponse: {
                var response = JSON.parse(payload);
                if (response.returnValue === false) {
                    status.liveError = method + " " + (response.errorText || response.errorCode || "");
                    return;
                }
                if (method === "/bind") {
                    status.pipelineId = response.binded ? (response.broadcastId || "") : "";
                    if (status.pipelineId === "") return;
                    call("luna://com.webos.service.utp.extinputs", "/getVRRInfo",
                         JSON.stringify({ pipelineId: status.pipelineId, mode: "GameOptimizer",
                                          interval: status.vrrInterval, subscribe: true }));
                } else if (method === "/getVRRInfo" && response.vrrInfo) {
                    var rate = Number(response.vrrInfo.frameRate);
                    status.frameRate = isNaN(rate) ? -1 : Math.round(rate);
                    status.vrrType = response.vrrInfo.vrrType || "";
                }
            }
            onError: status.liveError = method + " " + errorText
        }
    }
}
