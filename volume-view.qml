import QtQuick 2.12
import WebOSCompositorBase 1.0
import WebOSCompositor 1.0
import "module"

// Our volume pill in place of LG's volume view. The release mounts this file over
// /usr/lib/qml/WebOSCompositor/views/StarfishVolumeView.qml. It is our own file, not a
// copy of LG's: it keeps only what the compositor calls on the view (muteStr,
// requestTts, setLocaleInfo, handleVolumeBannerTimeout and BaseView's opened) and
// draws module/VolumePill.qml. LG's key filter still changes the volume, this view
// only shows it.
BaseView {
    id: root

    // LG's switches for the volume display, read the same way LG's view reads them.
    property bool adjWBStatus: (Settings.subscribe("com.webos.service.factorymanager", "getFactoryOpt",
                                                   {"keys": ["adjWBStatus"]}) || "false") === "true"
    property bool volumeOSD: Settings.subscribe("com.webos.service.config", "getConfigs",
                                                {"configNames": ["com.webos.surfacemanager.volumeOSD"]}) !== false
    property var powerStateObj: Settings.subscribe("com.webos.service.tvpower", "power2/getPowerState", {}) || ({})
    readonly property bool poweringOff: powerStateObj["sub processing"] === "prepare power off" &&
                                        powerStateObj["next sub state"] === "suspend"
    readonly property bool available: volumeOSD && !poweringOff && !adjWBStatus

    // Read by LG's key filter for Audio-Guidance on the mute key.
    property string muteStr: I18n.t("volume", "speech.muted")
    property var localeInfo: ({})

    signal requestTts(string text, bool delayed)

    function setLocaleInfo(info) {
        if (info) localeInfo = info;
    }

    // From LG's key filter: false while a volume key is held, true once it is let go.
    function handleVolumeBannerTimeout(restart) {
        pill.hold(!restart);
    }

    // Outputs whose device keeps the value; volumeSyncable means it reports it back.
    function exterior(audio) {
        var external = /^(external_optical|external_arc|external_arc_sound_mode_sync|lineout|urcu_oss|tv_speaker_external_arc_harmony|wow_cast|tv_speaker_wow_cast)$/
                       .test(audio.soundOutput) || audio.ossActivate === true;
        return external && audio.volumeSyncable !== true;
    }

    function update() {
        var audio = LS.audioService;
        // LG's view stays empty in the internal mode as well.
        if (audio.mode === "internal") return;
        var wasOpen = pill.shown;
        pill.update({
            volume: audio.volume,
            maximum: audio.volumeMax,
            muted: audio.muted,
            output: audio.soundOutput,
            disabled: audio.disabled,
            exterior: exterior(audio),
            cause: audio.cause
        });
        speak(audio, wasOpen);
    }

    // Like LG's view: the word "volume" on the first press, then the value or the direction.
    function speak(audio, wasOpen) {
        if (audio.disabled) {
            requestTts(I18n.t("volume", "notice.not_controllable"), false);
            return;
        }
        if (audio.muted) return;
        if (!wasOpen) requestTts(I18n.t("volume", "speech.volume"), false);
        if (pill.showsLevel) requestTts(String(audio.volume), !wasOpen);
        else if (pill.direction !== "")
            requestTts(I18n.t("volume", pill.direction === "down" ? "notice.quieter" : "notice.louder"), !wasOpen);
    }


    VolumePill {
        id: pill
        anchors.fill: parent
        titleFamily: GlassStyle.titleFont
        valueFamily: GlassStyle.valueFont
        onActiveChanged: active ? root.openView() : root.closeView()
    }

    Connections {
        target: LS.audioService
        onVolumeUpdated: if (root.available) root.update()
    }

    onAvailableChanged: if (!available) pill.dismiss()

    // The chip stands as long as the sound is off. In case the sound comes back
    // without volumeUpdated, it checks by itself.
    Timer {
        interval: 2000
        repeat: true
        running: pill.look === "chip"
        onTriggered: if (!LS.audioService.muted) pill.dismiss()
    }

    // After a restart of surface-manager the sound may already be off.
    Timer {
        interval: 3000
        running: true
        onTriggered: if (root.available && LS.audioService.muted && pill.look === "hidden") pill.showChip()
    }
}
