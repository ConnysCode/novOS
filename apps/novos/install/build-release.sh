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

# Files that keep values: debug switches with the blur, and the launcher's order.
state() {
    sed -e "s#/tmp/novos-debug.ini#${STATE}debug.ini#g" \
        -e "s#/tmp/novos-launcher.ini#${STATE}launcher.ini#g"
}

# The three windows LG loads from /usr/lib/qml, and our volume view in the compositor.
entry() {
    sed -e "s#import \"module#import \"file://$PANEL/module#" \
        -e "s#Qt.resolvedUrl(\"novos-inter-#\"file://$PANEL/novos-inter-#" \
        -e "s#\.ttf\")#.ttf\"#" \
        -e "s#Qt.resolvedUrl(\"module/icons/#(\"file://$PANEL/module/icons/#" \
        -e "s#Qt.resolvedUrl(\"module/vt-feed.py\").toString().replace(\"file://\", \"\")#\"$PANEL/module/vt-feed.py\"#" \
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
cp -R "$HERE/launcher/backgrounds" "$OUT/launcher/"
cp "$LIB"/fonts/novos-inter-*.ttf "$OUT/"
state < "$HERE/banner-relay.py" > "$OUT/banner-relay.py"
cp "$HERE/toast-filter.inc" "$HERE/settings-redirect.inc" "$HERE/launcher-home-key.inc" "$HERE/fullscreen-home.inc" "$HERE/splash-hide.inc" "$HERE/launcher-home.inc" "$HERE/launcher-stays.inc" \
    "$INSTALL/lg-targets.txt" "$OUT/"
for file in "$INSTALL"/tv/*; do [ ! -f "$file" ] || cp "$file" "$OUT/bin/"; done
# The PmLogCtl and luna-send stand-ins of the early start, each alone in its folder for PATH.
cp -R "$INSTALL/tv/early" "$INSTALL/tv/kick" "$OUT/bin/"
chmod 755 "$OUT"/bin/early/* "$OUT"/bin/kick/*
# The uninstall script carries the list itself, so it works without the release.
uninstall_script > "$OUT/bin/novos-uninstall.sh"
chmod 755 "$OUT"/bin/*

{
    echo "version=$(git -C "$HERE" describe --always --dirty 2>/dev/null || echo unknown)"
    echo "built=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "panel=$PANEL"
    echo "state=$STATE"
} > "$OUT/VERSION"
