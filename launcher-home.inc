
        // novOS: our launcher, LG's StoreStreamer window, lives on the compositor's home
        // layer below the overlays while the relay's marker is on. The quick menu and
        // the source picker then open on top of it instead of replacing it, as on a
        // real home screen. Without the marker it stays an overlay as LG configured it.
        function novosLauncherHome(ev) {
            if (ev.appId !== "com.webos.app.store-streamer" || ev.payload.main) return false;
            try {
                var request = new XMLHttpRequest();
                request.open("GET", "file:///tmp/novos-banner-active", false);
                request.send();
                return request.responseText.indexOf("on") === 0;
            } catch (error) {
                return false;
            }
        }

