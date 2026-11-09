import QtQuick 2.12
import "."

// Oberfläche › Ausschalt-Video › Video hinzufügen (K3-Ausschalt-5): a QR code that leads a
// phone or computer in the same network to the upload page the TV serves while this page
// is open, three steps, and the transfer live. bin/novos-upload.py does the serving; the
// supervisor starts it for the "open" this page leaves in /tmp/novos-upload/command.ini.
// A new video or picture becomes the power-off video at once.
Item {
    id: page

    property real unit: 1
    property var owner: null              // the settings modal
    property var host: null               // SettingsData: refreshShutdown(), writeNovos()

    function t(key, params) { return I18n.t("settings_interface", key, params); }
    // In MB with one decimal; a small file shows 0.1 rather than 0.0.
    function megabytes(bytes) {
        var tenths = bytes > 0 ? Math.max(1, Math.round(bytes / 104857.6)) : 0;
        return (tenths / 10).toLocaleString(Qt.locale(), "f", 1);
    }

    readonly property var info: bridge.info
    readonly property bool serving: info.serving === true && bridge.answeredId === bridge.sentId
    readonly property string phase: serving ? String(info.phase || "waiting") :
                                    (bridge.answeredId === bridge.sentId && info.phase ? String(info.phase) : "starting")
    readonly property var upload: info.upload || ({})
    // A video comes as frames (frames, done), a picture as bytes (size, received).
    readonly property real share: upload.frames > 0 ? upload.done / upload.frames :
                                  (upload.size > 0 ? upload.received / upload.size : 0)
    readonly property var added: info.added || []
    readonly property string address: String(info.url || "").replace(/^http:\/\//, "")
    readonly property bool sending: phase === "receiving" || phase === "done"
    property string doneName: ""

    SetupBridge {
        id: bridge
        folder: "/tmp/novos-upload"
        active: true
    }

    Component.onCompleted: bridge.send("open")
    Component.onDestruction: bridge.send("close")

    // A new file is the power-off video at once; a later still only redraws its tile. Reads
    // the fresh state itself: the properties derived from it may still hold the last one.
    property int seenRevision: 0
    property int seenAdded: 0
    onInfoChanged: {
        var state = info || {};
        // Only the answer to this page's own "open", not what an earlier visit left.
        if (String(state.id || "") !== bridge.sentId || !host) return;
        var revision = Number(state.revision || 0);
        if (revision === seenRevision) return;
        seenRevision = revision;
        var list = state.added || [];
        if (list.length > seenAdded) {
            host.writeNovos("shutdownScreen", String(list[list.length - 1]));
            doneName = state.upload && state.upload.name ? String(state.upload.name) : "";
        }
        seenAdded = list.length;
        host.refreshShutdown();
    }

    Row {
        x: 20 * page.unit
        spacing: 40 * page.unit

        // The code on white, as phones read it best.
        Rectangle {
            width: 332 * page.unit
            height: width
            radius: 28 * page.unit
            color: "#ffffff"

            Image {
                anchors.centerIn: parent
                width: 296 * page.unit
                height: width
                visible: page.serving && String(page.info.qr || "") !== ""
                source: visible ? "file://" + page.info.qr : ""
                cache: false
                smooth: false
                fillMode: Image.PreserveAspectFit
            }

            Spinner {
                anchors.centerIn: parent
                visible: page.phase === "starting"
                running: visible
                dark: true
            }
        }

        Column {
            width: 1080 * page.unit - 332 * page.unit - 40 * page.unit - 40 * page.unit
            spacing: 18 * page.unit

            Repeater {
                model: [
                    { title: page.t("upload.step_scan"),
                      detail: page.address !== "" ? page.t("upload.step_scan_detail", { address: page.address }) : "",
                      done: page.sending },
                    { title: page.t("upload.step_choose"),
                      detail: !page.upload.name ? "" : page.upload.size > 0 ?
                              page.t("upload.step_choose_detail", { name: page.upload.name, size: page.megabytes(page.upload.size) + " MB" }) :
                              page.upload.name,
                      done: page.sending },
                    { title: page.t(page.phase === "done" ? "upload.step_sent" : "upload.step_send"), detail: "",
                      done: page.phase === "done" }
                ]

                Row {
                    spacing: 16 * page.unit

                    Rectangle {
                        width: 32 * page.unit
                        height: width
                        radius: width / 2
                        color: modelData.done ? GlassStyle.accent : "#29ffffff"

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
                            font.pixelSize: 16 * page.unit
                        }
                    }

                    Column {
                        spacing: 2 * page.unit

                        Text {
                            text: modelData.title
                            color: GlassStyle.textPrimary
                            font.family: GlassStyle.rowFont
                            font.pixelSize: 22 * page.unit
                        }

                        Text {
                            visible: text !== ""
                            text: modelData.detail
                            color: GlassStyle.textSecondary
                            font.family: GlassStyle.valueFont
                            font.pixelSize: 18 * page.unit
                        }
                    }
                }
            }

            // The transfer as it arrives.
            Column {
                x: 48 * page.unit
                width: parent.width - x
                spacing: 10 * page.unit
                visible: page.phase === "receiving"

                Item {
                    width: parent.width
                    height: 24 * page.unit

                    Text {
                        text: page.upload.frames > 0 ?
                              page.t("upload.progress_frames", { done: page.upload.done || 0, total: page.upload.frames }) :
                              page.t("upload.progress", { received: page.megabytes(page.upload.received || 0),
                                                          size: page.megabytes(page.upload.size || 0) })
                        color: "#d1ffffff"
                        font.family: GlassStyle.valueFont
                        font.pixelSize: 18 * page.unit
                    }

                    Text {
                        anchors.right: parent.right
                        text: Math.round(page.share * 100) + " %"
                        color: "#d1ffffff"
                        font.family: GlassStyle.titleFont
                        font.pixelSize: 18 * page.unit
                    }
                }

                ProgressBar {
                    width: parent.width
                    unit: page.unit
                    barHeight: 10
                    value: page.share
                }
            }

            // What happened, or what to know.
            Text {
                x: 48 * page.unit
                width: parent.width - x
                wrapMode: Text.WordWrap
                text: page.phase === "done" ? page.t("upload.done", { name: page.doneName }) :
                      page.phase === "expired" || page.phase === "closed" ? page.t("upload.expired") :
                      page.info.error === "network" ? page.t("upload.network") :
                      page.phase === "error" ? page.t("upload.error") :
                      page.t("upload.note")
                color: GlassStyle.textSecondary
                font.family: GlassStyle.valueFont
                font.pixelSize: 18 * page.unit
                lineHeight: 1.45
            }

            Text {
                x: 48 * page.unit
                width: parent.width - x
                wrapMode: Text.WordWrap
                text: page.t("upload.limits")
                color: GlassStyle.textMuted
                font.family: GlassStyle.valueFont
                font.pixelSize: 17 * page.unit
                lineHeight: 1.45
            }
        }
    }
}
