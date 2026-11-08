import QtQuick 2.12

// What lies behind the setup's glass:
//   "picture"  one of the launcher's pictures (lib/backgrounds), as Home and the hub show them
//   "glow"     black with a soft light in the middle (restart screens, K3-Boot-Schein)
//   "black"    plain black (farewell after the removal)
// The design canvas draws its own scenes; on the TV the setup uses the same pictures as
// the launcher, so that it looks like the novOS it installs.
Item {
    id: scene

    property real unit: 1
    property string kind: "picture"
    property url pictureSource: ""

    Rectangle {
        anchors.fill: parent
        color: scene.kind === "picture" ? "#02040a" : "#000000"
    }

    Image {
        anchors.fill: parent
        visible: scene.kind === "picture"
        source: visible ? scene.pictureSource : ""
        sourceSize: Qt.size(1920, 1080)
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    // radial-gradient(circle, rgba(255, 236, 210, 0.14) 0%, rgba(150, 190, 255, 0.06) 35%,
    // transparent 65%) in a 900 px box at (50 %, 46 %), as on K3-Boot-Schein-1.
    ShaderEffect {
        anchors.fill: parent
        visible: scene.kind === "glow"
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;

            highp float span(highp float t, highp float a, highp float b) {
                return clamp((t - a) / (b - a), 0.0, 1.0);
            }

            void main() {
                highp vec2 p = qt_TexCoord0 * vec2(1920.0, 1080.0);
                highp float r = length(p - vec2(960.0, 496.8));
                highp float s = r / 636.4;
                highp float a = mix(0.14, 0.06, span(s, 0.0, 0.35));
                a = mix(a, 0.0, span(s, 0.35, 0.65)) * clamp(450.0 - r + 0.5, 0.0, 1.0);
                highp vec3 rgb = mix(vec3(255.0, 236.0, 210.0), vec3(150.0, 190.0, 255.0), span(s, 0.0, 0.35)) / 255.0;
                highp float dither = (fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
                gl_FragColor = vec4(rgb * a + dither, 1.0) * qt_Opacity;
            }"
    }
}
