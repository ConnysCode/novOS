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

    Loader {
        id: screen
        anchors.fill: parent
    }

    // Reads the slide itself: in onSlideIdChanged the binding of slide may still be old.
    function load() {
        var next = Slides.list[Math.max(0, Slides.indexOf(slideId))];
        screen.setSource(Qt.resolvedUrl(next.screen + ".qml"),
                         { unit: stage.unit, backdrop: backdrop, variant: next.variant });
    }

    onSlideIdChanged: load()
    onUnitChanged: if (screen.item) screen.item.unit = unit
    Component.onCompleted: {
        loadPictures();
        load();
    }
}
