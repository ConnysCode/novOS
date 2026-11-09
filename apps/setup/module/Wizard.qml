import QtQuick 2.12

// The running setup: pages in order, focus moved with the remote, actions sent to
// novos-setupd serve through SetupBridge, and pages that follow the service's state.
//
//   flow "install"  welcome, channel, check, what changes, privacy, keyboard and updates,
//                   summary, progress, restart, done (after the window was opened again)
//   flow "update"   what is new, progress, restart
//   flow "remove"   confirm, progress, farewell
//
// Privacy choices are only collected: novOS does not switch LG's values yet.
Item {
    id: wizard

    property real unit: 1
    property string flow: "install"
    property bool reopened: false
    signal close()

    property string page: ""
    property string focusId: ""
    property var privacy: [false, false, false, false]
    property string keyboard: "qwertz"
    // Stabil or Beta: the check looks there, the install keeps it for every later update.
    // It starts as the service's channel (stable, or beta while stable has no release).
    property string channel: "stable"
    property bool autoUpdate: true
    property bool blockUpdates: true
    property bool deleteData: true
    property bool choicesRead: false

    function tr(key, params) { return I18n.t("setup", key, params); }
    // Ends novos-setupd serve; the window closes itself afterwards.
    function finish() { bridge.send("close"); }
    function mb(bytes) { return Math.round((bytes || 0) / 1000000); }

    SetupBridge { id: bridge }

    SetupStage {
        anchors.fill: parent
        visible: wizard.page !== ""
        unit: wizard.unit
        slideId: wizard.page
        live: wizard.live
    }

    // ---- focus ---------------------------------------------------------------------------

    readonly property var checkResult: bridge.result && bridge.result.check ? bridge.result.check : null
    readonly property bool checking: bridge.busy && bridge.info.command === "check"
    readonly property bool checkFailed: !checking && bridge.info.command === "check" && bridge.phase === "error"
    readonly property bool canInstall: checkResult !== null && checkResult.newer === true &&
                                       (checkResult.problems || []).length === 0

    function grid() {
        switch (page) {
        case "install-1": return [["cancel", "start"]];
        case "install-channel": return [["stable", "beta"], ["back", "next"]];
        // A disabled "next" takes no focus.
        case "install-2": return [checkFailed ? ["back", "retry"] : (canInstall ? ["back", "next"] : ["back"])];
        case "install-3": return [["back", "next"]];
        case "install-4": return [["row0"], ["row1"], ["row2"], ["row3"], ["back", "next"]];
        case "install-5": return [["qwertz", "t9"], ["auto"], ["block"], ["back", "next"]];
        case "install-6": return [["back", "install"]];
        case "install-9": return [["home"]];
        case "install-x": return [["close", "retry"]];
        case "update-2": return [canInstall ? ["later", "now"] : ["later"]];
        case "remove-2": return [["data"], ["cancel", "remove"]];
        default: return [];
        }
    }

    function defaultFocus() {
        switch (page) {
        case "install-1": return "start";
        case "install-channel": return channel;
        case "install-2": return canInstall ? "next" : "back";
        case "install-4": return "row0";
        case "install-5": return keyboard;
        case "install-6": return "install";
        case "install-9": return "home";
        case "install-x": return "retry";
        case "update-2": return canInstall ? "now" : "later";
        case "remove-2": return "cancel";
        default: return grid().length > 0 ? "next" : "";
        }
    }

    // The footer button that takes the page forward. A destructive page keeps "cancel", as
    // its focus starts there too (docs/design-system.md).
    function footerAction() {
        var rows = grid();
        if (rows.length === 0) return "";
        var footer = rows[rows.length - 1];
        if (page === "remove-2") return "cancel";
        return footer[footer.length - 1];
    }

    function go(next) {
        page = next;
        focusId = defaultFocus();
    }

    function move(dx, dy) {
        var rows = grid();
        for (var r = 0; r < rows.length; ++r) {
            var c = rows[r].indexOf(focusId);
            if (c < 0) continue;
            if (dx !== 0) {
                var nc = Math.max(0, Math.min(rows[r].length - 1, c + dx));
                focusId = rows[r][nc];
            } else {
                var nr = Math.max(0, Math.min(rows.length - 1, r + dy));
                // Down from the content into the footer lands on the page's action.
                if (nr !== r && nr === rows.length - 1 && rows[nr].indexOf(footerAction()) >= 0)
                    focusId = footerAction();
                else
                    focusId = rows[nr][Math.min(c, rows[nr].length - 1)];
            }
            return;
        }
        focusId = defaultFocus();
    }

    // The check starts once the check page has flown in: its first answers rebuild the page,
    // which cost a frame in the middle of the motion.
    Timer {
        id: checkLater
        interval: GlassStyle.slideDuration + 120
        onTriggered: if (wizard.page === "install-2") bridge.send("check", { source: wizard.channel })
    }

    function choiceValues() {
        return { source: channel, keyboard: keyboard, autoUpdate: autoUpdate ? "on" : "off",
                 blockUpdates: blockUpdates ? "on" : "off" };
    }

    function activate() {
        var id = focusId;
        switch (page) {
        case "install-1":
            if (id === "cancel") wizard.close();
            else go("install-channel");
            break;
        case "install-channel":
            if (id === "stable" || id === "beta") channel = id;
            else if (id === "back") go("install-1");
            else { go("install-2"); checkLater.restart(); }
            break;
        case "install-2":
            if (id === "back") go("install-channel");
            else if (id === "retry") bridge.send("check", { source: channel });
            else if (canInstall) go("install-3");
            break;
        case "install-3":
            go(id === "back" ? "install-2" : "install-4");
            break;
        case "install-4":
            if (id.indexOf("row") === 0) {
                var values = privacy.slice();
                var index = Number(id.slice(3));
                values[index] = !values[index];
                privacy = values;
            } else go(id === "back" ? "install-3" : "install-5");
            break;
        case "install-5":
            if (id === "qwertz" || id === "t9") keyboard = id;
            else if (id === "auto") autoUpdate = !autoUpdate;
            else if (id === "block") blockUpdates = !blockUpdates;
            else go(id === "back" ? "install-4" : "install-6");
            break;
        case "install-6":
            if (id === "back") go("install-5");
            else { go("install-7"); bridge.send("install", choiceValues()); }
            break;
        case "install-9":
            wizard.close();
            break;
        case "install-x":
            if (id === "close") wizard.close();
            else { go(flow === "update" ? "update-4" : "install-7"); bridge.send(flow === "update" ? "update" : "install", choiceValues()); }
            break;
        case "update-2":
            if (id === "later") wizard.close();
            else if (canInstall) { go("update-4"); bridge.send("update"); }
            break;
        case "remove-2":
            if (id === "data") deleteData = !deleteData;
            else if (id === "cancel") wizard.close();
            else { go("remove-3"); bridge.send("uninstall", { keepState: !deleteData }); }
            break;
        }
    }

    function back() {
        switch (page) {
        case "install-1": case "update-2": case "remove-2": case "install-9": case "install-x":
            wizard.close();
            break;
        case "install-channel": go("install-1"); break;
        case "install-2": go("install-channel"); break;
        case "install-3": go("install-2"); break;
        case "install-4": go("install-3"); break;
        case "install-5": go("install-4"); break;
        case "install-6": go("install-5"); break;
        }
    }

    function handleKey(key) {
        if (Remote.isBack(key)) back();
        else if (Remote.isOk(key)) activate();
        else if (key === Qt.Key_Left) move(-1, 0);
        else if (key === Qt.Key_Right) move(1, 0);
        else if (key === Qt.Key_Up) move(0, -1);
        else if (key === Qt.Key_Down) move(0, 1);
        else return false;
        return true;
    }

    // ---- following the service --------------------------------------------------------------

    readonly property bool progressPage: page === "install-7" || page === "update-4" || page === "remove-3"

    Connections {
        target: bridge
        onInfoChanged: wizard.follow()
    }

    function follow() {
        if (!choicesRead && bridge.info.choices) {
            choicesRead = true;
            keyboard = bridge.choices.keyboard || keyboard;
            if (bridge.info.channel === "stable" || bridge.info.channel === "beta") channel = bridge.info.channel;
        }
        if (page === "") {
            if (!bridge.info.serving) return;      // wait for the service
            start();
            return;
        }
        if (progressPage && bridge.phase === "restarting")
            go(page === "install-7" ? "install-8" : page === "update-4" ? "update-5" : "remove-4");
        else if (progressPage && bridge.answered && bridge.phase === "error")
            go("install-x");
    }

    // When the check finds a release, the focus moves on to "next" once; the state is read
    // a few times a second, and moving it on every read kept the user from going back.
    onCanInstallChanged: {
        if (!canInstall) return;
        if (page === "install-2" && focusId === "back") focusId = "next";
        else if (page === "update-2" && focusId === "later") focusId = "now";
    }

    function start() {
        if (reopened) {
            // surface-manager restarted during an install and the service opened the window again.
            if (bridge.info.command === "install" && bridge.phase === "done") go("install-9");
            else wizard.close();
        } else if (flow === "update") {
            go("update-2");
            bridge.send("check");
        } else if (flow === "remove") {
            go("remove-2");
        } else {
            go("install-1");
        }
    }

    // ---- what the pages show ---------------------------------------------------------------

    function focusIs(id) { return focusId === id; }

    function checkRows() {
        var tv = bridge.tv;
        var result = checkResult;
        var problems = result ? (result.problems || []) : [];
        var lowSpace = problems.join(" ").indexOf("free space") >= 0;
        var internet;
        if (checking) internet = { status: "running", label: tr("check.internet"), value: tr("check.checking") };
        else if (checkFailed) {
            // Only an unreachable server is the connection's fault.
            var kind = bridge.info.errorKind || "failed";
            internet = { status: "error", label: tr("check.internet"),
                         value: tr(kind === "offline" ? "check.failed" :
                                  kind === "missing" ? (channel === "stable" ? "check.no_stable" : "check.no_release") :
                                  "check.error") };
        }
        else if (!result) internet = { status: "pending", label: tr("check.internet") };
        else if (!result.newer && result.installed === result.available)
            internet = { status: "done", label: tr("check.internet"), value: tr("check.installed_already", { version: result.installed }) };
        else if (problems.length > 0 && !lowSpace)
            internet = { status: "error", label: tr("check.internet"), value: tr("check.not_compatible") };
        else internet = { status: "done", label: tr("check.internet"), value: tr("check.release_found", { version: result.available }) };
        return [
            { status: "done", label: tr("check.tv"), value: tv.model || "LG webOS TV" },
            { status: tv.webos ? "done" : "pending", label: tr("check.webos"),
              value: tv.webos ? tr("check.webos_value", { version: tv.webos }) : "" },
            { status: tv.root === false ? "error" : "done", label: tr("check.root"),
              value: tv.root === false ? tr("check.root_missing") : tr("check.root_found") },
            { status: lowSpace ? "error" : (tv.free ? "done" : "pending"), label: tr("check.storage"),
              value: tv.free ? tr(lowSpace ? "check.storage_low" : "check.storage_free", { size: mb(tv.free) + " MB" }) : "" },
            internet
        ];
    }

    readonly property var stageOrder: ["manifest", "download", "verify", "stop", "unpack", "overlays", "switch", "settings", "start"]

    function stageIndex(key) { return stageOrder.indexOf(key); }

    function stageStatus(keys, last) {
        var current = bridge.info.stage || "";
        if (bridge.phase === "done" || stageIndex(current) > stageIndex(last)) {
            for (var i = 0; i < keys.length; ++i) if (bridge.hasStage(keys[i])) return "done";
            return bridge.phase === "done" ? "done" : "pending";
        }
        if (keys.indexOf(current) >= 0) return bridge.phase === "error" ? "error" : "running";
        return "pending";
    }

    function progressRows(update) {
        var size = checkResult && checkResult.size ? tr("progress.megabytes", { size: mb(checkResult.size) }) : "";
        var settingsDone = bridge.hasStage("settings");
        return [
            { status: stageStatus(["download"], "download"), label: tr(update ? "update.loaded" : "progress.download"), value: size },
            { status: stageStatus(["verify"], "verify"), label: tr("progress.verify"),
              value: bridge.hasStage("verify") ? tr("progress.signature_ok") : "" },
            { status: stageStatus(["stop", "unpack", "overlays", "switch"], "switch"), label: tr("progress.files") },
            { status: settingsDone ? "done" : "pending", label: tr("progress.settings") },
            { status: bridge.phase === "restarting" || bridge.info.stage === "start" ? "running" :
                      (bridge.phase === "done" ? "done" : "pending"), label: tr("progress.restart") }
        ];
    }

    function taskLabel() {
        var stage = bridge.info.stage || "";
        if (stage === "download" || stage === "manifest") return tr("progress.download");
        if (stage === "verify") return tr("progress.verify");
        if (stage === "start") return tr("progress.restart");
        return tr("progress.files");
    }

    readonly property var live: {
        var f = focusId;
        switch (page) {
        case "install-1": case "install-3": case "install-9":
            return { focus: f };
        case "install-channel":
            return { focus: f, channel: channel };
        case "install-2":
            return {
                label: tr("header.install"), step: 3, title: tr("check.title"), lead: tr("check.lead"),
                rows: checkRows(),
                left: [{ label: tr("button.back"), focused: f === "back" }],
                right: checkFailed ? [{ label: tr("button.check_again"), icon: "refresh-22", focused: f === "retry" }]
                                   : [{ label: tr("button.next"), focused: f === "next", disabled: !canInstall }]
            };
        case "install-4":
            return { focus: f, values: privacy };
        case "install-5":
            return { focus: f, keyboard: keyboard, autoUpdate: autoUpdate, blockUpdates: blockUpdates };
        case "install-6":
            return { focus: f, rows: [
                { label: tr("summary.version"), value: checkResult ? tr("summary.version_value",
                    { version: checkResult.available, size: mb(checkResult.size) + " MB" }) : "" },
                { label: tr("summary.channel"), value: tr(channel === "beta" ? "channel.beta_title" : "channel.stable_title") },
                { label: tr("summary.duration"), value: tr("summary.duration_value") },
                { label: tr("summary.privacy"), value: tr("summary.privacy_later") },
                { label: tr("summary.keyboard"), value: tr(keyboard === "t9" ? "keyboard.t9_title" : "keyboard.qwertz_title") },
                { label: tr("summary.auto_update"), value: tr(autoUpdate ? "summary.on" : "summary.off") },
                { label: tr("summary.block_updates"), value: tr(blockUpdates ? "summary.blocked" : "summary.allowed") }
            ] };
        case "install-7": case "update-4":
            var update = page === "update-4";
            return {
                label: tr(update ? "header.update" : "header.install"),
                title: update ? tr("update.install_title", { version: checkResult ? checkResult.available : "" })
                              : tr("progress.install_title"),
                lead: tr(update ? "update.install_lead" : "progress.install_lead"),
                task: taskLabel(), value: bridge.percent / 100,
                remaining: bridge.percent >= 80 ? tr("progress.almost") : "",
                rows: progressRows(update)
            };
        case "remove-3":
            return {
                label: tr("header.remove"), title: tr("remove.running_title"), lead: tr("remove.running_lead"),
                task: tr("remove.data_title"), value: 0.5, remaining: "",
                rows: [
                    { status: "running", label: tr("remove.originals") },
                    { status: "pending", label: tr(deleteData ? "remove.data_title" : "progress.files") },
                    { status: "pending", label: tr("progress.restart") }
                ]
            };
        case "install-x":
            var rows = progressRows(flow === "update");
            for (var i = 0; i < rows.length; ++i) {
                if (rows[i].status === "running") rows[i] = { status: "error", label: rows[i].label, value: "" };
            }
            return {
                label: tr(flow === "update" ? "header.update" : "header.install"), step: 0,
                title: tr("error.title"), lead: bridge.error || tr("error.lead"), rows: rows,
                left: [{ label: tr("button.close"), focused: f === "close" }],
                right: [{ label: tr("button.retry"), icon: "refresh-22", focused: f === "retry" }]
            };
        case "update-2":
            return {
                focus: f, version: checkResult ? checkResult.available : "", canUpdate: canInstall,
                news: [{ icon: "setup-sparkle-30", title: tr("update.release_notes_title"),
                         detail: tr("update.release_notes_detail") }],
                facts: [
                    { label: tr("update.size"), value: checkResult && checkResult.size ? mb(checkResult.size) + " MB" : "" },
                    { label: tr("update.restarts"), value: "1" },
                    { label: tr("update.settings"), value: tr("update.settings_kept") }
                ]
            };
        case "remove-2":
            return { focus: f, deleteData: deleteData };
        default:
            return null;
        }
    }
}
