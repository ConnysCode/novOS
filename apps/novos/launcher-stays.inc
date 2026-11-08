
    // novOS: an overlay opening closes the home layer, LG's rule for its own home.
    // Our launcher lives there, and the quick menu and the source picker open on top
    // of it, as on a home screen, so it stays. It also stays when two minutes pass
    // without a key, which closes LG's Home. Every other rule stays LG's.
    function novosLauncherOnHome() {
        var home = views.starfishHome;
        return !!home && !!home.currentView && home.currentView.appId === "com.webos.app.store-streamer";
    }
