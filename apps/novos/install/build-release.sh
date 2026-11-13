#!/bin/sh
# Builds one release of the panel, the source picker and the launcher for bind mounts.
#
#   install/build-release.sh <out-dir> <panel-dir> <state-prefix>
#   install/build-release.sh --uninstall-script     prints only novos-uninstall.sh
#
# <panel-dir> is where the files lie on the TV. Behind a bind mount relative URLs
# point into LG's system folder, so every reference becomes an absolute file:// path.
# <state-prefix> replaces "/tmp/novos-" in the two files that keep values:
#   "/tmp/novos-"            test mount, values live until the TV restarts
#   "/var/lib/novos/state/"  install, values survive a restart
# LG's own files are not part of a release: bin/make-overlays.sh derives the
# overlays of LG files from the originals on the TV.
set -eu

OUT=$1
PANEL=${2:-}
STATE=${3:-}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALL=$HERE/install
LIB=$(CDPATH= cd -- "$HERE/../../lib/ui" && pwd)
BACKGROUNDS=$(CDPATH= cd -- "$HERE/../../lib/backgrounds" && pwd)

# novos-uninstall.sh with the list of LG files inside. Also used by novos-on-tv.sh.
uninstall_script() {
    sed -e "/^# @LG_TARGETS@\$/r $INSTALL/lg-targets.txt" "$INSTALL/tv/novos-uninstall.sh"
}
[ "$OUT" != --uninstall-script ] || { uninstall_script; exit 0; }

[ -f "$HERE/module/output/libnovos-video-backdrop.so" ] || {
    echo "module/output/libnovos-video-backdrop.so is missing, build the plugin first" >&2
    exit 1
}
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }

# Files that keep values: debug switches with the blur, the launcher's order, and the
# power-off videos and pictures the user added (bin/novos-upload.py writes them there).
state() {
    sed -e "s#/tmp/novos-debug.ini#${STATE}debug.ini#g" \
        -e "s#/tmp/novos-launcher.ini#${STATE}launcher.ini#g" \
        -e "s#/tmp/novos-media/#${STATE}media/#g"
}

# The three windows LG loads from /usr/lib/qml, and our volume view in the compositor.
entry() {
    sed -e "s#import \"module#import \"file://$PANEL/module#" \
        -e "s#Qt.resolvedUrl(\"novos-inter-#\"file://$PANEL/novos-inter-#" \
        -e "s#\.ttf\")#.ttf\"#" \
        -e "s#Qt.resolvedUrl(\"module/icons/#(\"file://$PANEL/module/icons/#" \
        -e "s#Qt.resolvedUrl(\"module/vt-feed.py\").toString().replace(\"file://\", \"\")#\"$PANEL/module/vt-feed.py\"#" \
        -e "s#Qt.resolvedUrl(\"module/#(\"file://$PANEL/module/#" \
        -e "s#Qt.resolvedUrl(\"launcher/#(\"file://$PANEL/launcher/#" \
        "$HERE/$1" | state > "$OUT/$2"
    # A relative URL left in an entry file would point into LG's folder.
    if grep -n 'Qt.resolvedUrl("' "$OUT/$2" >&2; then
        echo "$1: relative URL left, extend entry() in build-release.sh" >&2
        exit 1
    fi
}

entry quick-settings-glass.qml QuickSettings.qml
entry source-picker.qml InputPicker.qml
entry launcher.qml StoreStreamer.qml
entry volume-view.qml StarfishVolumeView.qml

mkdir -p "$OUT/launcher" "$OUT/bin"
# lib/ui and our module/ become one folder, see lib/ui/qmldir.
python3 -I "$LIB/stage.py" "$HERE/module" "$OUT/module"
for file in "$OUT"/module/*.qml "$OUT"/module/*.js; do
    state < "$file" > "$file.new"
    mv "$file.new" "$file"
done
state < "$HERE/module/vt-feed.py" > "$OUT/module/vt-feed.py"
cp "$HERE/module/output/libnovos-video-backdrop.so" "$OUT/module/"
# What is new in every version and its pictures, for the update page and "Neu in novOS".
python3 -I "$INSTALL/check-notes.py" || { echo "release-notes.json names what the release lacks" >&2; exit 1; }
cp "$HERE/release-notes.json" "$OUT/module/"
mkdir -p "$OUT/module/release-art"
cp "$HERE"/release-art/*.png "$OUT/module/release-art/"
for folder in "$HERE"/release-art/*/; do
    case $folder in */src/) continue ;; esac
    mkdir -p "$OUT/module/release-art/$(basename "$folder")"
    cp "$folder"*.png "$OUT/module/release-art/$(basename "$folder")/"
done
# The pictures of launcher and hub, shared with the setup in lib/backgrounds.
mkdir -p "$OUT/launcher/backgrounds"
cp "$BACKGROUNDS"/*.jpg "$BACKGROUNDS/index.json" "$BACKGROUNDS/CREDITS.md" "$OUT/launcher/backgrounds/"
cp "$LIB"/fonts/novos-inter-*.ttf "$OUT/"
state < "$HERE/banner-relay.py" > "$OUT/banner-relay.py"
cp "$HERE/toast-filter.inc" "$HERE/settings-redirect.inc" "$HERE/launcher-home-key.inc" "$HERE/fullscreen-home.inc" "$HERE/splash-hide.inc" "$HERE/launcher-home.inc" "$HERE/launcher-stays.inc" \
    "$INSTALL/lg-targets.txt" "$OUT/"
# The overlay of LG's MasterBrand.qml loads our shutdown screen from this release.
sed -e "s#@PANEL@#$PANEL#g" "$HERE/shutdown-screen.inc" | state > "$OUT/shutdown-screen.inc"
for file in "$INSTALL"/tv/*; do [ ! -f "$file" ] || cp "$file" "$OUT/bin/"; done
# What novos-updater.py checks the setup's updater with, and the keys it trusts.
mkdir -p "$OUT/bin/release"
cp "$HERE/../../lib/release/release.py" "$HERE/../../lib/release/ed25519.py" \
    "$HERE/../../lib/release/trusted-keys.json" "$OUT/bin/release/"
# The PmLogCtl and luna-send stand-ins of the early start, each alone in its folder for PATH.
cp -R "$INSTALL/tv/early" "$INSTALL/tv/kick" "$OUT/bin/"
chmod 755 "$OUT"/bin/early/* "$OUT"/bin/kick/*
# The uninstall script carries the list itself, so it works without the release.
uninstall_script > "$OUT/bin/novos-uninstall.sh"
chmod 755 "$OUT"/bin/*

{
    # A CI release names its version; a local build takes the commit.
    echo "version=${NOVOS_VERSION:-$(git -C "$HERE" describe --always --dirty --match 'novos-v*' 2>/dev/null || echo unknown)}"
    echo "built=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "panel=$PANEL"
    echo "state=$STATE"
} > "$OUT/VERSION"
