import QtQuick 2.12
import QtMultimedia 5.0

// A video the user added, filling the screen with its own aspect. Own file, so that only
// a video entry loads QtMultimedia. sound plays the sound track at the TV's volume.
Video {
    id: video

    property bool sound: true

    fillMode: VideoOutput.PreserveAspectFit
    autoPlay: false
    muted: !video.sound
}
