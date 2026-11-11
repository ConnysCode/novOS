pragma Singleton
import QtQuick 2.12
import Qt.labs.settings 1.0
import WebOSServices 1.0
import "UiConfig.js" as UiConfig

// Values every window of an app shares. The edge light follows the blur: a sharper picture behind the
// glass needs a stronger edge to hold the shape, a very soft one needs less. At the
// approved blur of 84 px the factor is exactly 1.
QtObject {
    id: style

    readonly property real referenceBlur: 84

    // ---- High contrast (QS-1, K3-Einst-HoherKontrast) ------------------------------------
    // LG's option.highContrast, read by every window itself. On, every token below that names
    // a contrast value takes it: stronger dimming under the glass, stronger texts, clearer
    // edges and fills. The glass itself stays as it is (blur, saturation, gloss, live
    // picture); its grade only takes the stronger content dimming as a veil (contentVeil).
    // Settable, so that previews can show it.
    property bool highContrast: false
    property var contrastReader: Service {
        appId: UiConfig.serviceAppId
        Component.onCompleted: call("luna://com.webos.settingsservice", "/getSystemSettings",
                                    JSON.stringify({ category: "option", keys: ["highContrast"], subscribe: true }))
        onResponse: {
            var response = JSON.parse(payload);
            if (response.settings && response.settings.highContrast !== undefined) {
                style.highContrast = response.settings.highContrast === "on";
            }
        }
    }

    // ---- Design tokens -------------------------------------------------------------
    // One place for the values every window and component shares, so that all of novOS
    // looks and moves the same. Change them here, never as numbers in a file.
    // Text on the glass.
    readonly property color textPrimary: "#ffffff"
    readonly property color textSecondary: highContrast ? "#ebffffff" : "#b8ffffff" // values, subtitles of pages: 72 %, contrast 92 %
    readonly property color textDetail: highContrast ? "#e6ffffff" : "#b3ffffff"   // second line of a row: 70 %, contrast 90 %
    readonly property color textMuted: highContrast ? "#d1ffffff" : "#99ffffff"    // section titles, quiet labels: 60 %, contrast 82 %
    // The focus surface and what stands on it.
    readonly property color focusFill: highContrast ? "#ffffffff" : "#f2ffffff"    // white 95 %, contrast 100 %
    readonly property color focusText: highContrast ? "#050608" : "#0b0c10"
    readonly property color focusSecondary: highContrast ? "#363940" : "#5b5e66"  // contrast 11.6:1 on white
    readonly property real focusScale: 1.03
    readonly property real pressScale: 0.93                // one short pulse per key press
    // Controls.
    readonly property color accent: highContrast ? "#2b7bef" : "#4c9dff"           // switch on, markers
    readonly property color switchOff: highContrast ? "#9e787880" : "#5c787880"    // keeps its grey on the focus surface
    readonly property color trackFill: highContrast ? "#6bffffff" : "#3dffffff"    // slider track on glass: 24 %, contrast 42 %
    readonly property color trackFocused: highContrast ? "#470b0c10" : "#240b0c10" // slider track on the focus surface
    readonly property color zeroLine: highContrast ? "#d9ffffff" : "#8cffffff"     // the 0 of a slider filled from its middle: white 55 %
    readonly property color zeroLineFocused: highContrast ? "#990b0c10" : "#660b0c10" // on the focus surface: 40 %
    readonly property color endCapFill: highContrast ? "#24ffffff" : "#14ffffff"   // the circle at an end of a slider ("L"): white 8 %
    readonly property color endCapFocused: highContrast ? "#290b0c10" : "#140b0c10" // on the focus surface: 8 %
    readonly property color separator: highContrast ? "#4dffffff" : "#1fffffff"    // white 12 %, contrast 30 %
    readonly property color danger: highContrast ? "#ffb8b0" : "#ff9a90"
    readonly property color keyRed: "#e5484d"              // the red key of the remote in key hints
    readonly property color keyYellow: "#f2c94c"           // the yellow key, beside channelGreen and channelBlue
    readonly property color dangerFocused: highContrast ? "#a3190f" : "#c42b20"
    readonly property color warning: highContrast ? "#ffd2ab" : "#ffc08a"          // a second line that went wrong ("Verbindung fehlgeschlagen")
    readonly property color warningFocused: highContrast ? "#7a3400" : "#9a4300"
    // StatusCard: the card, the circle of its symbol, the circle of an error.
    readonly property color cardFill: highContrast ? "#24ffffff" : "#14ffffff"     // white 8 %, contrast 14 %
    readonly property color circleFill: highContrast ? "#3dffffff" : "#29ffffff"   // white 16 %, contrast 24 %
    readonly property color dangerCircle: highContrast ? "#52ff9a90" : "#38ff9a90" // danger 22 %, contrast 32 %
    // Profiles: LG's ten profile colours (/etc/accountmanager.d/profile.json), in LG's order.
    // The initial is dark on the two light ones, white on the rest.
    readonly property var profileColors: ["#7360E7", "#D84C75", "#9532E9", "#3DA287", "#355BD4",
                                          "#FCB214", "#00A2B8", "#F27121", "#ED45F4", "#339BDD"]
    readonly property var profileLightColors: ["#FCB214", "#F27121"]
    readonly property color profileInkDark: "#0b0c10"
    readonly property color profileInkLight: "#ffffff"
    readonly property real profileInitialShare: 0.44       // initial size per avatar size
    readonly property color profileRing: highContrast ? "#66ffffff" : "#47ffffff"  // inner light at the top, white 28 %
    // Plates without focus inside a list: a head block, a counter (K3-Einst-Geraeteliste).
    readonly property color plateFill: highContrast ? "#24ffffff" : "#12ffffff"    // white 7 %, contrast 14 %
    readonly property color chipFill: highContrast ? "#24ffffff" : "#14ffffff"     // white 8 %, contrast 14 %
    readonly property color chipCircle: highContrast ? "#33ffffff" : "#1fffffff"   // white 12 %, contrast 20 %
    readonly property color hintCircle: highContrast ? "#3dffffff" : "#24ffffff"   // white 14 %, the circle of a hint block
    readonly property color spinnerTrack: highContrast ? "#66ffffff" : "#38ffffff" // the ring of a spinner on glass
    // Fills of small glass elements (keys, tiles, chips, fields), from faint to latched, each
    // with its contrast step (K3-Einst-HoherKontrast-02: resting 10 → 18 %, chosen 18 → 28 %,
    // pressed 30 → 40 %). Same values as before when off.
    readonly property color fillFaint: plateFill                                    // 7 %
    readonly property color fillSoft: chipFill                                      // 8 %
    readonly property color fillRest: highContrast ? "#2effffff" : "#1affffff"     // 10 %
    readonly property color fillControl: highContrast ? "#33ffffff" : "#1fffffff"  // 12 %, GlassControl
    readonly property color fillRaised: highContrast ? "#3dffffff" : "#24ffffff"   // 14 %
    readonly property color fillActive: highContrast ? "#47ffffff" : "#29ffffff"   // 16 %
    readonly property color fillActiveStrong: highContrast ? "#47ffffff" : "#2effffff" // 18 %
    readonly property color fillSelected: highContrast ? "#4dffffff" : "#33ffffff" // 20 %
    readonly property color fillStrong: highContrast ? "#5cffffff" : "#3dffffff"   // 24 %
    readonly property color fillPressed: highContrast ? "#66ffffff" : "#40ffffff"  // 25 %
    readonly property color fillLatched: highContrast ? "#66ffffff" : "#47ffffff"  // 28 %
    readonly property color fillLatchedStrong: highContrast ? "#66ffffff" : "#4dffffff" // 30 %
    readonly property color fillOnFocus: highContrast ? "#290b0c10" : "#140b0c10"  // a plate on the focus surface
    // Lines and rings.
    readonly property color lineSoft: highContrast ? "#4dffffff" : "#1affffff"     // a hairline around a card
    readonly property color lineQuiet: highContrast ? "#4dffffff" : "#1fffffff"
    readonly property color lineLight: highContrast ? "#66ffffff" : "#47ffffff"    // around a thumbnail
    readonly property color lineMark: highContrast ? "#80ffffff" : "#52ffffff"     // around a status mark
    readonly property color lineHalf: highContrast ? "#ccffffff" : "#80ffffff"     // a frame that waits for focus
    readonly property color lineOnFocus: highContrast ? "#660b0c10" : "#400b0c10"
    // The ring of a chosen card (OptionCard), without the dark stroke of the focus ring.
    readonly property color optionRing: highContrast ? "#d9ffffff" : "#8cffffff"
    // Texts with their own strength, with their contrast step.
    readonly property color textHigh: highContrast ? "#f5ffffff" : "#d9ffffff"     // 85 %
    readonly property color textRaised: highContrast ? "#f2ffffff" : "#d1ffffff"   // 82 %, hero texts
    readonly property color textGlance: highContrast ? "#f2ffffff" : "#c7ffffff"   // 78 %, the clock
    readonly property color textCaption: highContrast ? "#ebffffff" : "#c2ffffff"  // 76 %
    readonly property color textCaptionMedia: highContrast ? "#ebffffff" : "#bdffffff" // 74 %, over a picture
    readonly property color textFaint: highContrast ? "#d1ffffff" : "#9effffff"    // 62 %
    readonly property color textHalf: highContrast ? "#c7ffffff" : "#80ffffff"     // 50 %
    readonly property color chevronIdle: textHalf                                   // a chevron at rest
    readonly property color stepDone: highContrast ? "#ffffffff" : "#ebffffff"     // a step reached (StepBar)
    // Greyed out: rows, switches and sliders that are locked; their reason stays readable.
    readonly property real disabledOpacity: highContrast ? 0.7 : 0.5
    // An icon that stands for something off (a device or input that is off), and one at rest.
    readonly property real iconDimmed: highContrast ? 0.78 : 0.55
    readonly property real iconQuiet: highContrast ? 0.78 : 0.6
    // The settings modal's own dimming over the picture.
    readonly property real backdropVeil: highContrast ? 0.52 : 0.38
    // Launcher and hub: the gradients under their texts (BackdropScrim), from the left and
    // from the top, and the hub's at the bottom.
    readonly property var launcherScrimLeft: highContrast ? [0.74, 0.44, 0.32] : [0.62, 0.30, 0.20]
    readonly property real launcherScrimTop: highContrast ? 0.58 : 0.45

    // Motion.
    readonly property var curve: [0.2, 0.8, 0.2, 1, 1, 1]
    readonly property int focusDuration: 220               // the focus surface and lists glide
    readonly property int focusFarDuration: 340            // the surface crosses a footer or a card row
    readonly property real focusFarDistance: 320           // logical px from which a jump counts as far
    readonly property int colorDuration: 120               // text and icons change colour
    readonly property int pageDuration: 240                // pages cross-fade with 16 px shift
    readonly property int slideDuration: 520               // a wizard page flies out, the next one in
    readonly property real pageShift: 16
    readonly property int popoverDuration: 160             // popovers, dimming, fades
    readonly property int listFadeDuration: 180            // a list end fades in or out
    readonly property int noticeDuration: 2500             // a short message stands, then goes
    readonly property int answerLimit: 5000                // a service that has not answered by then is not there
    readonly property int pressDuration: 40
    readonly property real dimmedOpacity: highContrast ? 0.55 : 0.4               // what steps back behind a popover
    // Dark layers over the picture. Glass lies on top of them and samples them too, as
    // backdrop-filter does: a surface on a dimmed picture must not glow from the undimmed one.
    readonly property color scrimColor: "#040608"
    readonly property real contentScrim: highContrast ? 0.32 : 0.18 // behind the panel; the grade holds 0.18
    readonly property real gradeScrim: 0.18                // what gradeShader holds of it (its constant)
    readonly property real modalScrim: highContrast ? 0.70 : 0.55                 // behind a modal
    readonly property real dialogScrim: 0.45               // over the settings card behind a device dialog
    // The boot look on black (BootGlow): its light breathes, and switching off dims it.
    readonly property int bootPulseDuration: 6000          // one breath of the light
    readonly property real bootPulseLow: 0.85              // its opacity at the low point
    readonly property real bootPulseSwell: 1.04            // its size at the high point
    readonly property int updateScreenLimit: 300000        // an install screen goes after this at the latest
    readonly property real shutdownDim: 0.55               // light and wordmark when switching off
    readonly property int shutdownInDuration: 400          // picture to the dimmed boot look
    readonly property int shutdownOutDuration: 500         // the boot look to black; the entry holds the rest
    readonly property int switchDuration: 260              // the knob of a switch springs over
    readonly property var switchCurve: [0.34, 1.36, 0.5, 1, 1, 1]
    // Type, in logical px.
    readonly property int titleSize: 32                    // page title in the panel
    readonly property int modalTitleSize: 40               // page title in the settings modal
    readonly property int rowSize: 22
    readonly property int valueSize: 18
    readonly property int detailSize: 17
    readonly property int pillTextSize: 20                 // status pill of background work
    readonly property int sectionSize: 16
    readonly property int hintTitleSize: 24                // title of a hint block ("Keine Geräte gefunden")
    readonly property int blockTextSize: 20                // text of a head block over a list
    readonly property int counterSize: 24                  // the number of a counter chip
    readonly property int counterLabelSize: 15            // its label below
    readonly property int dialogTitleSize: 34              // the name in the head of a device dialog
    readonly property int dialogTextSize: 20               // its state below
    readonly property int endCapSize: 17                   // "L" and "R" at the ends of a balance
    readonly property int badgeSize: 16                    // an outlined badge beside a title ("Dolby Atmos")
    readonly property real sectionTracking: 0.96          // 0.06 em, as in the hand-off
    readonly property int statSize: 34                     // a live value, for example of the game bar
    readonly property int statUnitSize: 15                 // its unit beside it
    readonly property int chipValueSize: 26                // the value of a chip, for example the genre
    readonly property int barTitleSize: 30                 // title of a bar over the picture (BandEditor)
    readonly property int barTitleCompactSize: 28          // the same in the taller white balance bar
    readonly property int bandValueSize: 24                // the value above a vertical slider, "+3"
    readonly property int bandLabelSize: 19                // the band below it, "1 kHz"
    readonly property int bandReasonSize: 15               // why a column is greyed, "Nur bei Stufe 100 %"
    readonly property int levelSize: 19                    // an entry of a level list in a bar, "90 %"
    readonly property int levelChosenSize: 22              // the chosen level, bold
    readonly property real levelRadius: 14                 // its plate, in logical px
    // "Fernbedienung erlernen" (K3-Einst-Fernbedienung): the key, its name, short and long.
    readonly property int guideKeySize: 168                // the key's plate
    readonly property int guideKeyIcon: 80
    readonly property int guideKeyLabel: 64                // "OK", "5" on the key
    readonly property int guideDot: 84                     // a colour key
    readonly property int guideNameSize: 48
    readonly property int guideStartTitle: 44
    readonly property int guideEffectSize: 28              // "Schnellmenü", and "Eine Taste drücken."
    readonly property int guideChipSize: 19                // "Kurz", "Lang"
    readonly property int guideMarkSize: 14                // "Platzhalter"
    readonly property int eyebrowSize: 18                  // the small title above a name, upper case
    readonly property color guideKeyFill: highContrast ? "#2effffff" : "#1affffff" // white 10 %, contrast 18 %
    readonly property color guideChipFill: highContrast ? "#47ffffff" : "#2effffff" // white 18 %, contrast 28 %
    readonly property color guideMarkLine: highContrast ? "#d9ffffff" : "#8cffffff" // white 55 %
    readonly property color guideMarkText: highContrast ? "#ffffffff" : "#dbffffff" // white 86 %
    readonly property color levelChosenFill: highContrast ? "#47ffffff" : "#2effffff" // its plate on glass: white 18 %
    readonly property color levelChosenFocused: highContrast ? "#330b0c10" : "#1a0b0c10" // on the focus surface: 10 %
    readonly property color textDisabled: highContrast ? "#a6ffffff" : "#66ffffff" // a greyed value: white 40 %, contrast 65 %
    // The colour channels beside a label ("Rot", "Grün", "Blau" of the white balance).
    readonly property color channelRed: "#e5484d"
    readonly property color channelGreen: "#3fbf8f"
    readonly property color channelBlue: "#4c9dff"
    // A bar over the picture at the bottom edge (K3-Einst-Equalizer), in logical px.
    readonly property real bottomBarInset: 56
    // A bar along the top edge (K3-Spiel-A-HUD), in logical px.
    readonly property real topBarInset: 48
    readonly property real topBarRadius: 44
    readonly property int chipRadius: 28
    readonly property int pillRadius: 32
    readonly property color divider: highContrast ? "#52ffffff" : "#24ffffff"      // white 14 %, between groups of a bar
    property alias blur: values.blur
    property alias keyboardMode: values.keyboardMode
    // High contrast makes the edge light stronger, never weaker.
    readonly property real edgeGain: Math.max(0.5, Math.min(2.5, Math.pow(referenceBlur / blur, 0.7))) *
                                     (highContrast ? 1.5 : 1)

    // Two dark layers of strength a and b darken as one of this strength.
    function stackScrims(a, b) {
        return 1 - (1 - a) * (1 - b);
    }

    // The veil a glass needs over a scrim of this strength, beyond the contentScrim that
    // its grade already holds. A weaker scrim gets none: the grade never brightens.
    function veilBeyondContent(total) {
        return Math.max(0, 1 - (1 - total) / (1 - gradeScrim));
    }

    // The veil the glass needs over the content scrim alone: 0, and with high contrast the
    // part of its stronger scrim that the grade does not hold.
    readonly property real contentVeil: veilBeyondContent(contentScrim)

    // A scrimColor layer of this strength, for gradients.
    function scrim(strength) {
        return Qt.rgba(scrimColor.r, scrimColor.g, scrimColor.b, strength);
    }

    // Inter in the three cuts of the hand-off, loaded once for every window. An app's build
    // puts fonts/novos-inter-*.ttf next to the folder that holds these files.
    readonly property string titleFont: titleLoader.name     // bold: titles
    readonly property string rowFont: rowLoader.name         // medium: rows, buttons
    // regular: values, second lines; with high contrast medium as the rows
    readonly property string valueFont: highContrast ? rowLoader.name : valueLoader.name
    property FontLoader titleLoader: FontLoader { source: Qt.resolvedUrl("../novos-inter-title.ttf") }
    property FontLoader rowLoader: FontLoader { source: Qt.resolvedUrl("../novos-inter-row.ttf") }
    property FontLoader valueLoader: FontLoader { source: Qt.resolvedUrl("../novos-inter-value.ttf") }

    // Kept in the app's settings file (UiConfig.js), shared by all its windows.
    property Settings values: Settings {
        id: values
        fileName: UiConfig.settingsFile
        property real blur: 84
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

    // Everything of the glass that is linear across the surface (the pixel, the place in the
    // backdrop, the sheen's position) is worked out per corner here and interpolated, so the
    // fragment shader reads the backdrop without computing its coordinates first. Every
    // ShaderEffect with glassShader sets this as its vertexShader.
    readonly property string glassVertexShader: "
                uniform highp mat4 qt_Matrix;
                uniform highp vec2 panelSize;
                uniform highp float backdropMargin;
                uniform highp vec2 backdropOrigin;
                uniform highp vec2 backdropArea;
                attribute highp vec4 qt_Vertex;
                attribute highp vec2 qt_MultiTexCoord0;
                varying highp vec2 qt_TexCoord0;
                varying highp vec2 pixel;
                varying highp vec2 uv;
                varying highp float sheenAt;

                void main() {
                    qt_TexCoord0 = qt_MultiTexCoord0;
                    pixel = qt_MultiTexCoord0 * panelSize;
                    uv = (pixel + backdropOrigin + vec2(backdropMargin)) /
                         (backdropArea + vec2(2.0 * backdropMargin));
                    highp float span = (panelSize.x + panelSize.y) * 0.70710678;
                    sheenAt = dot(pixel - panelSize * 0.5, vec2(0.70710678)) / span + 0.5;
                    gl_Position = qt_Matrix * qt_Vertex;
                }"

    readonly property string glassShader: "
                varying highp vec2 qt_TexCoord0;
                varying highp vec2 pixel;
                varying highp vec2 uv;
                varying highp float sheenAt;
                uniform lowp float qt_Opacity;
                uniform sampler2D backdrop;
                uniform highp vec2 panelSize;
                uniform highp float cornerRadius;
                uniform highp float topLightWidth;
                uniform highp float contourWidth;
                uniform highp float glowHeight;
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
                    highp vec2 halfSize = panelSize * 0.5;
                    highp vec2 point = pixel - halfSize;

                    lowp vec3 color = mix(fallback, texture2D(backdrop, uv).rgb, hasBackdrop);
                    lowp float alpha = mix(0.94, 1.0, hasBackdrop);

                    // linear-gradient(135deg, white 20 %, 7 % at 45 %, 13 %).
                    highp float t = sheenAt;
                    highp float sheen = t < 0.45 ? mix(0.20, 0.07, t / 0.45)
                                                 : mix(0.07, 0.13, (t - 0.45) / 0.55);
                    color = mix(color, vec3(1.0), sheen * hasBackdrop);
                    color *= 1.0 - dim;

                    // Hides 8-bit banding in dark blurred areas.
                    color += (noise(gl_FragCoord.xy) - 0.5) / 255.0;

                    // The edge work only runs near the edge. Most pixels of a
                    // large card never get here, which is what keeps it smooth.
                    // The glow fades out by the middle of the card, so below the
                    // middle only the corners and the contour itself need it.
                    highp float shape = 1.0;
                    highp vec2 inset = abs(point) - halfSize;
                    highp float nearest = max(inset.x, inset.y);
                    bool corner = min(inset.x, inset.y) > -cornerRadius;
                    bool rimBand = nearest > -(contourWidth + topLightWidth + 1.0);
                    bool glowBand = pixel.y < halfSize.y && nearest > -(cornerRadius + glowHeight);
                    if (corner || rimBand || glowBand) {
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

    // veil: a dark layer between the picture and the glass that the source does not hold
    // yet, such as the dimming behind a modal. Every ShaderEffect with it sets veil.
    readonly property string gradeShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform sampler2D source;
            uniform lowp float veil;

            const lowp vec3 scrim = vec3(0.0157, 0.0235, 0.0314);
            const lowp vec3 luma = vec3(0.2126, 0.7152, 0.0722);
            const highp float knee = 0.24;
            const highp float ceiling = 0.36;

            void main() {
                lowp vec3 color = texture2D(source, qt_TexCoord0).rgb;
                color = mix(color, scrim, 0.18);
                color = mix(color, scrim, veil);
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
}
