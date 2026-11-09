#!/bin/sh
# Runs the setup on the TV from /tmp, as it will run from the setup app: novos-setupd serve
# as root and the setup's window. Nothing is installed by this script itself; the setup
# does what it is told on the TV, an install included.
#
#   setup-on-tv.sh <build-name> [install|update|remove] [stable|beta]
#                                                         start the setup with this flow; the
#                                                         channel is checked, installed from and
#                                                         stored. Without it: the stored channel,
#                                                         else stable (beta while stable is empty)
#   setup-on-tv.sh key <ok|back|left|right|up|down>...    press keys in the running setup
#   setup-on-tv.sh state                                  print the service's state.json
#   setup-on-tv.sh capture <file.png> [DISPLAY]           a picture of the interface; DISPLAY
#                                                         takes the video plane too
#   setup-on-tv.sh stop                                   close window and service
#   setup-on-tv.sh perf                                   print the frame statistics of a run
#                                                         started with SETUP_PERF=1 (every slide
#                                                         between pages, time to build a page)
#
# Every build needs a new name, because surface-manager caches components by URL.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB=$(CDPATH= cd -- "$HERE/../../lib" && pwd)
APP=com.webos.app.quicksettings
BRIDGE=/tmp/novos-setup
TV=${NOVOS_TV_SSH_TARGET:-lg-tv}

case "${1:-}" in
key)
    shift
    count=0
    for key in "$@"; do
        count=$((count + 1))
        ssh "$TV" "printf '%s %s\n' \$(date +%s)-$$-$count $key > /tmp/novos-setup-keys"
        sleep 0.6
    done
    exit 0 ;;
state)
    ssh "$TV" "cat $BRIDGE/state.json"; echo; exit 0 ;;
perf)
    ssh "$TV" "cat /tmp/novos-perf.ini" | sed -n 's/^log=//p' | sed 's/\\n/\n/g'; echo; exit 0 ;;
capture)
    request='{"path":"/tmp/novos-setup-capture.png","method":"'${3:-GRAPHIC}'","format":"PNG","width":1920,"height":1080}'
    ssh -tt "$TV" "rm -f /tmp/novos-setup-capture.png; luna-send -n 1 -w 5000 luna://com.webos.service.capture/executeOneShot '$request'" >/dev/null 2>&1
    scp -q "$TV:/tmp/novos-setup-capture.png" "$2"; echo "$2"; exit 0 ;;
stop)
    ssh "$TV" "printf '[General]\ncommand=close\nserial=stop-%s\n' \$(date +%s) > $BRIDGE/command.ini; sleep 1; pkill -f 'novos-setupd.p[y] serve'; luna-send -n 1 -w 3000 luna://com.webos.service.systemUIManager/closeByAppId '{\"appId\":\"$APP\"}' >/dev/null 2>&1; true"
    exit 0 ;;
esac

BUILD_NAME=$1
FLOW=${2:-install}
CHANNEL=${3:-}
case "$CHANNEL" in
""|stable|beta) ;;
*) echo "the channel is stable or beta" >&2; exit 2 ;;
esac
REMOTE=/tmp/novos-setup-app/$BUILD_NAME
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$HERE/setup.qml" "$STAGE/"
python3 -I "$LIB/ui/stage.py" "$HERE/module" "$STAGE/module"
if [ "${SETUP_PERF:-0}" = 1 ]; then
    sed -i.orig 's/readonly property bool enabled: false/readonly property bool enabled: true/' "$STAGE/module/PerfProbe.qml"
    rm -f "$STAGE/module/PerfProbe.qml.orig"
fi
cp "$LIB"/ui/fonts/novos-inter-*.ttf "$STAGE/"
mkdir "$STAGE/backgrounds" "$STAGE/tv"
cp "$LIB"/backgrounds/*.jpg "$LIB/backgrounds/index.json" "$STAGE/backgrounds/"
cp "$HERE/tv/novos-setupd.py" "$LIB/release/release.py" "$LIB/release/ed25519.py" "$LIB/release/trusted-keys.json" "$STAGE/tv/"

ssh "$TV" "pkill -f 'novos-setupd.p[y] serve'; find /tmp/novos-setup-app -mindepth 1 -maxdepth 1 -type d -mmin +30 -exec rm -rf {} + 2>/dev/null; rm -rf $BRIDGE /tmp/novos-setup-keys /tmp/novos-perf.ini; mkdir -p $REMOTE $BRIDGE"
scp -qr "$STAGE"/* "$TV:$REMOTE/"
ssh "$TV" "setsid python3 $REMOTE/tv/novos-setupd.py serve --dir $BRIDGE --window file://$REMOTE/setup.qml --app $APP --idle 1800 ${CHANNEL:+--channel $CHANNEL} </dev/null >$BRIDGE/serve.log 2>&1 &"
LAUNCH='{"appId":"'$APP'","main":"file://'$REMOTE'/setup.qml","params":{"flow":"'$FLOW'"}}'
ssh -tt "$TV" "luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId '{\"appId\":\"$APP\"}'; sleep 1; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/launch '$LAUNCH'" >/dev/null 2>&1
echo "setup $FLOW${CHANNEL:+ ($CHANNEL)} running from $REMOTE"
