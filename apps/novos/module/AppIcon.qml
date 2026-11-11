import QtQuick 2.12

// App icon on a dark plate with rounded corners. Store icons come as 80 to 130 px
// PNG, some of them white on transparent, so the plate is always there.
Item {
    id: icon

    property string source: ""
    property real cornerRadius: 18
    property bool focused: false

    Rectangle {
        anchors.fill: parent
        radius: icon.cornerRadius
        color: "#750a0e14"
    }

    Image {
        id: picture
        anchors.fill: parent
        visible: false
        source: icon.source
        sourceSize: Qt.size(icon.width, icon.height)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    ShaderEffect {
        anchors.fill: parent
        visible: picture.status === Image.Ready
        property variant source: picture
        property size boxSize: Qt.size(width, height)
        property real boxRadius: icon.cornerRadius
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform sampler2D source;
            uniform highp vec2 boxSize;
            uniform highp float boxRadius;

            void main() {
                highp vec2 point = (qt_TexCoord0 - 0.5) * boxSize;
                highp vec2 q = abs(point) - boxSize * 0.5 + vec2(boxRadius);
                highp float outer = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - boxRadius;
                gl_FragColor = texture2D(source, qt_TexCoord0) * clamp(0.5 - outer, 0.0, 1.0) * qt_Opacity;
            }"
    }

    Rectangle {
        anchors.fill: parent
        radius: icon.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: icon.focused ? GlassStyle.trackFocused : GlassStyle.divider
    }
}
