pragma Singleton
import QtQuick 2.12
import Qt.labs.settings 1.0

// Values both menus share. The edge light follows the blur: a sharper picture behind the
// glass needs a stronger edge to hold the shape, a very soft one needs less. At the
// approved blur of 84 px the factor is exactly 1.
QtObject {
    id: style

    readonly property real referenceBlur: 84

    // ---- Design tokens -------------------------------------------------------------
    // One place for the values every window and module shares, so that all of novOS
    // looks and moves the same. Change them here, never as numbers in a file.
    // Text on the glass.
    readonly property color textPrimary: "#ffffff"
    readonly property color textSecondary: "#b8ffffff"     // values, subtitles of pages: white 72 %
    readonly property color textDetail: "#b3ffffff"        // second line of a row: white 70 %
    readonly property color textMuted: "#99ffffff"         // section titles, quiet labels: white 60 %
    // The focus surface and what stands on it.
    readonly property color focusFill: "#f2ffffff"         // white 95 %
    readonly property color focusText: "#0b0c10"
    readonly property color focusSecondary: "#5b5e66"
    readonly property real focusScale: 1.03
    readonly property real pressScale: 0.93                // one short pulse per key press
    // Controls.
    readonly property color accent: "#4c9dff"              // switch on, markers
    readonly property color switchOff: "#5c787880"         // keeps its grey on the focus surface
    readonly property color trackFill: "#3dffffff"         // slider track on glass
    readonly property color trackFocused: "#240b0c10"      // slider track on the focus surface
    readonly property color separator: "#1fffffff"        // white 12 %
    readonly property color danger: "#ff9a90"
    readonly property color dangerFocused: "#c42b20"
    // Motion.
    readonly property var curve: [0.2, 0.8, 0.2, 1, 1, 1]
    readonly property int focusDuration: 220               // the focus surface and lists glide
    readonly property int colorDuration: 120               // text and icons change colour
    readonly property int pageDuration: 240                // pages cross-fade with 16 px shift
    readonly property real pageShift: 16
    readonly property int popoverDuration: 160             // popovers, dimming, fades
    readonly property int pressDuration: 40
    readonly property real dimmedOpacity: 0.4              // what steps back behind a popover
    readonly property int switchDuration: 260               // the knob of a switch springs over
    readonly property var switchCurve: [0.34, 1.36, 0.5, 1, 1, 1]
    // Type, in logical px.
    readonly property int titleSize: 32                    // page title in the panel
    readonly property int modalTitleSize: 40               // page title in the settings modal
    readonly property int rowSize: 22
    readonly property int valueSize: 18
    readonly property int detailSize: 17
    readonly property int sectionSize: 16
    readonly property real sectionTracking: 0.96          // 0.06 em, as in the hand-off
    property alias blur: values.blur
    property alias hideInputBanner: values.hideInputBanner
    property alias demoDevices: values.demoDevices
    property alias keyboardMode: values.keyboardMode
    readonly property real edgeGain: Math.max(0.5, Math.min(2.5, Math.pow(referenceBlur / blur, 0.7)))

    // Inter in the three cuts of the hand-off, loaded once for every window.
    readonly property string titleFont: titleLoader.name     // bold: titles
    readonly property string rowFont: rowLoader.name         // medium: rows, buttons
    readonly property string valueFont: valueLoader.name     // regular: values, second lines
    property FontLoader titleLoader: FontLoader { source: Qt.resolvedUrl("../novos-inter-title.ttf") }
    property FontLoader rowLoader: FontLoader { source: Qt.resolvedUrl("../novos-inter-row.ttf") }
    property FontLoader valueLoader: FontLoader { source: Qt.resolvedUrl("../novos-inter-value.ttf") }

    // Kept until the TV restarts, also across the two menus.
    property Settings values: Settings {
        id: values
        fileName: "/tmp/novos-debug.ini"
        property real blur: 84
        property bool hideInputBanner: true
        property bool demoDevices: false     // the smart home hub's made-up home
        property string keyboardMode: "qwertz"   // last used: "qwertz" or "t9"
    }

    readonly property string shadowShader: "
        varying highp vec2 qt_TexCoord0;
        uniform lowp float qt_Opacity;
        uniform highp vec2 itemSize;
        uniform highp vec2 boxSize;
        uniform highp float boxRadius;
        uniform highp float sigma;
        uniform highp float offsetY;
        uniform lowp vec4 shadowColor;
        uniform lowp float strength;

        highp float roundedBox(highp vec2 point, highp vec2 halfSize, highp float radius) {
            highp vec2 q = abs(point) - halfSize + vec2(radius);
            return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
        }

        void main() {
            highp vec2 point = (qt_TexCoord0 - 0.5) * itemSize;
            highp vec2 halfSize = boxSize * 0.5;
            highp float boxDistance = roundedBox(point - vec2(0.0, offsetY), halfSize, boxRadius);
            highp float x = -boxDistance / (sigma * 1.41421356);
            highp float erf = sign(x) * sqrt(1.0 - exp(-1.2732395 * x * x));
            highp float coverage = 0.5 + 0.5 * erf;
            highp float outside = clamp(roundedBox(point, halfSize, boxRadius) + 0.5, 0.0, 1.0);
            gl_FragColor = shadowColor * coverage * outside * strength * qt_Opacity;
        }"

    readonly property string glassShader: "
                varying highp vec2 qt_TexCoord0;
                uniform lowp float qt_Opacity;
                uniform sampler2D backdrop;
                uniform highp vec2 panelSize;
                uniform highp float cornerRadius;
                uniform highp float topLightWidth;
                uniform highp float contourWidth;
                uniform highp float glowHeight;
                uniform highp float backdropMargin;
                uniform highp vec2 backdropOrigin;
                uniform highp vec2 backdropArea;
                uniform lowp float dim;
                uniform lowp float hasBackdrop;
                uniform highp float edgeGain;

                const lowp vec3 fallback = vec3(0.1098, 0.1255, 0.1725);

                highp float roundedBox(highp vec2 point, highp vec2 halfSize, highp float radius) {
                    highp vec2 q = abs(point) - halfSize + vec2(radius);
                    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
                }

                highp float noise(highp vec2 point) {
                    return fract(52.9829189 * fract(dot(point, vec2(0.06711056, 0.00583715))));
                }

                void main() {
                    highp vec2 pixel = qt_TexCoord0 * panelSize;
                    highp vec2 halfSize = panelSize * 0.5;
                    highp vec2 point = pixel - halfSize;

                    highp vec2 uv = (pixel + backdropOrigin + vec2(backdropMargin)) /
                                    (backdropArea + vec2(2.0 * backdropMargin));
                    lowp vec3 color = mix(fallback, texture2D(backdrop, uv).rgb, hasBackdrop);
                    lowp float alpha = mix(0.94, 1.0, hasBackdrop);

                    // linear-gradient(135deg, white 20 %, 7 % at 45 %, 13 %).
                    highp float span = (panelSize.x + panelSize.y) * 0.70710678;
                    highp float t = dot(point, vec2(0.70710678)) / span + 0.5;
                    highp float sheen = t < 0.45 ? mix(0.20, 0.07, t / 0.45)
                                                 : mix(0.07, 0.13, (t - 0.45) / 0.55);
                    color = mix(color, vec3(1.0), sheen * hasBackdrop);
                    color *= 1.0 - dim;

                    // Hides 8-bit banding in dark blurred areas.
                    color += (noise(gl_FragCoord.xy) - 0.5) / 255.0;

                    // The edge work only runs near the edge. Most pixels of a
                    // large card never get here, which is what keeps it smooth.
                    highp float shape = 1.0;
                    highp vec2 inset = abs(point) - halfSize;
                    if (max(inset.x, inset.y) > -(cornerRadius + glowHeight)) {
                        highp float outer = roundedBox(point, halfSize, cornerRadius);
                        highp float shifted = roundedBox(point - vec2(0.0, topLightWidth), halfSize, cornerRadius);

                        // The rim takes on some of the picture, so it reads as
                        // light in the glass rather than a white line on top.
                        lowp vec3 rim = mix(vec3(1.0), color, 0.40);

                        // Soft glow under the top edge gives the rim some body.
                        highp float depth = max(-outer, 0.0);
                        highp float glow = 0.06 * edgeGain * exp(-depth / glowHeight);
                        color = mix(color, rim, glow * clamp(1.0 - pixel.y / (panelSize.y * 0.5), 0.0, 1.0));

                        // Fine contour along the whole rounded edge.
                        highp float contour = clamp(outer + contourWidth + 0.5, 0.0, 1.0);
                        color = mix(color, rim, min(1.0, 0.13 * edgeGain) * contour);
                        alpha = mix(alpha, 1.0, min(1.0, 0.13 * edgeGain) * contour);

                        // Clear light line along the top, tapering around the corners.
                        highp float topLight = clamp(shifted + 0.5, 0.0, 1.0);
                        color = mix(color, rim, min(1.0, 0.50 * edgeGain) * topLight);
                        alpha = mix(alpha, 1.0, min(1.0, 0.50 * edgeGain) * topLight);

                        shape = clamp(0.5 - outer, 0.0, 1.0);
                    }

                    gl_FragColor = vec4(color * alpha, alpha) * shape * qt_Opacity;
                }"

    readonly property string gradeShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform sampler2D source;

            const lowp vec3 scrim = vec3(0.0157, 0.0235, 0.0314);
            const lowp vec3 luma = vec3(0.2126, 0.7152, 0.0722);
            const highp float knee = 0.24;
            const highp float ceiling = 0.36;

            void main() {
                lowp vec3 color = texture2D(source, qt_TexCoord0).rgb;
                color = mix(color, scrim, 0.18);
                color = clamp(mix(vec3(dot(color, luma)), color, 1.8), 0.0, 1.0);

                // Bright content keeps its hue but stops short of white,
                // so white text stays readable on any picture.
                highp float brightness = dot(color, luma);
                if (brightness > knee) {
                    highp float room = ceiling - knee;
                    highp float limited = knee + room * (1.0 - exp((knee - brightness) / room));
                    color *= limited / brightness;
                }
                gl_FragColor = vec4(color, 1.0) * qt_Opacity;
            }"

    // Picture with rounded corners and edge light in one pass.
    readonly property string pictureShader: "
                    varying highp vec2 qt_TexCoord0;
                    uniform lowp float qt_Opacity;
                    uniform sampler2D source;
                    uniform highp vec4 sourceRect;
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
                        lowp vec3 color = texture2D(source, sourceRect.xy + qt_TexCoord0 * sourceRect.zw).rgb;
                        const lowp vec3 rim = vec3(0.667, 0.698, 0.769);
                        color = mix(color, rim, min(1.0, 0.20 * edgeGain) * clamp(outer + contourWidth + 0.5, 0.0, 1.0));
                        color = mix(color, rim, min(1.0, 0.50 * edgeGain) * clamp(shifted + 0.5, 0.0, 1.0));
                        lowp float alpha = clamp(0.5 - outer, 0.0, 1.0);
                        gl_FragColor = vec4(color * alpha, alpha) * qt_Opacity;
                    }"

    // LG's Home starts its preview with this role, and its input apps then leave out their
    // banner. It lasts until the next launch of that input, and touches a few of LG's
    // checks there, so the debug page can turn it off. banner-relay.py reads the same value.
    function launchRequest(appId) {
        var request = { id: appId };
        if (hideInputBanner && appId.indexOf("com.webos.app.hdmi") === 0) {
            request.params = { appViewRole: "appViewGuest" };
        }
        return JSON.stringify(request);
    }
}
