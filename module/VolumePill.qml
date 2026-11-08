import QtQuick 2.12
import "."

// Volume pill after the K3-Laut boards: a glass pill top centre, 56 px from the edge,
// 560 x 72, with symbol, bar and number. It takes no focus. Mute shows a short pill
// that shrinks to a round chip after 2 s; the chip stands as long as the sound is off.
//
// The owner reports every change of the sound with update(). The pill draws only what
// it is told: the volume view in the compositor feeds it from LS.audioService, the
// preview from a script. It fills the screen; everything outside the glass is empty.
Item {
    id: pill

    property real unit: Math.min(width / 1920, height / 1080)
    property string titleFamily: ""
    property string valueFamily: ""
    property string framePrefix: "/tmp/novos-volume-frame-"

    // What the sound does, as of the last update().
    property int volume: 0
    property int maximum: 100
    property bool muted: false
    property string output: "tv_speaker"
    property bool disabled: false
    property bool exterior: false          // the device keeps the value, we only know the key
    property string direction: ""          // "up" or "down" for an exterior device

    // "hidden", "level", "muted" (volume key while muted), "notice" (short pill) or "chip".
    property string look: "hidden"
    property string noticeIcon: ""
    property string noticeLabel: ""
    property string noticeText: ""
    property bool shown: false             // the glass is on screen or fading in
    property bool wanted: false            // a look waits to be shown
    readonly property bool active: wanted || shown || opacity > 0
    readonly property bool showsLevel: look === "level"

    readonly property int holdTime: 2000   // after the last change
    readonly property int stepTime: 120    // bar and number follow each step
    readonly property int morphTime: 240   // pill to chip and back, fade out
    readonly property int pictureWait: 250 // longest wait for the glass colour
    readonly property int chipRefresh: 4000
    readonly property var standardCurve: GlassStyle.curve

    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, volume / maximum)) : 0
    readonly property var device: deviceOf(output)

    opacity: shown ? (look === "chip" ? 0.85 : 1) : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: pill.shown ? pill.stepTime : pill.morphTime
            easing.type: Easing.Bezier
            easing.bezierCurve: pill.standardCurve
        }
    }

    // Outputs with a symbol and a name of their own. TV speakers have none.
    function deviceOf(name) {
        if (/^(headphone|bt_soundbar|tv_speaker_bluetooth|tv_speaker_bt_surround)$/.test(name))
            return { icon: "volume-headphones-30",
                     label: I18n.t("volume", name === "headphone" ? "label.headphones" : "label.bluetooth") };
        if (/^(external_arc|external_arc_sound_mode_sync|tv_speaker_external_arc_harmony|bt_atmos|wisa_speaker|flex_connector|wow_cast|tv_speaker_wow_cast)$/.test(name))
            return { icon: "volume-soundbar-30", label: I18n.t("volume", "label.soundbar") };
        if (/^(external_optical|lineout|urcu_oss)$/.test(name))
            return { icon: "volume-soundbar-30", label: I18n.t("volume", "label.audio_out") };
        return null;
    }

    // The symbol loses its waves as it gets quieter: two from 50, one below, none at 0.
    function levelIcon() {
        if (device) return device.icon;
        if (volume <= 0) return "volume-0-30";
        return fraction * 100 >= 50 ? "volume-2-30" : "volume-1-30";
    }

    function icon(name) {
        return name === "" ? "" : Qt.resolvedUrl("icons/" + name + ".png");
    }

    // state: { volume, maximum, muted, output, disabled, exterior, cause }
    function update(state) {
        var wasMuted = muted;
        var mutedNow = state.muted === true;
        volume = state.volume;
        maximum = state.maximum;
        output = state.output || "";
        disabled = state.disabled === true;
        exterior = state.exterior === true;
        direction = state.cause === "volumeUp" ? "up" : state.cause === "volumeDown" ? "down" : "";
        muted = mutedNow;

        if (disabled) {
            notice("volume-muted-30", "", I18n.t("volume", "notice.not_controllable"));
        } else if (muted && !wasMuted) {
            notice("volume-muted-30", "", I18n.t("volume", "notice.muted"));
        } else if (muted) {
            present("muted");
        } else if (exterior) {
            // The device keeps its value: name it and the direction of the key.
            // Without a key, as after a change from outside, only the device.
            var named = device || { icon: "volume-soundbar-30", label: I18n.t("volume", "label.audio_out") };
            if (direction === "") notice(named.icon, "", named.label);
            else notice(named.icon, named.label,
                        I18n.t("volume", direction === "down" ? "notice.quieter" : "notice.louder"));
        } else {
            present("level");
        }
    }

    function notice(iconName, label, text) {
        noticeIcon = iconName;
        noticeLabel = label;
        noticeText = text;
        present("notice");
    }

    function present(newLook) {
        look = newLook;
        wanted = true;
        holdTimer.restart();
        if (!backdropLoader.active) backdropLoader.active = true;
        else if (backdropLoader.item) {
            backdropLoader.item.resume();
            backdropLoader.item.requestNextFrame();
        }
        if (shown || (backdropLoader.item && backdropLoader.item.pictureReady)) shown = true;
        else pictureTimer.restart();
    }

    // The chip after a restart, without the pill before it.
    function showChip() {
        muted = true;
        look = "chip";
        wanted = true;
        holdTimer.stop();
        if (!backdropLoader.active) backdropLoader.active = true;
        pictureTimer.restart();
        chipPause.restart();
    }

    // LG's key filter asks to keep the pill while a key is held.
    function hold(keep) {
        if (keep) holdTimer.stop();
        else if (look !== "chip" && look !== "hidden") holdTimer.restart();
    }

    // Everything goes, the chip too.
    function dismiss() {
        holdTimer.stop();
        pictureTimer.stop();
        wanted = false;
        shown = false;
        releaseTimer.restart();
    }

    function refreshGlass() {
        if (look === "chip" && backdropLoader.item) backdropLoader.item.refresh();
    }

    Timer {
        id: holdTimer
        interval: pill.holdTime
        onTriggered: {
            if (pill.muted && !pill.disabled) {
                pill.look = "chip";
                chipPause.restart();
            } else {
                pill.dismiss();
            }
        }
    }

    // The chip keeps its picture once it has shrunk.
    Timer {
        id: chipPause
        interval: pill.morphTime
        onTriggered: if (pill.look === "chip" && backdropLoader.item) backdropLoader.item.pause()
    }

    Timer {
        id: chipRefreshTimer
        interval: pill.chipRefresh
        repeat: true
        running: pill.look === "chip" && pill.shown
        onTriggered: pill.refreshGlass()
    }

    // The glass shows the picture behind it from the start. Without one in time, the
    // fixed surface is better than a pill that comes late.
    Timer {
        id: pictureTimer
        interval: pill.pictureWait
        onTriggered: if (pill.wanted) pill.shown = true
    }

    Timer {
        id: releaseTimer
        interval: pill.morphTime + 60
        onTriggered: if (!pill.wanted) {
            pill.look = "hidden";
            backdropLoader.active = false;
        }
    }

    Loader {
        id: backdropLoader
        anchors.fill: parent
        active: false
        sourceComponent: LiveBackdrop {
            unit: pill.unit
            framePrefix: pill.framePrefix
            area: Qt.rect(pillArea.x, pillArea.y, pillArea.width, pillArea.height)
            opened: true
            shown: false            // never starts a video process of its own
            closing: !pill.wanted
            onReady: if (pill.wanted) pill.shown = true
        }
    }

    readonly property real pillWidth: 560 * unit
    readonly property real pillHeight: 72 * unit

    // The largest shape. The glass samples the backdrop relative to it.
    Item {
        id: pillArea
        x: (pill.width - width) / 2
        y: 56 * pill.unit
        width: pill.pillWidth
        height: pill.pillHeight

        readonly property real targetWidth: {
            if (pill.look === "chip") return 56 * pill.unit;
            if (pill.look === "notice") return noticeRow.width + 54 * pill.unit;
            return pill.pillWidth;
        }
        readonly property real targetHeight: (pill.look === "chip" ? 56 : 72) * pill.unit
        readonly property bool small: pill.look === "chip"

        SoftShadow {
            unit: pill.unit
            boxWidth: glass.width
            boxHeight: glass.height
            x: glass.x - 100 * pill.unit
            y: glass.y - 100 * pill.unit
            radius: (glass.height / 2) / pill.unit
            softness: pillArea.small ? 20 : 30
            drop: pillArea.small ? 16 : 24
            strength: pillArea.small ? 0.30 : 0.35
            pad: 100
        }

        GlassCard {
            id: glass
            x: (pillArea.width - width) / 2
            y: 0
            width: pillArea.targetWidth
            height: pillArea.targetHeight
            unit: pill.unit
            cornerRadius: height / 2
            glideDuration: pill.morphTime
            glideCurve: pill.standardCurve
            backdrop: backdropLoader.item ? backdropLoader.item.texture : null
            glassShader: GlassStyle.glassShader
            backdropMargin: backdropLoader.item ? backdropLoader.item.margin : 56 * pill.unit
            backdropArea: Qt.rect(0, 0, pillArea.width, pillArea.height)
            hasBackdrop: pictureShown
            shadow: ""

            // Fades in, so that a late picture does not jump onto the fixed surface.
            property real pictureShown: backdropLoader.item && backdropLoader.item.hasFrame ? 1 : 0
            Behavior on pictureShown {
                NumberAnimation { duration: pill.morphTime }
            }

            Item {
                anchors.fill: parent
                clip: true

                // Symbol, optional device, bar, number: K3-Laut-Mittel and -Stumm.
                Item {
                    id: levelContent
                    x: (parent.width - width) / 2
                    width: pill.pillWidth
                    height: pill.pillHeight
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: pill.look === "level" || pill.look === "muted" ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: pill.stepTime }
                    }

                    Image {
                        id: levelSymbol
                        x: 22 * pill.unit
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * pill.unit
                        height: 30 * pill.unit
                        smooth: true
                        opacity: pill.look === "muted" ? 0.7 : 1
                        source: pill.icon(pill.look === "muted" ? "volume-muted-30" : pill.levelIcon())
                    }

                    Text {
                        id: deviceLabel
                        x: levelSymbol.x + levelSymbol.width + 18 * pill.unit
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: pill.device && pill.look === "level" ? pill.device.label : ""
                        color: GlassStyle.textSecondary
                        font.family: pill.titleFamily
                        font.pixelSize: 17 * pill.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Rectangle {
                        id: track
                        x: (deviceLabel.visible ? deviceLabel.x + deviceLabel.width : levelSymbol.x + levelSymbol.width) +
                           18 * pill.unit
                        width: number.x - 18 * pill.unit - x
                        height: 10 * pill.unit
                        anchors.verticalCenter: parent.verticalCenter
                        radius: height / 2
                        color: "#33ffffff"
                        border.width: 1 * pill.unit
                        border.color: "#1aaab2c4"
                        clip: true

                        Rectangle {
                            height: parent.height
                            width: parent.width * pill.fraction
                            radius: parent.radius
                            color: pill.look === "muted" ? "#66ffffff" : "#ffffff"

                            Behavior on width {
                                NumberAnimation { duration: pill.stepTime; easing.type: Easing.OutQuad }
                            }
                        }
                    }

                    Text {
                        id: number
                        readonly property real minWidth: (pill.look === "muted" ? 64 : 40) * pill.unit
                        width: Math.max(minWidth, implicitWidth)
                        x: parent.width - 26 * pill.unit - width
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: pill.look === "muted" ? I18n.t("volume", "label.muted") : String(pill.volume)
                        color: "#ffffff"
                        font.family: pill.titleFamily
                        font.pixelSize: 22 * pill.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }

                // Short pill: K3-Laut-Mute, and the same shape for outputs without a value.
                Row {
                    id: noticeRow
                    x: 24 * pill.unit
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14 * pill.unit
                    opacity: pill.look === "notice" ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: pill.stepTime }
                    }

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * pill.unit
                        height: 30 * pill.unit
                        smooth: true
                        source: pill.icon(pill.noticeIcon)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: pill.noticeLabel
                        color: GlassStyle.textSecondary
                        font.family: pill.titleFamily
                        font.pixelSize: 17 * pill.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pill.noticeText
                        color: "#ffffff"
                        font.family: pill.titleFamily
                        font.pixelSize: 22 * pill.unit
                        font.hintingPreference: Font.PreferNoHinting
                    }
                }

                // K3-Laut-Mute-Dauer: only the symbol.
                Image {
                    anchors.centerIn: parent
                    width: 26 * pill.unit
                    height: 26 * pill.unit
                    smooth: true
                    source: pill.icon("volume-muted-26")
                    opacity: pill.look === "chip" ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: pill.stepTime }
                    }
                }
            }
        }
    }
}
