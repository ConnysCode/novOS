#!/bin/sh
# Shows the setup's screens on the TV from /tmp, as a system window, without touching
# anything installed. A timer on the TV closes the window even if this script dies.
#
#   preview-on-tv.sh <build-name> [slide ...]
#
# Opens the window on the first slide given (or the first of all), then switches to each
# slide in turn through the control file and saves a capture of it in ./captures/
# (CAPTURES=<dir> elsewhere). "all" stands for every slide. The window stays open for
# SECONDS_OPEN (default 30) after the last capture. Slide ids are in module/Slides.js.
#
# Captures use GRAPHIC: only the interface, no video. Every build needs a new name,
# because surface-manager caches components by URL.
set -eu
TV=${NOVOS_TV:?"set NOVOS_TV to the SSH target of the TV as root, e.g. root@<tv-ip>"}

BUILD_NAME=$1
shift
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB=$(CDPATH= cd -- "$HERE/../../lib/ui" && pwd)
REMOTE_DIR=/tmp/novos-setup-preview/$BUILD_NAME
APP=com.webos.app.quicksettings
CONTROL=/tmp/novos-setup-slide
OUT=${CAPTURES:-$HERE/captures}
SLIDES="$*"
if [ -z "$SLIDES" ] || [ "$SLIDES" = all ]; then
    SLIDES=$(sed -n 's/.*{ id: "\([^"]*\)".*/\1/p' "$HERE/module/Slides.js" | tr '\n' ' ')
fi
FIRST=${SLIDES%% *}
COUNT=$(echo $SLIDES | wc -w)
SECONDS_TOTAL=$((COUNT * 7 + ${SECONDS_OPEN:-30}))

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
sed -e "s/property string startSlide: \"\"/property string startSlide: \"$FIRST\"/" \
    "$HERE/setup.qml" > "$STAGE/setup.qml"
python3 -I "$LIB/stage.py" "$HERE/module" "$STAGE/module"
cp "$LIB"/fonts/novos-inter-*.ttf "$STAGE/"
# The launcher's pictures, see lib/backgrounds.
mkdir "$STAGE/backgrounds"
cp "$HERE"/../../lib/backgrounds/*.jpg "$HERE/../../lib/backgrounds/index.json" "$STAGE/backgrounds/"

ssh "$TV" "find /tmp/novos-setup-preview -mindepth 1 -maxdepth 1 -type d -mmin +10 -exec rm -rf {} + 2>/dev/null; mkdir -p $REMOTE_DIR; echo $FIRST > $CONTROL"
scp -qr "$STAGE"/* "$TV:$REMOTE_DIR/"

CLOSE='{"appId":"'$APP'"}'
LAUNCH='{"appId":"'$APP'","main":"file://'$REMOTE_DIR'/setup.qml"}'
ssh "$TV" "pkill -f '[n]ovos-setup-guard' 2>/dev/null; true"
ssh "$TV" "nohup sh -c 'sleep $SECONDS_TOTAL; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId \"{\\\"appId\\\":\\\"$APP\\\"}\"; rm -f $CONTROL; : novos-setup-guard' >/dev/null 2>&1 &"
ssh -tt "$TV" "luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId '$CLOSE'; sleep 1; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/launch '$LAUNCH'" >/dev/null 2>&1
sleep ${PREVIEW_WAIT:-4}

mkdir -p "$OUT"
REQUEST='{"path":"/tmp/novos-setup-capture.png","method":"GRAPHIC","format":"PNG","width":1920,"height":1080}'
for slide in $SLIDES; do
    ssh -tt "$TV" "echo $slide > $CONTROL; sleep ${SLIDE_WAIT:-1.5}; rm -f /tmp/novos-setup-capture.png; luna-send -n 1 -w 5000 luna://com.webos.service.capture/executeOneShot '$REQUEST'" >/dev/null 2>&1
    scp -q "$TV:/tmp/novos-setup-capture.png" "$OUT/$BUILD_NAME-$slide.png"
    echo "$OUT/$BUILD_NAME-$slide.png"
done
