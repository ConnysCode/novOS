import QtQuick 2.12
import WebOSServices 1.0
import "."

// Picture of a source in the launcher. Everything that moves is a sharp frame on the GPU,
// because the video plane stutters while it is scaled. At rest a hole opens down to the
// plane, which the launcher has moved here beforehand, and the frame fades away.
Item {
    id: preview

    property real unit: 1
    property string shadowShader: ""
    property bool live: false               // show the running source
    property bool capturing: false          // keep a recent frame of the running source
    property bool holeOpen: false
    property string still: ""
    property real motion: 1                 // set by the owner's transition
    property real roundness: 1              // 0 while the picture still fills the screen
    property int shownLayer: 0
    property bool hasFrame: false
    property bool planeSmall: false         // the video plane sits at the preview
    readonly property rect planeArea: Qt.rect(1248 / 1920, 203 / 1080, 576 / 1920, 324 / 1080)
    property bool firstCropped: false
    property bool secondCropped: false
    signal frameReady()

    readonly property Image currentFrame: shownLayer === 0 ? first : second
    readonly property bool hasPicture: live ? hasFrame || holeOpen : stillImage.status === Image.Ready
    opacity: motion * ((live || still !== "") && hasPicture ? 1 : 0)
    visible: opacity > 0

    // A capture shows the screen as it is: with the plane at the preview, the video sits
    // in that corner of the frame. So those frames are full size and get cut out.
    function capture() {
        var next = 1 - shownLayer;
        service.pending = next;
        service.pendingCropped = planeSmall;
        service.call("luna://com.webos.service.capture", "/executeOneShot", JSON.stringify({
            path: "/tmp/novos-live-" + next + ".jpg", method: "VIDEO", format: "JPEG",
            width: planeSmall ? 1920 : 1152, height: planeSmall ? 1080 : 648 }));
    }

    function frameLoaded(layer) {
        shownLayer = layer;
        var first = !hasFrame;
        hasFrame = true;
        if (first) frameReady();
        renew.restart();
    }

    onCapturingChanged: if (capturing) capture()

    Service {
        id: service
        property int pending: 0
        property bool pendingCropped: false
        appId: "com.webos.app.quicksettings"
        onResponse: {
            // The plane moved meanwhile, so the frame shows it in the wrong place.
            if (!preview.capturing || pendingCropped !== preview.planeSmall) {
                renew.restart();
                return;
            }
            if (pending === 0) preview.firstCropped = pendingCropped;
            else preview.secondCropped = pendingCropped;
            var image = preview.pendingImage();
            image.source = "";
            image.source = "file:///tmp/novos-live-" + pending + ".jpg";
        }
        onError: renew.restart()
    }

    function pendingImage() {
        return service.pending === 0 ? first : second;
    }

    Timer {
        id: renew
        interval: 900
        onTriggered: if (preview.capturing) preview.capture()
    }

    SoftShadow {
        unit: preview.unit
        boxWidth: preview.width
        boxHeight: preview.height
        visible: preview.roundness >= 1
        radius: 28
        softness: 30
        drop: 24
        strength: 0.45
        pad: 90
    }

    Image {
        id: first
        visible: false
        cache: false
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) preview.frameLoaded(0)
    }

    Image {
        id: second
        visible: false
        cache: false
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) preview.frameLoaded(1)
    }

    Image {
        id: stillImage
        visible: false
        cache: false
        asynchronous: true
        source: !preview.live && preview.still !== "" ? "file://" + preview.still : ""
    }

    // The hole. Without blending it clears the window down to the video plane.
    ShaderEffect {
        anchors.fill: parent
        visible: preview.holeOpen
        blending: false
        property size boxSize: Qt.size(width, height)
        property real cornerRadius: 28 * preview.unit
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform highp vec2 boxSize;
            uniform highp float cornerRadius;

            void main() {
                highp vec2 point = abs((qt_TexCoord0 - 0.5) * boxSize) - boxSize * 0.5 + vec2(cornerRadius);
                highp float distance = min(max(point.x, point.y), 0.0) + length(max(point, vec2(0.0))) - cornerRadius;
                if (distance > 0.0) discard;
                gl_FragColor = vec4(0.0);
            }"
    }

    ShaderEffect {
        anchors.fill: parent
        opacity: preview.holeOpen ? 0 : 1
        visible: opacity > 0
        property variant source: preview.live ? preview.currentFrame : stillImage
        property rect sourceRect: preview.live && (preview.shownLayer === 0 ? preview.firstCropped : preview.secondCropped) ?
                                  preview.planeArea : Qt.rect(0, 0, 1, 1)
        property size boxSize: Qt.size(width, height)
        property real cornerRadius: 28 * preview.unit * preview.roundness
        property real topLightWidth: 1.5 * preview.unit
        property real contourWidth: 1.25 * preview.unit
        property real edgeGain: GlassStyle.edgeGain * preview.roundness
        fragmentShader: GlassStyle.pictureShader

        Behavior on opacity {
            enabled: preview.holeOpen
            NumberAnimation { duration: 200 }
        }
    }

    // The edge light stays while the video shows through the hole.
    ShaderEffect {
        anchors.fill: parent
        visible: preview.holeOpen
        property size boxSize: Qt.size(width, height)
        property real cornerRadius: 28 * preview.unit
        property real topLightWidth: 1.5 * preview.unit
        property real contourWidth: 1.25 * preview.unit
        property real edgeGain: GlassStyle.edgeGain
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform highp vec2 boxSize;
            uniform highp float cornerRadius;
            uniform highp float topLightWidth;
            uniform highp float contourWidth;
            uniform highp float edgeGain;

            highp float roundedBox(highp vec2 point, highp vec2 halfSize, highp float radius) {
                highp vec2 q = abs(point) - halfSize + vec2(radius);
                return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
            }

            void main() {
                highp vec2 halfSize = boxSize * 0.5;
                highp vec2 point = (qt_TexCoord0 - 0.5) * boxSize;
                highp float outer = roundedBox(point, halfSize, cornerRadius);
                highp float shifted = roundedBox(point - vec2(0.0, topLightWidth), halfSize, cornerRadius);
                lowp float edge = min(1.0, 0.20 * edgeGain) * clamp(outer + contourWidth + 0.5, 0.0, 1.0);
                edge = max(edge, min(1.0, 0.50 * edgeGain) * clamp(shifted + 0.5, 0.0, 1.0));
                lowp float alpha = edge * clamp(0.5 - outer, 0.0, 1.0);
                gl_FragColor = vec4(vec3(0.667, 0.698, 0.769) * alpha, alpha) * qt_Opacity;
            }"
    }
}
