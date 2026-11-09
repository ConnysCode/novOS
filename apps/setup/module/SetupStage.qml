import QtQuick 2.12
import "Slides.js" as Slides

// One screen of the setup over its picture. Picture and scrim form the backdrop that the
// glass of the screen samples, as backdrop-filter does on the boards. The glass hides
// what it samples, so the backdrop is drawn a second time as it is, as in the hub.
// The setup always shows the same launcher picture, with its credit from index.json.
Item {
    id: stage

    property real unit: 1
    property string slideId: ""
    // Values and focus of the running setup, handed to the screen; null shows the board.
    property var live: null
    readonly property var slide: Slides.list[Math.max(0, Slides.indexOf(slideId))]

    property string pictureFile: "lake-tahoe-at-morning-7-2023.jpg"
    property var picture: null
    readonly property bool showsPicture: slide.scene === "picture" && picture !== null

    function loadPictures() {
        try {
            var request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../backgrounds/index.json"), false);
            request.send();
            var pictures = JSON.parse(request.responseText);
            for (var i = 0; i < pictures.length; ++i) {
                if (pictures[i].file === pictureFile) picture = pictures[i];
            }
        } catch (error) {
            picture = null;
        }
    }

    Item {
        id: backdrop
        anchors.fill: parent
        // The glass of every page samples this one blurred picture of the whole screen.
        property Item sharedGlass: screenGlass

        SetupScene {
            anchors.fill: parent
            unit: stage.unit
            kind: stage.slide.scene
            pictureSource: stage.picture ? Qt.resolvedUrl("../backgrounds/" + stage.picture.file) : ""
        }

        Rectangle {
            anchors.fill: parent
            visible: stage.slide.scrim > 0
            color: Qt.rgba(4 / 255, 6 / 255, 8 / 255, stage.slide.scrim)
        }
    }

    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: backdrop
        live: true
    }

    // Blurred once for the whole screen and again only when the picture changes, so that a
    // flying page costs no new textures; edges clamp at the screen as before.
    ImageGlass {
        id: screenGlass
        sourceItem: backdrop
        unit: stage.unit
        margin: 0
        area: Qt.rect(0, 0, stage.width, stage.height)
        visible: false
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 56 * stage.unit
        y: parent.height - height - 28 * stage.unit
        visible: stage.showsPicture
        text: stage.picture ? I18n.t("setup", "label.image_credit", { credit: stage.picture.credit }) : ""
        color: "#9effffff"
        font.family: GlassStyle.rowFont
        font.pixelSize: 16 * stage.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    // The pages. A new page flies in from the right while the current one flies out to the
    // left at the same speed (back: the other way); the windows themselves keep their size.
    // Pages over another scene (the black restart) change at once.
    Item {
        id: pages
        anchors.fill: parent
    }

    property Item current: null
    property Item leaving: null
    property int currentIndex: -1

    ParallelAnimation {
        id: slideMotion
        NumberAnimation {
            id: outMotion
            property: "x"
            duration: GlassStyle.slideDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: GlassStyle.curve
        }
        NumberAnimation {
            id: inMotion
            property: "x"
            to: 0
            duration: GlassStyle.slideDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: GlassStyle.curve
        }
        onStopped: {
            stage.dropLeaving();
            PerfProbe.endPhase();
            PerfProbe.flush();
        }
    }

    // Frame statistics of every slide; only in a measuring copy (setup-on-tv.sh, SETUP_PERF=1).
    PerfMeter {}

    Timer {
        id: launchTimer
        interval: 60
        property string phase: ""
        onTriggered: {
            PerfProbe.beginPhase(phase);
            slideMotion.start();
        }
    }

    function dropLeaving() {
        if (leaving) leaving.destroy();
        leaving = null;
    }

    // Reads the slide itself: in onSlideIdChanged the binding of slide may still be old.
    function load() {
        // The wizard starts with no page; its first page appears without a slide.
        if (Slides.indexOf(slideId) < 0 && currentIndex < 0 && slideId === "") return;
        var index = Math.max(0, Slides.indexOf(slideId));
        var next = Slides.list[index];
        if (launchTimer.running) {
            launchTimer.stop();
            slideMotion.start();
        }
        if (slideMotion.running) slideMotion.complete();
        dropLeaving();
        var building = PerfProbe.now();
        var component = Qt.createComponent(Qt.resolvedUrl(next.screen + ".qml"));
        var item = component.createObject(pages, { unit: stage.unit, backdrop: backdrop, variant: next.variant,
                                                   live: stage.live, width: stage.width, height: stage.height });
        PerfProbe.cost("page.build", building, next.id);
        if (item === null) return;
        var before = current;
        var slides = before !== null && currentIndex >= 0 &&
                     Slides.list[currentIndex].scene === "picture" && next.scene === "picture";
        current = item;
        if (!slides) {
            if (before) before.destroy();
        } else {
            var direction = index >= currentIndex ? 1 : -1;
            leaving = before;
            item.x = direction * stage.width;
            outMotion.target = before;
            outMotion.from = 0;
            outMotion.to = -direction * stage.width;
            inMotion.target = item;
            inMotion.from = direction * stage.width;
            launchTimer.phase = "slide " + Slides.list[currentIndex].id + ">" + next.id;
            // The first frame of a new page (nodes, glyphs, its layout) is drawn while it
            // still waits beside the screen; the motion starts after it, without a gap.
            launchTimer.restart();
        }
        currentIndex = index;
    }

    onSlideIdChanged: load()
    onUnitChanged: if (current) current.unit = unit
    onLiveChanged: if (current) current.live = live
    Component.onCompleted: {
        loadPictures();
        load();
    }
}
