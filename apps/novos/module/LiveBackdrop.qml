import QtQuick 2.12
import QtGraphicalEffects 1.12
import WebOSServices 1.0
import "."

// The picture behind the glass: live video where the TV gives it, screenshots
// otherwise. Blurred, calmed over time and graded on a tiny image, so that every
// glass surface of a window only samples one small texture. Shared by the panel
// and the source picker, which are separate windows.
Item {
    id: chain

    property real unit: 1
    property rect area: Qt.rect(0, 0, 0, 0)     // the part of the screen behind the glass
    property real margin: 56 * unit
    property bool opened: false
    property bool shown: false                  // start video once the window stands
    property bool closing: false
    property string framePrefix: "/tmp/novos-quicksettings-frame-"
    // Dimming between the picture and the glass beyond the content scrim, such as behind
    // a modal. Applied after the temporal smoothing, so it changes at once.
    property real veil: 0

    readonly property variant texture: gradedBackdrop
    readonly property rect crop: Qt.rect(area.x - margin, area.y - margin,
                                         area.width + 2 * margin, area.height + 2 * margin)

    signal ready()                              // the window may open now

    readonly property real blurSigma: GlassStyle.blur * unit
    readonly property int backdropDownscale: 8
    readonly property size captureSize: Qt.size(480, 270)
    readonly property size decodeSize: Qt.size(240, 135)    // averages fine detail away
    readonly property size stillSize: Qt.size(768, 432)     // twice the preview box
    readonly property int minFrameBytes: 3000    // an empty frame is smaller
    readonly property int maxEmptyFrames: 10     // then the picture counts as lost
    readonly property int retryDelay: 220
    readonly property int glassSettleDelay: 120
    readonly property real glassTimeConstant: 280   // ms, smooths screenshot steps
    readonly property real videoTimeConstant: 70    // ms, only calms live video
    readonly property int videoStartTimeout: 3000
    readonly property int videoStallTimeout: 1500

    // The screen the TV reports video positions in, see videooutput/getStatus.
    readonly property size videoScreen: Qt.size(3840, 2160)
    readonly property real videoCoverage: 0.98  // share of the glass the app video must cover

    property bool hasFrame: false
    property bool liveBackdrop: false           // live video runs behind the glass
    property bool videoSource: false            // HDMI, Live TV and the other inputs
    property bool appVideo: false               // an app plays video behind the glass
    // The app's video is protected and the TV gives out only black. The glass then
    // shows the fixed surface of K3-Wechsel-Geschuetzt: hasFrame stays false.
    property bool protectedVideo: false
    property bool videoProbed: false
    property bool probingVideo: false
    property bool captureRunning: false
    property bool glassSettled: false
    property bool videoFailed: false
    property int emptyFrames: 0
    property int activeLayer: 1
    property bool waitingForApp: false
    property bool pictureReady: false           // the current picture is on the glass
    property bool joinedFeed: false
    property string foreground: ""
    property bool keepStill: false              // the source picker keeps a picture per source
    property bool stillsOnly: false             // no live feed: the signal is about to change
    property bool stillTaken: false
    property bool stillRunning: false
    // Keeps the picture on the glass and takes no new ones, for a surface that stands
    // long, like the mute chip. Set only through pause() and resume().
    property bool paused: false

    readonly property string shadowShader: GlassStyle.shadowShader

    // Glass material, shared by the panel and the popover. All layers sit in
    // one pass so the edge lights follow the rounded shape.
    readonly property string glassShader: GlassStyle.glassShader

    // Two frame layers, so loading a frame never blanks the visible one.
    // Each frame is blurred once when it arrives.
    // The crop and blur run at one eighth resolution.
    Repeater {
        id: frameLayers
        model: 2

        Item {
            readonly property int layerIndex: index
            property alias frame: frameImage
            property alias blurred: blurredFrame
            width: chain.width
            height: chain.height

            // Only the leaves are hidden. Qt skips a hidden parent's whole
            // subtree, and the blur chain would stay black.
            Image {
                id: frameImage
                anchors.fill: parent
                visible: false
                sourceSize: chain.decodeSize
                asynchronous: true
                cache: false
                smooth: true
                onStatusChanged: if (status === Image.Ready) chain.frameLoaded(layerIndex)
            }

            ShaderEffectSource {
                id: croppedFrame
                width: Math.ceil(chain.crop.width / chain.backdropDownscale)
                height: Math.ceil(chain.crop.height / chain.backdropDownscale)
                visible: false
                sourceItem: frameImage
                sourceRect: chain.crop
                textureSize: Qt.size(width, height)
                live: true
                recursive: false
                hideSource: false
                smooth: true
            }

            GaussianBlur {
                id: frameBlur
                width: croppedFrame.width
                height: croppedFrame.height
                visible: false
                source: croppedFrame
                deviation: chain.blurSigma / chain.backdropDownscale
                radius: Math.ceil(deviation * 2.6)
                samples: 2 * radius + 1
                transparentBorder: false
                cached: false
            }

            ShaderEffectSource {
                id: blurredFrame
                width: croppedFrame.width
                height: croppedFrame.height
                visible: false
                sourceItem: frameBlur
                textureSize: Qt.size(width, height)
                live: true
                recursive: false
                smooth: true
            }
        }
    }

    // Live video plane, blurred on every video frame. Only the leaves are
    // hidden: Qt skips a hidden parent's whole subtree.
    Item {
        width: chain.width
        height: chain.height

        VideoBackdrop {
            id: videoBackdrop
            anchors.fill: parent
            visible: false
            feedScript: Qt.resolvedUrl("vt-feed.py").toString().replace("file://", "")
            // Starts once the panel stands, so that launching the video
            // process cannot disturb the opening animation.
            running: (chain.joinedFeed || (chain.opened && chain.liveBackdrop && chain.shown)) &&
                     !chain.closing && !chain.videoFailed && !chain.stillRunning && !chain.stillsOnly &&
                     !chain.paused
            onHasFrameChanged: if (hasFrame) chain.videoFrameReady()
            onRunningChanged: chain.requestNextFrame()
        }

        ShaderEffectSource {
            id: videoCrop
            width: temporalBlend.width
            height: temporalBlend.height
            visible: false
            sourceItem: videoBackdrop
            sourceRect: chain.crop
            textureSize: Qt.size(width, height)
            live: true
            recursive: false
            hideSource: false
            smooth: true
        }

        GaussianBlur {
            id: videoBlur
            width: videoCrop.width
            height: videoCrop.height
            visible: false
            source: videoCrop
            deviation: chain.blurSigma / chain.backdropDownscale
            radius: Math.ceil(deviation * 2.6)
            samples: 2 * radius + 1
            transparentBorder: false
            cached: false
        }

        ShaderEffectSource {
            id: videoBlurred
            width: videoCrop.width
            height: videoCrop.height
            visible: false
            sourceItem: videoBlur
            textureSize: Qt.size(width, height)
            live: true
            recursive: false
            smooth: true
        }
    }

    // Temporal smoothing. Runs every display frame on the tiny blurred image
    // and moves it a share of the way to the newest frame. The step is at
    // least one 8-bit level, otherwise slow changes would round to nothing.
    ShaderEffect {
        id: temporalBlend
        width: blurredSize.width
        height: blurredSize.height
        visible: false
        readonly property size blurredSize: Qt.size(
            Math.ceil(chain.crop.width / chain.backdropDownscale),
            Math.ceil(chain.crop.height / chain.backdropDownscale))
        property variant target
        property variant previous: smoothedBackdrop
        // Frames land at once until the window stands. With the soft blend already
        // on, the glass would climb out of black during the opening: that was the grey.
        property real rate: chain.glassSettled && chain.shown ?
                                1 - Math.exp(-16.7 / (videoBackdrop.hasFrame ?
                                    chain.videoTimeConstant : chain.glassTimeConstant)) : 1
        // Only animates so that this pass reruns on every display frame.
        property real tick: 0
        NumberAnimation on tick {
            from: 0
            to: 1
            duration: 1000
            loops: Animation.Infinite
            running: chain.opened && chain.liveBackdrop
        }
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform sampler2D target;
            uniform sampler2D previous;
            uniform highp float rate;
            uniform highp float tick;

            void main() {
                highp vec3 from = texture2D(previous, qt_TexCoord0).rgb;
                highp vec3 to = texture2D(target, qt_TexCoord0).rgb;
                highp vec3 gap = to - from;
                highp vec3 size = abs(gap);
                highp vec3 step = sign(gap) * min(size, max(size * rate, vec3(1.0 / 255.0)));
                gl_FragColor = vec4(from + step + vec3(tick * 0.0), 1.0) * qt_Opacity;
            }"
    }

    ShaderEffectSource {
        id: smoothedBackdrop
        width: temporalBlend.width
        height: temporalBlend.height
        visible: false
        sourceItem: temporalBlend
        textureSize: Qt.size(width, height)
        recursive: true
        live: true
        smooth: true
    }

    // The colour of the glass is worked out here, on the tiny blurred image.
    // On the full panel this cost more GPU time than the display frame allows.
    ShaderEffect {
        id: backdropGrade
        width: temporalBlend.width
        height: temporalBlend.height
        visible: false
        property variant source: smoothedBackdrop
        property real veil: chain.veil
        fragmentShader: GlassStyle.gradeShader
    }

    ShaderEffectSource {
        id: gradedBackdrop
        width: temporalBlend.width
        height: temporalBlend.height
        visible: false
        sourceItem: backdropGrade
        textureSize: Qt.size(width, height)
        live: true
        smooth: true
    }


    function framePath(layer) {
        return framePrefix + layer + ".jpg";
    }

    // Frames land on the hidden layer. The visible one is never touched.
    function requestFrame(method) {
        if (captureRunning || closing) return;
        captureRunning = true;
        captureService.call("luna://com.webos.service.capture", "/executeOneShot",
                             JSON.stringify({
                                 path: framePath(1 - activeLayer),
                                 method: method,
                                 format: "JPEG",
                                 width: captureSize.width,
                                 height: captureSize.height
                             }));
    }

    // A separate capture: the live feed only delivers 480 x 270 with jagged edges, and
    // it must wait, because a capture comes back black while the feed runs.
    function requestStill() {
        stillTaken = true;
        stillRunning = true;
        captureRunning = true;
        captureService.call("luna://com.webos.service.capture", "/executeOneShot",
                             JSON.stringify({
                                 path: stillPath(foreground),
                                 method: "VIDEO",
                                 format: "JPEG",
                                 width: stillSize.width,
                                 height: stillSize.height
                             }));
    }

    function requestNextFrame() {
        if (paused) return;
        if (keepStill && !stillTaken && videoSource && !joinedFeed && !captureRunning && !closing &&
                foreground !== "") {
            requestStill();
            return;
        }
        // On an input, video screenshots remain the fallback while no live video is
        // available. Apps and Home keep their opening picture: VIDEO is refused there
        // without playing video, and DISPLAY would now contain this window.
        if (videoSource && !videoBackdrop.running) requestFrame("VIDEO");
    }

    function handleCapture(response) {
        captureRunning = false;
        if (stillRunning) {
            stillRunning = false;
            requestNextFrame();
            return;
        }
        if (closing) return;
        if (probingVideo) {
            probingVideo = false;
            if (!response.returnValue) {
                markProtected();
                return;
            }
            // The video is readable, so the black was the picture itself.
        }
        if (!response.returnValue) {
            ready();
            retryTimer.restart();
            return;
        }
        // A black picture is a picture: the neutral fallback would show a colour that
        // is not on screen. Only a long run of them means it is protected or gone.
        var empty = response.writtenBytes < minFrameBytes;
        // In an app an empty opening picture may be protected video: DISPLAY leaves
        // it out. VIDEO tells the two apart, it is refused for protected video.
        if (empty && !hasFrame && !videoSource && !videoProbed &&
                foreground !== "com.webos.app.home") {
            videoProbed = true;
            probingVideo = true;
            requestFrame("VIDEO");
            return;
        }
        emptyFrames = empty ? emptyFrames + 1 : 0;
        if (emptyFrames >= maxEmptyFrames) hasFrame = false;
        var layer = 1 - activeLayer;
        var image = frameLayers.itemAt(layer).frame;
        image.source = "";
        image.source = "file://" + framePath(layer);
    }

    function frameLoaded(layer) {
        activeLayer = layer;
        // A screenshot that arrives late must not replace the live video.
        if (!videoBackdrop.hasFrame) temporalBlend.target = frameLayers.itemAt(layer).blurred;
        if (!hasFrame && emptyFrames < maxEmptyFrames) {
            hasFrame = true;
            settleTimer.restart();
            firstPicture.restart();
        }
        requestNextFrame();
    }

    function stillPath(appId) {
        return "/tmp/novos-still-" + appId + ".jpg";
    }

    function videoFrameReady() {
        temporalBlend.target = videoBlurred;
        if (!hasFrame) {
            hasFrame = true;
            settleTimer.restart();
            firstPicture.restart();
        }
    }


    // No live picture in time: stay with screenshots for this opening.
    Timer {
        interval: chain.videoStartTimeout
        running: videoBackdrop.running && !videoBackdrop.hasFrame
        onTriggered: chain.videoFailed = true
    }

    // Frames stopped arriving: the video process died or the picture is gone.
    Timer {
        property int lastCount: 0
        interval: chain.videoStallTimeout
        repeat: true
        running: videoBackdrop.hasFrame
        onRunningChanged: lastCount = 0
        onTriggered: {
            var count = videoBackdrop.frameCount();
            if (count === lastCount) chain.videoFailed = true;
            lastCount = count;
        }
    }

    Timer {
        id: retryTimer
        interval: chain.retryDelay
        repeat: false
        onTriggered: chain.requestNextFrame()
    }

    // The first frame lands at once. Afterwards the glass eases towards
    // each new frame, so a late frame can never make it stop.
    Timer {
        id: settleTimer
        interval: chain.glassSettleDelay
        repeat: false
        onTriggered: chain.glassSettled = true
    }


    // A layer only renders while something on screen samples it. The chain above
    // ends in hidden items, so this invisible pixel keeps the recursive pass running.
    // Without it the glass stays black on live video.
    ShaderEffect {
        width: 1
        height: 1
        property variant source: smoothedBackdrop
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform sampler2D source;

            void main() {
                gl_FragColor = texture2D(source, qt_TexCoord0) * 0.0;
            }"
    }

    // The window is created anew for every key press. The capture starts right then,
    // not when the window opens: the glass must show what is on screen now, so the
    // window waits for this frame and every millisecond here shortens that wait.
    Component.onCompleted: {
        // The other window is open and holds the feed. Its frames are already the
        // current picture, and a screenshot would come back black.
        if (videoBackdrop.feedAlive()) {
            joinedFeed = true;
            return;
        }
        waitingForApp = true;
        appTimeout.restart();
        captureService.call("luna://com.webos.applicationManager", "/getForegroundAppInfo", "{}");
    }

    // A still picture for the opening. On an input VIDEO is the one that works:
    // DISPLAY comes back empty there. Home is graphics, which only DISPLAY contains.
    // In apps DISPLAY is the picture as seen, app video and subtitles included;
    // VIDEO is refused there while no video plays.
    function requestFirstFrame(method) {
        waitingForApp = false;
        appTimeout.stop();
        requestFrame(method);
    }

    function stop() {
        retryTimer.stop();
    }

    // Also leaves a feed it had joined, so that a standing surface does not keep
    // another window's video process alive.
    function pause() {
        paused = true;
        retryTimer.stop();
    }

    // The feed is asked first: running with a stale joinedFeed would start a process.
    function resume() {
        if (!paused) return;
        joinedFeed = videoBackdrop.feedAlive();
        paused = false;
        requestNextFrame();
    }

    // One new picture while paused. Only on an input: on Home and in apps the
    // screenshot would contain the surface itself. Not while a feed runs, it makes
    // VIDEO black.
    function refresh() {
        if (!paused || captureRunning || closing || !videoSource || videoBackdrop.feedAlive()) return;
        requestFrame("VIDEO");
    }

    // Inputs whose picture is the video plane. Everything else is an app or Home.
    function isVideoSource(appId) {
        return /^com\.webos\.app\.(hdmi\d|dp\d|usbc\d|externalinput\.|livetv$)/.test(appId);
    }

    // Our launcher lies below on the home layer: the glass shows its picture. GRAPHIC
    // holds the launcher; the video behind it is covered there.
    function launcherBelow() {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", "file:///tmp/novos-launcher-open.ini", false);
            request.send();
            return request.responseText.indexOf("open=true") >= 0;
        } catch (error) {
            return false;
        }
    }

    function setForeground(appId) {
        foreground = appId;
        if (launcherBelow()) {
            videoSource = false;
            appVideo = false;
            updateLive();
            if (waitingForApp) requestFirstFrame("GRAPHIC");
            return;
        }
        videoSource = isVideoSource(appId);
        updateLive();
        if (waitingForApp) requestFirstFrame(videoSource ? "VIDEO" : "DISPLAY");
        else requestNextFrame();
        // An app may play video. Asked after the capture, so the opening does not wait.
        if (!videoSource && appId !== "" && appId !== "com.webos.app.home")
            captureService.call("luna://com.webos.service.videooutput", "/getStatus", "{}");
    }

    // Live video only when the app's own video fills the glass. A smaller video in
    // the app's interface would show black where the interface is.
    function applyVideoStatus(status) {
        var videos = status.video || [];
        var main = null;
        for (var i = 0; i < videos.length; ++i) {
            if (videos[i].sink === "MAIN") main = videos[i];
        }
        appVideo = main !== null && main.connected === true && main.muted !== true &&
                   main.opacity !== 0 && main.appId === foreground &&
                   coversGlass(main.displayOutput || {});
        updateLive();
    }

    // libvtcapture refuses protected video as well, no need to start it.
    function updateLive() {
        liveBackdrop = videoSource || (appVideo && !protectedVideo);
    }

    // The fixed surface is final, so windows and notices need not wait any longer.
    function markProtected() {
        protectedVideo = true;
        updateLive();
        pictureReady = true;
        ready();
    }

    function coversGlass(output) {
        var left = Math.max(output.x / videoScreen.width, crop.x / width);
        var top = Math.max(output.y / videoScreen.height, crop.y / height);
        var right = Math.min((output.x + output.width) / videoScreen.width,
                             (crop.x + crop.width) / width);
        var bottom = Math.min((output.y + output.height) / videoScreen.height,
                              (crop.y + crop.height) / height);
        var covered = Math.max(0, right - left) * Math.max(0, bottom - top);
        return covered >= videoCoverage * (crop.width / width) * (crop.height / height);
    }

    // The next frame lands at once, for example after the crop has moved.
    function snap() {
        glassSettled = false;
        settleTimer.restart();
    }

    // The picture needs a few display frames through blur and grading. The window
    // only appears once it has arrived on the glass.
    Timer {
        id: firstPicture
        interval: 50
        onTriggered: {
            chain.pictureReady = true;
            chain.ready();
        }
    }

    Timer {
        id: appTimeout
        interval: 150
        onTriggered: chain.requestFirstFrame("DISPLAY")
    }

    Service {
        id: captureService
        appId: "com.webos.app.quicksettings"
        onResponse: {
            if (method === "/executeOneShot") chain.handleCapture(JSON.parse(payload));
            else if (method === "/getForegroundAppInfo") chain.setForeground(JSON.parse(payload).appId || "");
            else if (method === "/getStatus") chain.applyVideoStatus(JSON.parse(payload));
        }
        onError: {
            if (method === "/executeOneShot") {
                chain.captureRunning = false;
                chain.stillRunning = false;
                if (chain.probingVideo) {
                    chain.probingVideo = false;
                    chain.markProtected();
                    return;
                }
                chain.ready();
                retryTimer.restart();
            }
        }
    }
}
