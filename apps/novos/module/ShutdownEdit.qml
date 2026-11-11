import QtQuick 2.12
import "."
import "ShutdownScreens.js" as ShutdownScreens

// Oberfläche › Ausschalt-Video › an own video or picture (K3-Ausschalt-6, "Zuschneiden"):
// on the left what plays, framed as chosen, and for a video the film strip with the part
// that plays (left and right move it, at most 15 s); on the right its length, the fade at
// the end and the framing (size, sideways, up and down). Delete, cancel, apply below.
// Nothing is stored until "Übernehmen"; that makes it the power-off video. Red plays the
// preview with the changes. The page draws its own focus surface: it has no catalog rows.
Item {
    id: page

    property real unit: 1
    property var owner: null              // the settings modal: back(), runAction(), hostAction()
    property var host: null               // SettingsData: saveShutdown()
    property string entryId: ""

    readonly property var stored: ShutdownScreens.entry(entryId, ShutdownScreens.ownEntries())
    readonly property bool video: stored.kind === "video"
    readonly property int full: video ? stored.full : 15000
    readonly property int longest: Math.min(15000, full)

    // The values on the page, from the stored ones.
    property int start: stored.start || 0
    property int length: stored.length || 3000
    property bool fade: stored.fade !== false
    property real zoom: stored.zoom || 1
    property real panX: stored.x || 0
    property real panY: stored.y || 0
    readonly property var changes: ({ start: start, length: length, fade: fade, zoom: zoom, x: panX, y: panY })
    readonly property var draft: ShutdownScreens.withChanges(stored, changes)

    function t(key, params) { return I18n.t("settings_interface", key, params); }
    function seconds(ms) {
        var count = Math.max(1, Math.round(ms / 1000));
        return count === 1 ? t("value.second") : t("value.seconds", { count: count });
    }
    function clock(ms) {
        var all = Math.round(ms / 1000);
        var rest = all % 60;
        return Math.floor(all / 60) + ":" + (rest < 10 ? "0" : "") + rest;
    }
    function signedPercent(value) {
        var rounded = Math.round(value * 100);
        return rounded === 0 ? t("value.edit_center") : (rounded > 0 ? "+" : "") + rounded + " %";
    }

    // ---- Focus: one list, up and down; left and right change the focused value ----
    readonly property bool movesX: preview.movesX || zoom > 1.001
    readonly property bool movesY: preview.movesY || zoom > 1.001
    readonly property var items: {
        var list = [];
        if (video) list.push("strip");
        list.push("length", "fade", "zoom");
        if (movesX) list.push("x");
        if (movesY) list.push("y");
        list.push("delete", "cancel", "apply");
        return list;
    }
    property string focusedItem: video ? "strip" : "length"
    readonly property bool onButtons: focusedItem === "delete" || focusedItem === "cancel" || focusedItem === "apply"

    function move(step) {
        var index = items.indexOf(focusedItem);
        if (onButtons && step > 0) return;
        if (onButtons) {
            focusedItem = items[items.indexOf("delete") - 1];
            return;
        }
        var next = index + step;
        if (next >= 0 && next < items.length) focusedItem = items[next] === "delete" ? "apply" : items[next];
    }

    function clampStart() {
        start = Math.max(0, Math.min(full - length, start));
    }

    // Returns false for a key it does not use; the modal then handles it (Left to the side bar).
    function handleKey(key, autoRepeat) {
        var item = focusedItem;
        var sideways = key === Qt.Key_Left ? -1 : (key === Qt.Key_Right ? 1 : 0);
        if (Remote.isRed(key)) {
            if (!autoRepeat && owner) owner.runAction("previewShutdown", { id: entryId, changes: changes });
        } else if (key === Qt.Key_Up) {
            move(-1);
        } else if (key === Qt.Key_Down) {
            move(1);
        } else if (sideways !== 0 && item === "strip") {
            start += sideways * 1000;
            clampStart();
        } else if (sideways !== 0 && item === "length") {
            length = Math.max(1000, Math.min(longest, length + sideways * 1000));
            clampStart();
        } else if (sideways !== 0 && item === "zoom") {
            zoom = Math.max(1, Math.min(3, Math.round((zoom + sideways * 0.1) * 10) / 10));
        } else if (sideways !== 0 && item === "x") {
            panX = Math.max(-1, Math.min(1, Math.round((panX + sideways * 0.1) * 10) / 10));
        } else if (sideways !== 0 && item === "y") {
            panY = Math.max(-1, Math.min(1, Math.round((panY + sideways * 0.1) * 10) / 10));
        } else if (sideways !== 0 && onButtons) {
            var buttons = ["delete", "cancel", "apply"];
            var at = buttons.indexOf(item) + sideways;
            if (at < 0) return false;
            if (at < buttons.length) focusedItem = buttons[at];
        } else if (Remote.isOk(key) && !autoRepeat) {
            activate(item);
        } else if (key === Qt.Key_Left) {
            return false;
        }
        return true;
    }

    function activate(item) {
        if (item === "fade") {
            fade = !fade;
        } else if (item === "apply") {
            if (host) host.saveShutdown(entryId, changes);
            if (owner) owner.back();
        } else if (item === "cancel") {
            if (owner) owner.back();
        } else if (item === "delete" && owner) {
            owner.hostAction("confirm", { action: "deleteShutdown", params: { id: entryId }, danger: true,
                                          title: t("confirm.delete_title", { name: stored.name }),
                                          text: t(video ? "confirm.delete_video" : "confirm.delete_image"),
                                          confirm: t("button.delete"), safe: false });
        }
    }

    // ---- Where things are, in logical px of the page ----
    readonly property real leftX: 20
    readonly property real previewWidth: 560
    readonly property real previewHeight: 315
    readonly property real stripY: previewHeight + 28
    readonly property real rightX: leftX + previewWidth + 28
    readonly property real rightWidth: 1120 - rightX - 20
    readonly property real rowsY: 74
    readonly property real footerY: 640

    function rowY(name) {
        var y = rowsY;
        var order = ["length", "fade", "zoom", "x", "y"];
        for (var i = 0; i < order.length; i++) {
            if (order[i] === name) return y;
            if (items.indexOf(order[i]) >= 0) y += rowHeight(order[i]) + 4;
        }
        return y;
    }
    function rowHeight(name) { return name === "fade" ? 68 : 96; }

    readonly property rect focusRect: {
        // On the strip the window shows the focus; the plate waits there, hidden, and glides
        // out of it to the next row.
        if (focusedItem === "strip") return Qt.rect(leftX, stripY, previewWidth, 88);
        if (onButtons) {
            var button = focusedItem === "delete" ? deleteButton : (focusedItem === "cancel" ? cancelButton : applyButton);
            return Qt.rect(button.x / unit, footerY, button.width / unit, 64);
        }
        return Qt.rect(rightX, rowY(focusedItem), rightWidth, rowHeight(focusedItem));
    }

    FocusSurface {
        x: page.focusRect.x * page.unit
        y: page.focusRect.y * page.unit
        width: page.focusRect.width * page.unit
        height: page.focusRect.height * page.unit
        visible: page.focusedItem !== "strip"
        unit: page.unit
        radius: page.onButtons ? 32 : 26
        focusScale: page.onButtons ? GlassStyle.focusScale : 1
    }

    // ---- What plays, framed as chosen ----
    Rectangle {
        id: previewPlate
        x: page.leftX * page.unit
        width: page.previewWidth * page.unit
        height: page.previewHeight * page.unit
        radius: 24 * page.unit
        color: "#000000"
        clip: true

        ShutdownFraming {
            id: preview
            anchors.fill: parent
            zoom: page.zoom
            panX: page.panX
            panY: page.panY
            mediaWidth: still.implicitWidth || 16
            mediaHeight: still.implicitHeight || 9

            Image {
                id: still
                anchors.fill: parent
                sourceSize: Qt.size(1280, 1280)
                asynchronous: true
                source: page.entryId === "" ? "" :
                        ShutdownScreens.frameUrl(page.draft, ShutdownScreens.frameAt(page.draft, page.start))
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#00ffffff"
            border.width: Math.max(1, page.unit)
            border.color: GlassStyle.lineQuiet
        }
    }

    // ---- The film strip with the part that plays (videos) ----
    Item {
        x: page.leftX * page.unit
        y: page.stripY * page.unit
        width: page.previewWidth * page.unit
        height: 124 * page.unit
        visible: page.video

        Row {
            id: strip
            width: parent.width
            height: 88 * page.unit
            clip: true

            Repeater {
                model: page.video ? 6 : 0

                Image {
                    readonly property real at: index / 6 * page.full
                    width: strip.width / 6
                    height: strip.height
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(240, 135)
                    asynchronous: true
                    source: ShutdownScreens.frameUrl(page.stored, Math.round(index * (page.stored.frames - 1) / 5))
                    opacity: at + page.full / 6 > page.start && at < page.start + page.length ? 1 : 0.38
                }
            }
        }

        // The window: white when the strip has the focus.
        Rectangle {
            x: page.start / page.full * strip.width - 4 * page.unit
            y: -4 * page.unit
            width: page.length / page.full * strip.width + 8 * page.unit
            height: strip.height + 8 * page.unit
            radius: 18 * page.unit
            color: "#00ffffff"
            border.width: 4 * page.unit
            border.color: page.focusedItem === "strip" ? "#ffffff" : GlassStyle.lineHalf

            Behavior on x { NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve } }
            Behavior on width { NumberAnimation { duration: GlassStyle.focusDuration; easing.type: Easing.Bezier; easing.bezierCurve: GlassStyle.curve } }
        }

        Item {
            y: strip.height + 14 * page.unit
            width: parent.width
            height: 22 * page.unit

            Text {
                text: "0:00"
                color: GlassStyle.textSecondary
                font.family: GlassStyle.valueFont
                font.pixelSize: 17 * page.unit
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.t("edit.window", { from: page.clock(page.start), to: page.clock(page.start + page.length),
                                              length: page.seconds(page.length) })
                color: GlassStyle.textPrimary
                font.family: GlassStyle.titleFont
                font.pixelSize: 17 * page.unit
            }

            Text {
                anchors.right: parent.right
                text: page.clock(page.full)
                color: GlassStyle.textSecondary
                font.family: GlassStyle.valueFont
                font.pixelSize: 17 * page.unit
            }
        }
    }

    // ---- Name and the values ----
    Column {
        x: page.rightX * page.unit + 20 * page.unit
        y: 6 * page.unit
        spacing: 6 * page.unit

        Text {
            text: page.stored.name || ""
            color: GlassStyle.textPrimary
            font.family: GlassStyle.titleFont
            font.pixelSize: 26 * page.unit
        }

        Text {
            text: page.video ? page.t("edit.meta_video", { length: page.seconds(page.full) }) : page.t("edit.meta_image")
            color: GlassStyle.textSecondary
            font.family: GlassStyle.valueFont
            font.pixelSize: 18 * page.unit
        }
    }

    Repeater {
        model: [
            { name: "length", title: page.t("row.edit_length"), value: page.seconds(page.length),
              share: (page.length - 1000) / Math.max(1, page.longest - 1000) },
            { name: "fade", title: page.t("row.edit_fade"), toggle: page.fade },
            { name: "zoom", title: page.t("row.edit_zoom"), value: Math.round(page.zoom * 100) + " %",
              share: (page.zoom - 1) / 2 },
            { name: "x", title: page.t("row.edit_x"), value: page.signedPercent(page.panX), share: (page.panX + 1) / 2 },
            { name: "y", title: page.t("row.edit_y"), value: page.signedPercent(page.panY), share: (page.panY + 1) / 2 }
        ]

        GlassRow {
            x: page.rightX * page.unit
            y: page.rowY(modelData.name) * page.unit
            width: page.rightWidth * page.unit
            height: page.rowHeight(modelData.name) * page.unit
            visible: page.items.indexOf(modelData.name) >= 0
            unit: page.unit
            titleFont: GlassStyle.rowFont
            valueFont: GlassStyle.valueFont
            focused: page.focusedItem === modelData.name
            title: modelData.title
            value: modelData.value || ""
            toggle: modelData.toggle
            sliderShare: modelData.share !== undefined ? Math.max(0, Math.min(1, modelData.share)) : -1
        }
    }

    // ---- Delete on the left, cancel and apply on the right ----
    FooterButton {
        id: deleteButton
        x: page.leftX * page.unit
        y: page.footerY * page.unit
        unit: page.unit
        fontFamily: GlassStyle.rowFont
        label: page.t("button.delete")
        danger: true
        focused: page.focusedItem === "delete"
    }

    Text {
        x: (page.leftX + 24) * page.unit + deleteButton.width
        y: page.footerY * page.unit
        height: 64 * page.unit
        verticalAlignment: Text.AlignVCenter
        width: cancelButton.x - x - 24 * page.unit
        elide: Text.ElideRight
        text: page.video ? page.t("edit.hint_video") : page.t("edit.hint_image")
        color: GlassStyle.textSecondary
        font.family: GlassStyle.valueFont
        font.pixelSize: 17 * page.unit
    }

    FooterButton {
        id: cancelButton
        x: applyButton.x - width - 12 * page.unit
        y: page.footerY * page.unit
        unit: page.unit
        fontFamily: GlassStyle.rowFont
        label: page.t("button.cancel")
        focused: page.focusedItem === "cancel"
    }

    FooterButton {
        id: applyButton
        x: (1120 - 20) * page.unit - width
        y: page.footerY * page.unit
        unit: page.unit
        fontFamily: GlassStyle.rowFont
        label: page.t("button.apply")
        focused: page.focusedItem === "apply"
    }
}
