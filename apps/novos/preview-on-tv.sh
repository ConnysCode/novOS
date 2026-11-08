#!/bin/sh
# One-time preview of the live-video panel from /tmp, without a bind mount.
# A timer on the TV closes the preview even if this script dies. The panel starts
# and ends the video process itself.
#
# Usage: preview-on-tv.sh <build-name> <capture.png> [focus-index] [seconds-open]
#        PREVIEW_ENTRY=<file> starts another QML file from this upload.
#        PREVIEW_SED and PREVIEW_MODULE_SED change only the uploaded copy.
#        PREVIEW_APP=<app id> runs it as another system window.
#        PREVIEW_UPLOAD_ONLY=1 uploads and stops before the launch.
set -eu

BUILD_NAME=$1
CAPTURE_TARGET=$2
FOCUS_INDEX=${3:-0}
SECONDS_OPEN=${4:-20}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB=$(CDPATH= cd -- "$HERE/../../lib/ui" && pwd)
REMOTE_DIR=/tmp/lg-quicksettings-final/$BUILD_NAME
ENTRY=${PREVIEW_ENTRY:-QuickSettings.glass.qml}
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

sed -e "s/property int initialFocus: 0/property int initialFocus: $FOCUS_INDEX/" \
    -e "${PREVIEW_SED:-s/^$//}" \
    "$HERE/quick-settings-glass.qml" > "$STAGE/QuickSettings.glass.qml"
sed -e "${PREVIEW_SED:-s/^$//}" "$HERE/source-picker.qml" > "$STAGE/source-picker.qml"
sed -e "${PREVIEW_SED:-s/^$//}" "$HERE/launcher.qml" > "$STAGE/launcher.qml"
mkdir -p "$STAGE/launcher/backgrounds"
cp "$HERE"/../../lib/backgrounds/*.jpg "$HERE/../../lib/backgrounds/index.json" "$STAGE/launcher/backgrounds/"
cp "$LIB"/fonts/novos-inter-*.ttf "$STAGE/"
# lib/ui and our module/ become one folder, see lib/ui/qmldir.
python3 -I "$LIB/stage.py" "$HERE/module" "$STAGE/module"
cp "$HERE/module/output/libnovos-video-backdrop.so" "$HERE/module/vt-feed.py" "$STAGE/module/"
[ -z "${PREVIEW_MODULE_SED:-}" ] || sed -i '' -e "$PREVIEW_MODULE_SED" "$STAGE"/module/*.qml
[ -z "${PREVIEW_EXTRA:-}" ] || cp $PREVIEW_EXTRA "$STAGE/"

# /tmp on the TV is RAM (about 730 MB) and each upload holds ~20 MB of pictures: drop
# previews older than ten minutes so that a series of tests cannot fill it.
ssh lg-tv "find /tmp/lg-quicksettings-final -mindepth 1 -maxdepth 1 -type d -mmin +10 -exec rm -rf {} + 2>/dev/null; mkdir -p $REMOTE_DIR"
scp -qr "$STAGE"/* "lg-tv:$REMOTE_DIR/"
# PREVIEW_UPLOAD_ONLY=1: the caller launches by itself (perf-on-tv.sh).
[ -z "${PREVIEW_UPLOAD_ONLY:-}" ] || exit 0

APP=${PREVIEW_APP:-com.webos.app.quicksettings}
CLOSE_REQUEST='{"appId":"'$APP'"}'
LAUNCH_REQUEST='{"appId":"'$APP'","main":"file://'$REMOTE_DIR/$ENTRY'"}'
CAPTURE_REQUEST='{"path":"/tmp/quicksettings-capture.png","method":"GRAPHIC","format":"PNG","width":1920,"height":1080}'

ssh lg-tv "pkill -f '[t]vos-preview-guard' 2>/dev/null; true"
ssh lg-tv "nohup sh -c 'sleep $SECONDS_OPEN; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId \"{\\\"appId\\\":\\\"$APP\\\"}\"; : novos-preview-guard' >/dev/null 2>&1 &"
# GRAPHIC holds only the interface. DISPLAY comes out black while the feed runs.
ssh -tt lg-tv "luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId '$CLOSE_REQUEST'; sleep 1; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/launch '$LAUNCH_REQUEST'; sleep ${PREVIEW_WAIT:-3}; rm -f /tmp/quicksettings-capture.png; luna-send -n 1 -w 5000 luna://com.webos.service.capture/executeOneShot '$CAPTURE_REQUEST'" >/dev/null 2>&1
scp -q lg-tv:/tmp/quicksettings-capture.png "$CAPTURE_TARGET"
echo "$CAPTURE_TARGET"
