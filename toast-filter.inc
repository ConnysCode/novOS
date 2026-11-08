
        // novOS: toasts and plain dialogs stay away while banner-relay.py runs, because the
        // source picker's window shows them. Without the marker of a test mount LG's views
        // come back. Dialogs with a progress bar, a check box or a full screen stay LG's.
        function novosActive() {
            try {
                var request = new XMLHttpRequest();
                request.open("GET", "file:///tmp/novos-banner-active", false);
                request.send();
                return request.responseText.indexOf("on") === 0;
            } catch (error) {
                return false;
            }
        }

        // While novos-start.sh restarts the interface the relay does not run yet: LG's
        // toasts (QMS-VRR and the like) are dropped then, dialogs are not.
        function novosBooting() {
            try {
                var request = new XMLHttpRequest();
                request.open("GET", "file:///tmp/novos-booting", false);
                request.send();
                var parts = request.responseText.split(" ");
                return parts[0] === "on" && Date.now() / 1000 - Number(parts[1]) < 180;
            } catch (error) {
                return false;
            }
        }

        function replacedByPill(toast) {
            return novosActive() || novosBooting();
        }

        function replacedAlert(alert) {
            if (alert.type === "progress" || alert.type === "spinner" || alert.type === "warning") return false;
            if (alert.checkButton || alert.thumbnailPath) return false;
            if ((alert.buttons || []).length > 3) return false;
            return novosActive();
        }
