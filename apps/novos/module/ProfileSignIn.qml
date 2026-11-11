import QtQuick 2.12
import "."

// Profile › Profil hinzufügen (K3-Profil-Anmelden-Code, -Offline): LG's own way of signing
// in with a phone. LG gives a short code and an address; the phone signs in there with an
// LG or Google account, and the TV takes the account over. bin/novos-login.py talks to
// LG; the supervisor starts it for the "code" this page leaves in /tmp/novos-login.
// The password never passes through the TV. See docs/profile-sign-in.md.
Item {
    id: page

    property real unit: 1
    property var owner: null            // the settings modal
    property var host: null             // SettingsData

    readonly property var info: bridge.info
    readonly property bool mine: String(info.id || "") === bridge.sentId && bridge.sentId !== ""
    readonly property string phase: mine ? String(info.phase || "starting") : "starting"
    readonly property string code: String(info.code || "")
    readonly property string address: String(info.url || "").replace(/^https?:\/\//, "")
    property real now: Date.now()
    readonly property int secondsLeft: Math.max(0, Math.round(Number(info.expires || 0) - now / 1000))

    // The buttons of the current state, left to right.
    readonly property var buttons: phase === "offline" ? ["network", "retry"] :
                                   (phase === "error" || phase === "expired") ? ["retry"] :
                                   phase === "waiting" ? ["newCode"] : []
    property int buttonIndex: 0
    onButtonsChanged: buttonIndex = Math.min(buttonIndex, Math.max(0, buttons.length - 1))

    function t(key, params) { return I18n.t("profile", key, params); }

    function spacedCode(text) {
        return text.split("").join(" ");
    }

    function remaining() {
        var minutes = Math.floor(secondsLeft / 60);
        var seconds = secondsLeft % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function requestCode() {
        bridge.send("code");
    }

    function press(name) {
        if (name === "network" && owner) owner.runAction("openNetwork", {});
        else requestCode();
    }

    function handleKey(key, autoRepeat) {
        if (buttons.length === 0) return key !== Qt.Key_Left;
        if (key === Qt.Key_Left && buttonIndex > 0) buttonIndex--;
        else if (key === Qt.Key_Right && buttonIndex < buttons.length - 1) buttonIndex++;
        else if (Remote.isOk(key) && !autoRepeat) press(buttons[buttonIndex]);
        else if (key === Qt.Key_Left) return false;
        return true;
    }

    SetupBridge {
        id: bridge
        folder: "/tmp/novos-login"
        active: true
    }

    Component.onCompleted: requestCode()
    Component.onDestruction: bridge.send("close")

    // Signed in: back to the profiles, where the new one now stands as the active profile.
    onPhaseChanged: if (phase === "done" && owner) owner.back()

    Timer {
        interval: 1000
        repeat: true
        running: page.phase === "waiting"
        onTriggered: page.now = Date.now()
    }

    // ---- With a code ---------------------------------------------------------------------
    Row {
        x: 20 * page.unit
        spacing: 40 * page.unit
        visible: page.phase === "starting" || page.phase === "waiting" || page.phase === "finishing"

        // The code on white, as phones read it best.
        Rectangle {
            width: 332 * page.unit
            height: width
            radius: 28 * page.unit
            color: GlassStyle.textPrimary

            Image {
                anchors.centerIn: parent
                width: 296 * page.unit
                height: width
                visible: page.phase === "waiting" && String(page.info.qr || "") !== ""
                source: visible ? "file://" + page.info.qr : ""
                cache: false
                smooth: false
                fillMode: Image.PreserveAspectFit
            }

            Spinner {
                anchors.centerIn: parent
                visible: page.phase !== "waiting"
                running: visible
                dark: true
            }
        }

        Column {
            width: 1080 * page.unit - 332 * page.unit - 40 * page.unit - 40 * page.unit
            spacing: 18 * page.unit

            Repeater {
                model: [
                    { title: page.t("signin.step_scan"),
                      detail: page.code !== "" ? page.t("signin.step_scan_detail",
                                                        { address: page.address, code: page.spacedCode(page.code) }) :
                              page.t("signin.waiting"),
                      done: page.phase === "finishing" },
                    { title: page.t("signin.step_account"), detail: "", done: page.phase === "finishing" },
                    { title: page.t("signin.step_done"),
                      detail: page.phase === "finishing" ? page.t("signin.finishing") : page.t("signin.step_done_detail"),
                      done: false }
                ]

                Row {
                    spacing: 16 * page.unit

                    Rectangle {
                        width: 32 * page.unit
                        height: width
                        radius: width / 2
                        color: modelData.done ? GlassStyle.accent : GlassStyle.circleFill

                        Image {
                            anchors.centerIn: parent
                            visible: modelData.done
                            source: visible ? Qt.resolvedUrl("icons/check-18.png") : ""
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !modelData.done
                            text: String(index + 1)
                            color: GlassStyle.textPrimary
                            font.family: GlassStyle.titleFont
                            font.pixelSize: GlassStyle.sectionSize * page.unit
                        }
                    }

                    Column {
                        spacing: 2 * page.unit

                        Text {
                            text: modelData.title
                            color: GlassStyle.textPrimary
                            font.family: GlassStyle.rowFont
                            font.pixelSize: GlassStyle.rowSize * page.unit
                        }

                        Text {
                            visible: text !== ""
                            text: modelData.detail
                            color: GlassStyle.textSecondary
                            font.family: GlassStyle.valueFont
                            font.pixelSize: GlassStyle.valueSize * page.unit
                        }
                    }
                }
            }

            // The code once more, large, for typing it on a computer.
            Text {
                x: 48 * page.unit
                visible: page.code !== ""
                text: page.spacedCode(page.code)
                color: GlassStyle.textPrimary
                font.family: GlassStyle.titleFont
                font.pixelSize: 44 * page.unit
                font.letterSpacing: 4 * page.unit
            }

            Text {
                x: 48 * page.unit
                width: parent.width - x
                visible: page.phase === "waiting"
                wrapMode: Text.WordWrap
                text: page.t("signin.valid", { time: page.remaining() })
                color: GlassStyle.textMuted
                font.family: GlassStyle.valueFont
                font.pixelSize: GlassStyle.detailSize * page.unit
            }
        }
    }

    // ---- Without internet, or when LG did not answer (K3-Profil-Anmelden-Offline) ----------
    Column {
        x: 20 * page.unit
        width: 760 * page.unit
        spacing: 12 * page.unit
        visible: page.phase === "offline" || page.phase === "error" || page.phase === "expired"

        Rectangle {
            width: 64 * page.unit
            height: width
            radius: width / 2
            color: GlassStyle.circleFill

            Image {
                anchors.centerIn: parent
                source: Qt.resolvedUrl(page.phase === "offline" ? "icons/wifi-off-32.png" : "icons/status-alert-32.png")
            }
        }

        Text {
            text: page.phase === "offline" ? page.t("signin.offline") :
                  page.phase === "expired" ? page.t("signin.new_code") : page.t("signin.error")
            color: GlassStyle.textPrimary
            font.family: GlassStyle.titleFont
            font.pixelSize: 28 * page.unit
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.phase === "offline" ? page.t("signin.offline_detail") : page.t("signin.error_detail")
            color: GlassStyle.textSecondary
            font.family: GlassStyle.valueFont
            font.pixelSize: GlassStyle.valueSize * page.unit
            lineHeight: 1.35
        }
    }

    // Buttons of the state: a new code, the network settings, trying again.
    Row {
        x: 20 * page.unit
        y: (page.phase === "waiting" ? 372 : 260) * page.unit
        spacing: 12 * page.unit

        Repeater {
            model: page.buttons

            FooterButton {
                unit: page.unit
                size: 60
                ownFocus: true
                fontFamily: GlassStyle.rowFont
                focused: index === page.buttonIndex
                label: modelData === "network" ? page.t("signin.open_network") :
                       modelData === "newCode" ? page.t("signin.new_code") : page.t("signin.retry")
                onClicked: page.press(modelData)
            }
        }
    }
}
