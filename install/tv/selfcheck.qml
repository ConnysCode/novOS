import QtQuick 2.12
import Qt.labs.settings 1.0
import SystemUIComponent 1.0

// Compile check of a release, started by novos-start.sh inside the running
// surface-manager before anything is mounted, as LG's StoreStreamer window. A broken file would otherwise leave
// a window that never opens, a dead home key or no notices, and nothing would notice.
// The window never shows: it writes its verdict and exits.
//
// surface-manager caches components by URL, so every check runs from a folder of its
// own in /tmp: novos-start.sh copies this file there and fills in @RELEASE@. Releases
// themselves never change after the install, their URLs may stay cached.
StarfishSystemUIWindow {
    id: checkWindow

    // Services.qml and the compositor's container need LG's files beside them:
    // novos-start.sh builds those folders from symlinks.
    readonly property var files: [
        "file://@RELEASE@/QuickSettings.qml",
        "file://@RELEASE@/InputPicker.qml",
        "file://@RELEASE@/StoreStreamer.qml",
        Qt.resolvedUrl("selfcheck-keys.qml"),
        Qt.resolvedUrl("notification/Services.qml"),
        Qt.resolvedUrl("compositor/views/fullscreen/StarfishFullscreenContainer.qml"),
        Qt.resolvedUrl("compositor/views/StarfishImageSplash.qml"),
        Qt.resolvedUrl("compositor/views/StarfishVolumeView.qml"),
        Qt.resolvedUrl("compositor/views/systemUi/StarfishSystemUIManager.qml"),
        Qt.resolvedUrl("compositor/controllers/StarfishViewStateController.qml")
    ]
    property var components: []
    property int waited: 0

    Settings {
        id: result
        fileName: "/tmp/novos-selfcheck.ini"
        property string verdict: ""
        property string detail: ""
    }

    function finish() {
        var errors = [];
        for (var i = 0; i < components.length; ++i) {
            var component = components[i];
            if (component.status === Component.Ready) continue;
            var name = String(files[i]).split("/").pop();
            errors.push(name + ": " + (component.status === Component.Error ?
                                       component.errorString() : "status " + component.status));
        }
        result.detail = errors.join(" | ").replace(/\s+/g, " ");
        result.verdict = errors.length > 0 ? "fail" : "ok";
        closeTimer.start();
    }

    Timer {
        id: pollTimer
        interval: 100
        repeat: true
        onTriggered: {
            checkWindow.waited += interval;
            var loading = false;
            for (var i = 0; i < checkWindow.components.length; ++i) {
                if (checkWindow.components[i].status === Component.Loading) loading = true;
            }
            if (!loading || checkWindow.waited >= 8000) {
                stop();
                checkWindow.finish();
            }
        }
    }

    // Long enough for Settings to write the verdict before the window goes.
    Timer {
        id: closeTimer
        interval: 1500
        onTriggered: checkWindow.exit()
    }

    Component.onCompleted: {
        var list = [];
        for (var i = 0; i < files.length; ++i) list.push(Qt.createComponent(files[i]));
        components = list;
        pollTimer.start();
    }
}
