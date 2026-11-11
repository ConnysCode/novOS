import QtQuick 2.12
import "."

// The warm light of the boot look on black (K3-Boot-Schein, K3-Shutdown-Schein and the
// restart screens of the setup): radial-gradient(circle, rgba(255, 236, 210, 0.14) 0%,
// rgba(150, 190, 255, 0.06) 35%, transparent 65%) in a 900 px box at (50 %, 46 %) of a
// 1920×1080 stage. It paints the black too, so it fills a whole screen.
//   strength  scales the light: 1 when starting, GlassStyle.shutdownDim when switching off
//   pulsing   breathes it as on the canvas: opacity 85–100 % and size +4 % in 6 s
//   spread    the box of the light in stage px; a small picture of the screen (a tile)
//             draws it larger, as the canvas does
//   radius    rounds the corners, in px of this item; outside them nothing is painted
//   tint      a colour instead of the warm light, for example a profile's while it is being
//             switched to (K3-Profil-Wechsel): that colour at 26 % → 8 % at 35 % → nothing at 65 %
// The shader runs once into a texture; the breath only scales and fades that texture
// around the centre of the light. Computing the full-screen gradient anew for every frame
// made the preview stutter (23 ms per frame on average, gaps of up to 70 ms). The breath
// fades towards what lies below, which is black wherever it pulses.
Item {
    id: glow

    property real strength: 1
    property real spread: 900
    property real radius: 0
    property bool pulsing: false
    property color tint: "transparent"
    property real breath: 0          // 0 → 1 → 0 over one pulse

    SequentialAnimation on breath {
        running: glow.pulsing && glow.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: GlassStyle.bootPulseDuration / 2; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: GlassStyle.bootPulseDuration / 2; easing.type: Easing.InOutSine }
    }

    ShaderEffect {
        anchors.fill: parent
        // Without the breath the light rests at its low point inside the texture, and the
        // picture stays opaque (a tile's white focus plate must not show through).
        opacity: glow.pulsing ? 1 - (1 - GlassStyle.bootPulseLow) * (1 - glow.breath) : 1
        transform: Scale {
            origin.x: glow.width / 2
            origin.y: glow.height * 0.46
            xScale: 1 + (GlassStyle.bootPulseSwell - 1) * glow.breath
            yScale: xScale
        }
        layer.enabled: true
        layer.smooth: true

        property real light: glow.strength * (glow.pulsing ? 1 : GlassStyle.bootPulseLow)
        property real spread: glow.spread
        property real radius: glow.radius
        property size itemSize: Qt.size(width, height)
        property color tint: glow.tint
        property real tinted: glow.tint.a > 0 ? 1 : 0

        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform highp float light;
            uniform highp float spread;
            uniform highp float radius;
            uniform highp vec2 itemSize;
            uniform lowp vec4 tint;
            uniform lowp float tinted;

            highp float span(highp float t, highp float a, highp float b) {
                return clamp((t - a) / (b - a), 0.0, 1.0);
            }

            void main() {
                highp vec2 p = qt_TexCoord0 * vec2(1920.0, 1080.0);
                highp float r = length(p - vec2(960.0, 496.8));
                highp float s = r / (spread * 0.70711);
                highp float a = mix(mix(0.14, 0.26, tinted), mix(0.06, 0.08, tinted), span(s, 0.0, 0.35));
                a = mix(a, 0.0, span(s, 0.35, 0.65)) * clamp(spread * 0.5 - r + 0.5, 0.0, 1.0) * light;
                highp vec2 q = abs(qt_TexCoord0 * itemSize - itemSize * 0.5) - itemSize * 0.5 + vec2(radius);
                highp float corner = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
                highp float inside = clamp(0.5 - corner, 0.0, 1.0);
                highp vec3 rgb = mix(vec3(255.0, 236.0, 210.0), vec3(150.0, 190.0, 255.0), span(s, 0.0, 0.35)) / 255.0;
                rgb = mix(rgb, tint.rgb / max(tint.a, 0.001), tinted);
                highp float dither = (fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
                gl_FragColor = vec4(rgb * a + dither, 1.0) * inside * qt_Opacity;
            }"
    }
}
