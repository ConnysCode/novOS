import QtQuick 2.12
import "."

// Fades a long list out towards the top and bottom, like EdgeFade, without drawing the whole
// list into a texture first. The middle is drawn directly and clipped; only the two fade
// strips are copied into small textures and faded there. Measured on the TV, a list-sized
// layer cost the settings modal about five frames per second (docs/performance-plan.md).
//
//     EdgeFadeView {
//         width: …; height: …
//         topFade: 56 * unit; bottomFade: 96 * unit        // strip heights in px
//         topAmount: scroll > 1 ? 1 : 0                     // 0 shows the end without fade
//         bottomAmount: scroll < maxScroll - 1 ? 1 : 0
//         Item { y: -scroll; … rows … }
//     }
//
// The content gets the view's full height; children are positioned as inside a plain Item.
Item {
    id: view

    property real topFade: 0
    property real bottomFade: 0
    property real bottomGap: 0                // px at the very bottom that stay clear while fading
    property real topAmount: 0
    property real bottomAmount: 0
    property bool fading: true                // false: a plain clipped list, no strips

    default property alias content: inner.data

    Behavior on topAmount { NumberAnimation { duration: GlassStyle.listFadeDuration } }
    Behavior on bottomAmount { NumberAnimation { duration: GlassStyle.listFadeDuration } }

    readonly property real topStrip: fading ? Math.min(topFade, height / 2) : 0
    readonly property real bottomStrip: fading ? Math.min(bottomFade + bottomGap, height / 2) : 0

    Item {
        id: middle
        y: view.topStrip
        width: view.width
        height: Math.max(0, view.height - view.topStrip - view.bottomStrip)
        clip: true

        Item {
            id: inner
            y: -middle.y
            width: view.width
            height: view.height
        }
    }

    // One strip: the content in that band, faded towards the outer edge.
    Repeater {
        model: view.fading ? 2 : 0

        ShaderEffect {
            readonly property bool isTop: index === 0
            readonly property real band: isTop ? view.topStrip : view.bottomStrip
            y: isTop ? 0 : view.height - band
            width: view.width
            height: band
            visible: band > 0
            property real amount: isTop ? view.topAmount : view.bottomAmount
            property real fromTop: isTop ? 1 : 0
            property real gap: isTop || band <= 0 ? 0 : Math.min(1, view.bottomGap / band)
            property variant source: ShaderEffectSource {
                sourceItem: inner
                sourceRect: Qt.rect(0, isTop ? 0 : view.height - band, view.width, band)
                textureSize: Qt.size(Math.max(1, Math.ceil(view.width)), Math.max(1, Math.ceil(band)))
                live: true
                hideSource: false
                smooth: false
            }

            fragmentShader: "
                varying highp vec2 qt_TexCoord0;
                uniform lowp float qt_Opacity;
                uniform sampler2D source;
                uniform lowp float amount;
                uniform lowp float fromTop;
                uniform highp float gap;

                void main() {
                    highp float outward = mix(1.0 - qt_TexCoord0.y, qt_TexCoord0.y, fromTop);
                    lowp float ramp = clamp((outward - gap) / max(1.0 - gap, 0.0001), 0.0, 1.0);
                    gl_FragColor = texture2D(source, qt_TexCoord0) * qt_Opacity * mix(1.0, ramp, amount);
                }"
        }
    }
}
