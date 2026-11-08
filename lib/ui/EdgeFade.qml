import QtQuick 2.12

// Layer effect for long lists: fades the content out towards the top and bottom,
// but only at an end that has more rows. All lengths are shares of the height.
ShaderEffect {
    property real topFade: 0.2
    property real bottomFade: 0.2
    property real bottomGap: 0
    property real topAmount: 0
    property real horizontal: 0              // 1 fades left and right instead
    property real bottomAmount: 0

    Behavior on topAmount { NumberAnimation { duration: 180 } }
    Behavior on bottomAmount { NumberAnimation { duration: 180 } }

    fragmentShader: "
        varying highp vec2 qt_TexCoord0;
        uniform lowp float qt_Opacity;
        uniform sampler2D source;
        uniform highp float topFade;
        uniform highp float bottomFade;
        uniform highp float bottomGap;
        uniform lowp float topAmount;
        uniform lowp float bottomAmount;
        uniform lowp float horizontal;

        void main() {
            highp float along = mix(qt_TexCoord0.y, qt_TexCoord0.x, horizontal);
            lowp float top = clamp(along / topFade, 0.0, 1.0);
            lowp float bottom = clamp((1.0 - bottomGap - along) / bottomFade, 0.0, 1.0);
            gl_FragColor = texture2D(source, qt_TexCoord0) * qt_Opacity *
                           mix(1.0, top, topAmount) * mix(1.0, bottom, bottomAmount);
        }"
}
