import QtQuick 2.12
import "."

// Profile › Profil bearbeiten (K3-Profil-Einst-Bearbeiten): name and colour of the active
// profile. The ten colours are LG's (GlassStyle.profileColors); the avatar on top and the
// previews show the colour in the focus, OK keeps it at once. The name opens the panel's
// name entry. Both change only the TV's copy (updateAccountData), never the LG account.
Item {
    id: page

    property real unit: 1
    property var owner: null            // the settings modal: runAction(), hostAction()
    property var host: null             // SettingsData: profiles (ProfileStore)

    readonly property var profile: host && host.profiles ? host.profiles.active : null
    readonly property var colours: GlassStyle.profileColors
    property string item: "name"        // name or colour
    property int colourIndex: Math.max(0, colours.indexOf(profile ? profile.tint : ""))
    readonly property string shownTint: item === "colour" ? colours[colourIndex] :
                                        (profile ? profile.tint : colours[0])
    readonly property string shownInitial: profile ? profile.initial : ""
    readonly property string shownName: profile ? profile.nick : ""

    function t(key, params) { return I18n.t("profile", key, params); }

    onProfileChanged: if (item !== "colour") colourIndex = Math.max(0, colours.indexOf(profile ? profile.tint : ""))

    function handleKey(key, autoRepeat) {
        if (!profile) return false;
        if (key === Qt.Key_Up && item === "colour") item = "name";
        else if (key === Qt.Key_Down && item === "name") item = "colour";
        else if (key === Qt.Key_Left && item === "colour" && colourIndex > 0) colourIndex--;
        else if (key === Qt.Key_Right && item === "colour" && colourIndex < colours.length - 1) colourIndex++;
        else if (Remote.isOk(key) && !autoRepeat) activate();
        else if (key === Qt.Key_Left) return false;
        return true;
    }

    function activate() {
        if (!owner || !profile) return;
        if (item === "name") {
            owner.hostAction("profileName", { userNo: profile.userNo, current: profile.nick });
        } else if (colours[colourIndex] !== profile.tint) {
            owner.runAction("profileColour", { userNo: profile.userNo, tint: colours[colourIndex] });
        }
    }

    // The head: the profile as it will look.
    ProfileAvatar {
        x: 20 * page.unit
        y: 0
        unit: page.unit
        size: 96
        initial: page.shownInitial
        tint: page.shownTint
    }

    Text {
        x: 140 * page.unit
        y: 22 * page.unit
        height: 52 * page.unit
        verticalAlignment: Text.AlignVCenter
        text: page.shownName
        color: GlassStyle.textPrimary
        font.family: GlassStyle.titleFont
        font.pixelSize: 36 * page.unit
        font.hintingPreference: Font.PreferNoHinting
    }

    // Name: a row with the panel's name entry behind it.
    Item {
        id: nameRow
        y: 128 * page.unit
        width: 700 * page.unit
        height: 68 * page.unit
        readonly property bool focused: page.item === "name"

        Rectangle {
            anchors.fill: parent
            radius: 26 * page.unit
            color: GlassStyle.focusFill
            opacity: nameRow.focused ? 1 : 0
            scale: nameRow.focused ? GlassStyle.focusScale : 1
            Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }

            FocusRing {
                anchors.fill: parent
                unit: page.unit
                radius: parent.radius
            }
        }

        GlassRow {
            anchors.fill: parent
            unit: page.unit
            titleFont: GlassStyle.rowFont
            valueFont: GlassStyle.valueFont
            focused: nameRow.focused
            title: page.t("label.name")
            value: page.shownName
            mark: "chevron"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: { page.item = "name"; page.activate(); }
        }
    }

    SectionTitle {
        x: 20 * page.unit
        y: 232 * page.unit
        unit: page.unit
        text: page.t("label.colour")
    }

    // The ten colours; the one in the focus grows and carries a white ring.
    Row {
        x: 20 * page.unit
        y: 270 * page.unit
        spacing: 18 * page.unit

        Repeater {
            model: page.colours

            Item {
                readonly property bool focused: page.item === "colour" && index === page.colourIndex
                readonly property bool chosen: page.profile !== null && modelData === page.profile.tint
                width: 56 * page.unit
                height: width

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 10 * page.unit
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 3 * page.unit
                    border.color: GlassStyle.focusFill
                    // With "Kontrast für Fokus" this ring becomes FocusRing.
                    opacity: parent.focused && !GlassStyle.focusEmphasis ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: GlassStyle.colorDuration } }
                }

                FocusRing {
                    anchors.fill: parent
                    unit: page.unit
                    radius: width / 2
                    shown: parent.focused
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: modelData
                    scale: parent.focused ? GlassStyle.focusScale : 1
                    Behavior on scale { NumberAnimation { duration: GlassStyle.focusDuration } }
                }

                Image {
                    anchors.centerIn: parent
                    visible: parent.chosen
                    source: Qt.resolvedUrl(GlassStyle.profileLightColors.indexOf(modelData) >= 0 ?
                                           "icons/check-24-dark.png" : "icons/check-24.png")
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: { page.item = "colour"; page.colourIndex = index; page.activate(); }
                }
            }
        }
    }

    SectionTitle {
        x: 20 * page.unit
        y: 376 * page.unit
        unit: page.unit
        text: page.t("label.preview")
    }

    // Where the profile shows: the home screen's chip, the panel's row, the switch screen.
    Row {
        x: 20 * page.unit
        y: 414 * page.unit
        spacing: 20 * page.unit

        Repeater {
            model: ["home", "panel", "switch"]

            Column {
                spacing: 10 * page.unit

                Rectangle {
                    width: 320 * page.unit
                    height: 150 * page.unit
                    radius: 24 * page.unit
                    color: modelData === "switch" ? GlassStyle.scrimColor : GlassStyle.cardFill
                    clip: true

                    // Home: the chip beside the clock.
                    Row {
                        anchors.centerIn: parent
                        spacing: 14 * page.unit
                        visible: modelData === "home"

                        Rectangle {
                            width: (10 + 36 + 10 + homeName.implicitWidth / page.unit + 18) * page.unit
                            height: 52 * page.unit
                            radius: height / 2
                            color: GlassStyle.focusFill
                            anchors.verticalCenter: parent.verticalCenter

                            FocusRing {
                                anchors.fill: parent
                                unit: page.unit
                                radius: parent.radius
                            }

                            ProfileAvatar {
                                x: 8 * page.unit
                                anchors.verticalCenter: parent.verticalCenter
                                unit: page.unit
                                size: 36
                                initial: page.shownInitial
                                tint: page.shownTint
                            }

                            Text {
                                id: homeName
                                x: 54 * page.unit
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: page.shownName
                                color: GlassStyle.focusText
                                font.family: GlassStyle.rowFont
                                font.pixelSize: 17 * page.unit
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatTime(new Date(), "hh:mm")
                            color: GlassStyle.textPrimary
                            font.family: GlassStyle.titleFont
                            font.pixelSize: 26 * page.unit
                        }
                    }

                    // Panel: the row "Profile" with the avatar and the name.
                    GlassRow {
                        x: 16 * page.unit
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32 * page.unit
                        height: 60 * page.unit
                        visible: modelData === "panel"
                        unit: page.unit
                        titleFont: GlassStyle.rowFont
                        valueFont: GlassStyle.valueFont
                        title: page.t("row.profiles")
                        value: page.shownName
                        avatar: { "initial": page.shownInitial, "tint": page.shownTint }
                    }

                    // Switching: the avatar on black in the profile's light.
                    BootGlow {
                        anchors.fill: parent
                        visible: modelData === "switch"
                        tint: page.shownTint
                        spread: 2400
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8 * page.unit
                        visible: modelData === "switch"

                        ProfileAvatar {
                            anchors.horizontalCenter: parent.horizontalCenter
                            unit: page.unit
                            size: 64
                            initial: page.shownInitial
                            tint: page.shownTint
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.shownName
                            color: GlassStyle.textPrimary
                            font.family: GlassStyle.titleFont
                            font.pixelSize: 20 * page.unit
                        }
                    }
                }

                Text {
                    text: page.t("preview." + modelData)
                    color: GlassStyle.textSecondary
                    font.family: GlassStyle.valueFont
                    font.pixelSize: GlassStyle.valueSize * page.unit
                }
            }
        }
    }
}
