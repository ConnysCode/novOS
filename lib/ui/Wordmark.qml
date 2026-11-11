import QtQuick 2.12
import "."

// The novOS wordmark: "nov" bold and white, "OS" light at 72 %, on one baseline, with
// -0.035 em tracking. size is the font size in logical px (28 in dialog headers, 88 on
// the restart screens). The light cut is the regular one until the fonts bring a 300.
Row {
    id: mark

    property real unit: 1
    property real size: 28

    spacing: 0
    baselineOffset: nov.baselineOffset

    Text {
        id: nov
        text: "nov"
        color: GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: mark.size * mark.unit
        font.letterSpacing: -0.035 * mark.size * mark.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    Text {
        text: "OS"
        color: GlassStyle.textSecondary
        font.family: GlassStyle.valueFont
        font.pixelSize: mark.size * mark.unit
        font.letterSpacing: -0.035 * mark.size * mark.unit
        font.hintingPreference: Font.PreferNoHinting
    }
}
