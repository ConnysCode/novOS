<script type="text/javascript">
// novOS: LG's settings app opened without a target (from an app, from Home, from the
// long press of the gear key) hands over to novOS's settings modal and closes. A launch
// with a target, such as the deep links of the modal itself, stays in LG's app. A start
// in the background (LG prerenders this app) does nothing until the app becomes visible.
(function () {
    var handing = false;
    function launchParams() {
        try {
            return JSON.parse((window.PalmSystem && window.PalmSystem.launchParams) || "{}") || {};
        } catch (error) {
            return {};
        }
    }
    function handOver() {
        if (handing || document.hidden || typeof PalmServiceBridge === "undefined") return;
        var params = launchParams();
        if (params.target || params.path || params.item || params.id || params.page) return;
        handing = true;
        try {
            var bridge = new PalmServiceBridge();
            // LG's app closes only once novOS's modal took the launch; otherwise it stays.
            bridge.onservicecallback = function (message) {
                var answer = {};
                try { answer = JSON.parse(message); } catch (error) {}
                if (answer.returnValue === true) window.close();
                else handing = false;
            };
            bridge.call("luna://com.webos.service.systemUIManager/launch",
                        JSON.stringify({ appId: "com.webos.app.quicksettings", params: { page: "settings" } }));
        } catch (error) {
            handing = false;
        }
    }
    document.addEventListener("visibilitychange", function () {
        if (document.hidden) handing = false;
        else handOver();
    });
    document.addEventListener("webOSRelaunch", function () { setTimeout(handOver, 0); });
    window.addEventListener("load", function () { setTimeout(handOver, 0); });
})();
</script>
