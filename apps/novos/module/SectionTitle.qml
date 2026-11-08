import QtQuick 2.12
import "."

// Title above a group of entries: 16 px capitals with tracking in the muted text colour
// (docs/design-system.md, "Klare Stufen"). It stands 10 px above its list. The owner
// places it and may centre it or change its colour (for example on the focus surface).
Text {
    property real unit: 1

    height: 20 * unit
    verticalAlignment: Text.AlignVCenter
    color: GlassStyle.textMuted
    font.family: GlassStyle.titleFont
    font.pixelSize: GlassStyle.sectionSize * unit
    font.letterSpacing: GlassStyle.sectionTracking * unit
    font.capitalization: Font.AllUppercase
    font.hintingPreference: Font.PreferNoHinting
}
