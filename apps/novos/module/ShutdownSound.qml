import QtQuick 2.12
import QtMultimedia 5.0

// The sound of a video the user added: the part that plays, as WAV. SoundEffect plays
// through the TV's audio output; Audio and Video have no media service in surface-manager.
// Own file, so that only a video with sound loads QtMultimedia.
SoundEffect {
    volume: 1
}
