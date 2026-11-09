pragma Singleton
import QtQuick 2.12
import WebOS.Global 1.0

// The keys of the remote, read the same way in every window and module.
QtObject {
    function isBack(key) {
        return key === Qt.Key_Back || key === Qt.Key_Escape || key === Qt.Key_Backspace ||
               key === WebOS.Key_webOS_Back;
    }

    function isOk(key) {
        return key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Select;
    }

    // The red colour key. LG's remotes have no play key; red is free on 10.3.2, only its
    // long press becomes "record". Previews start with it.
    readonly property int redKey: WebOS.Key_webOS_Red

    function isRed(key) {
        return key === redKey;
    }

    function isArrow(key) {
        return key === Qt.Key_Up || key === Qt.Key_Down || key === Qt.Key_Left || key === Qt.Key_Right;
    }

    // 0..9 for the number keys, -1 for anything else.
    function digitOf(key) {
        return key >= Qt.Key_0 && key <= Qt.Key_9 ? key - Qt.Key_0 : -1;
    }
}
