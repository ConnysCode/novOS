#!/bin/sh
# Runs the setup on the TV from /tmp, as it will run from the setup app: novos-setupd serve
# as root and the setup's window. Nothing is installed by this script itself; the setup
# does what it is told on the TV, an install included.
#
#   setup-on-tv.sh <build-name> [install|update|remove]   start the setup with this flow
#   setup-on-tv.sh key <ok|back|left|right|up|down>...    press keys in the running setup
#   setup-on-tv.sh state                                  print the service's state.json
#   setup-on-tv.sh capture <file.png>                     a picture of the interface
#   setup-on-tv.sh stop                                   close window and service
#
# Every build needs a new name, because surface-manager caches components by URL.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB=$(CDPATH= cd -- "$HERE/../../lib" && pwd)
APP=com.webos.app.quicksettings
BRIDGE=/tmp/novos-setup

case "${1:-}" in
key)
    shift
    count=0
    for key in "$@"; do
        count=$((count + 1))
        ssh lg-tv "printf '%s %s\n' \$(date +%s)-$$-$count $key > /tmp/novos-setup-keys"
        sleep 0.6
    done
    exit 0 ;;
state)
    ssh lg-tv "cat $BRIDGE/state.json"; echo; exit 0 ;;
capture)
    request='{"path":"/tmp/novos-setup-capture.png","method":"GRAPHIC","format":"PNG","width":1920,"height":1080}'
    ssh -tt lg-tv "rm -f /tmp/novos-setup-capture.png; luna-send -n 1 -w 5000 luna://com.webos.service.capture/executeOneShot '$request'" >/dev/null 2>&1
    scp -q lg-tv:/tmp/novos-setup-capture.png "$2"; echo "$2"; exit 0 ;;
stop)
    ssh lg-tv "printf '[General]\ncommand=close\nserial=stop-%s\n' \$(date +%s) > $BRIDGE/command.ini; sleep 1; pkill -f 'novos-setupd.p[y] serve'; luna-send -n 1 -w 3000 luna://com.webos.service.systemUIManager/closeByAppId '{\"appId\":\"$APP\"}' >/dev/null 2>&1; true"
    exit 0 ;;
esac

BUILD_NAME=$1
FLOW=${2:-install}
REMOTE=/tmp/novos-setup-app/$BUILD_NAME
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$HERE/setup.qml" "$STAGE/"
python3 -I "$LIB/ui/stage.py" "$HERE/module" "$STAGE/module"
cp "$LIB"/ui/fonts/novos-inter-*.ttf "$STAGE/"
mkdir "$STAGE/backgrounds" "$STAGE/tv"
cp "$LIB"/backgrounds/*.jpg "$LIB/backgrounds/index.json" "$STAGE/backgrounds/"
cp "$HERE/tv/novos-setupd.py" "$LIB/release/release.py" "$LIB/release/ed25519.py" "$LIB/release/trusted-keys.json" "$STAGE/tv/"

ssh lg-tv "pkill -f 'novos-setupd.p[y] serve'; find /tmp/novos-setup-app -mindepth 1 -maxdepth 1 -type d -mmin +30 -exec rm -rf {} + 2>/dev/null; rm -rf $BRIDGE /tmp/novos-setup-keys; mkdir -p $REMOTE $BRIDGE"
scp -qr "$STAGE"/* "lg-tv:$REMOTE/"
ssh lg-tv "setsid python3 $REMOTE/tv/novos-setupd.py serve --dir $BRIDGE --window file://$REMOTE/setup.qml --app $APP --idle 1800 </dev/null >$BRIDGE/serve.log 2>&1 &"
LAUNCH='{"appId":"'$APP'","main":"file://'$REMOTE'/setup.qml","params":{"flow":"'$FLOW'"}}'
ssh -tt lg-tv "luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId '{\"appId\":\"$APP\"}'; sleep 1; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/launch '$LAUNCH'" >/dev/null 2>&1
echo "setup $FLOW running from $REMOTE"
