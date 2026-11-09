#!/bin/sh
# Tests the panel on the physical gear key with a temporary bind mount.
#
#   gear-test-on-tv.sh prepare            uploads the panel and runs one preview
#   gear-test-on-tv.sh mount <seconds>    mounts it, the TV removes it after <seconds>
#   gear-test-on-tv.sh rollback           removes the mount now
#   gear-test-on-tv.sh status             shows hash, mounts and processes
#
# The system file is never written. The mount lives in RAM and a reboot removes it.
set -eu
TV=${NOVOS_TV:?"set NOVOS_TV to the SSH target of the TV as root, e.g. root@<tv-ip>"}

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PANEL_DIR=/tmp/novos-panel
# Files and original hashes come from the list the install uses as well.
lg() { awk -v name="$1" -v column="$2" '$1 == name { print $column }' "$HERE/install/lg-targets.txt"; }
TARGET=$(lg QuickSettings.qml 2)
ORIGINAL_HASH=$(lg QuickSettings.qml 3)
PICKER_TARGET=$(lg InputPicker.qml 2)
PICKER_HASH=$(lg InputPicker.qml 3)
LAUNCHER_TARGET=$(lg StoreStreamer.qml 2)
LAUNCHER_HASH=$(lg StoreStreamer.qml 3)
KEYS_TARGET=$(lg systemUi.js 2)
KEYS_HASH=$(lg systemUi.js 3)
TOAST_TARGET=$(lg Services.qml 2)
TOAST_HASH=$(lg Services.qml 3)

upload() {
    STAGE=$(mktemp -d)
    # The same build as the install, with the panel in /tmp and the values in /tmp.
    "$HERE/install/build-release.sh" "$STAGE/panel" "$PANEL_DIR" /tmp/novos-
    ssh "$TV" "rm -rf $PANEL_DIR; mkdir -p $PANEL_DIR"
    scp -qr "$STAGE"/panel/* "$TV:$PANEL_DIR/"
    rm -rf "$STAGE"
    # LG's files stay out of this repository: the copies are made on the TV.
    ssh "$TV" "sh $PANEL_DIR/bin/make-overlays.sh $PANEL_DIR"
}

case "$1" in
prepare)
    upload
    ssh "$TV" "cat $PANEL_DIR/QuickSettings.qml | sha256sum"
    REQUEST='{"appId":"com.webos.app.quicksettings","main":"file://'$PANEL_DIR'/QuickSettings.qml"}'
    ssh -tt "$TV" "luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId '{\"appId\":\"com.webos.app.quicksettings\"}'; sleep 1; luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/launch '$REQUEST'" >/dev/null 2>&1
    ;;
mount)
    SECONDS_MOUNTED=$2
    ssh "$TV" sh -s "$SECONDS_MOUNTED" "$TARGET" "$ORIGINAL_HASH" "$PICKER_TARGET" "$PICKER_HASH" "$PANEL_DIR" "$TOAST_TARGET" "$TOAST_HASH" "$LAUNCHER_TARGET" "$LAUNCHER_HASH" "$KEYS_TARGET" "$KEYS_HASH" <<'REMOTE'
set -eu
seconds=$1; target=$2; original=$3; picker=$4; picker_original=$5; panel=$6; toast=$7; toast_original=$8
launcher=$9; shift 9; launcher_original=$1; keys=$2; keys_original=$3
for file in "$target" "$picker" "$toast" "$launcher" "$keys"; do
    if grep -Fq " $file " /proc/mounts; then echo "already mounted: $file (installed version? novos-on-tv.sh stop)"; exit 1; fi
done
if pgrep -f 'novos-supervisor.p[y] run' >/dev/null; then echo "installed version runs: novos-on-tv.sh stop"; exit 1; fi
[ "$(sha256sum "$launcher" | cut -d' ' -f1)" = "$launcher_original" ] || { echo "launcher hash differs"; exit 1; }
[ "$(sha256sum "$keys" | cut -d' ' -f1)" = "$keys_original" ] || { echo "keys hash differs"; exit 1; }
[ "$(sha256sum "$toast" | cut -d' ' -f1)" = "$toast_original" ] || { echo "toast hash differs"; exit 1; }
[ "$(sha256sum "$target" | cut -d' ' -f1)" = "$original" ] || { echo "panel hash differs"; exit 1; }
[ "$(sha256sum "$picker" | cut -d' ' -f1)" = "$picker_original" ] || { echo "picker hash differs"; exit 1; }
# No restart here: it would throw whatever runs on the TV back to Home.
cat > /tmp/novos-rollback.sh <<GUARD
#!/bin/sh
sleep $seconds
umount $target 2>/dev/null
umount $picker 2>/dev/null
umount $toast 2>/dev/null
umount $launcher 2>/dev/null
umount $keys 2>/dev/null
rm -f /tmp/novos-banner-active
pkill -f "banner-relay.p[y]"
GUARD
nohup sh /tmp/novos-rollback.sh >/dev/null 2>&1 &
mount --bind "$panel/QuickSettings.qml" "$target"
mount --bind "$panel/InputPicker.qml" "$picker"
mount --bind "$panel/Services.qml" "$toast"
mount --bind "$panel/StoreStreamer.qml" "$launcher"
mount --bind "$panel/systemUi.js" "$keys"
echo on > /tmp/novos-banner-active
nohup python3 "$panel/banner-relay.py" "$seconds" /tmp/novos-banner-active >/dev/null 2>&1 &
sed -i 's/^blur=.*/blur=84/' /tmp/novos-debug.ini 2>/dev/null || true
systemctl restart --no-block surface-manager-daemon.service
echo "mounted, removed automatically in $seconds s"
REMOTE
    ;;
rollback)
    ssh "$TV" sh -s "$TARGET" "$ORIGINAL_HASH" "$PICKER_TARGET" "$PICKER_HASH" "$TOAST_TARGET" "$TOAST_HASH" "$LAUNCHER_TARGET" "$LAUNCHER_HASH" "$KEYS_TARGET" "$KEYS_HASH" <<'REMOTE'
target=$1; original=$2; picker=$3; picker_original=$4; toast=$5; toast_original=$6; launcher=$7; launcher_original=$8; keys=$9; shift 9; keys_original=$1
pkill -f "novos-rollback.s[h]" 2>/dev/null
rm -f /tmp/novos-banner-active
pkill -f "banner-relay.p[y]" 2>/dev/null
for file in "$target" "$picker" "$toast" "$launcher" "$keys"; do
    if grep -Fq " $file " /proc/mounts; then umount "$file"; fi
done
systemctl restart --no-block surface-manager-daemon.service
sleep 1
restored=yes
for pair in "$target=$original" "$picker=$picker_original" "$toast=$toast_original" "$launcher=$launcher_original" "$keys=$keys_original"; do
    [ "$(sha256sum "${pair%%=*}" | cut -d' ' -f1)" = "${pair#*=}" ] || { echo "HASH DIFFERS ${pair%%=*}"; restored=no; }
done
[ "$restored" = yes ] && echo "all 5 originals restored"
echo "jail copies left: $(grep -cE '(QuickSettings\.qml|InputPicker\.qml|Notification/Services\.qml|StoreStreamer\.qml|systemUi\.js|StarfishFullscreenContainer\.qml|StarfishImageSplash\.qml|StarfishSystemUIManager\.qml|StarfishViewStateController\.qml|StarfishVolumeView\.qml) ' /proc/mounts)"
REMOTE
    ;;
status)
    ssh "$TV" "sha256sum $TARGET $PICKER_TARGET $TOAST_TARGET $LAUNCHER_TARGET $KEYS_TARGET | cut -c1-16; grep -c ' $TARGET ' /proc/mounts; grep -c ' $PICKER_TARGET ' /proc/mounts; grep -c ' $TOAST_TARGET ' /proc/mounts; grep -c ' $LAUNCHER_TARGET ' /proc/mounts; grep -c ' $KEYS_TARGET ' /proc/mounts; systemctl is-active surface-manager-daemon.service; echo sm=\$(pgrep -x surface-manager | head -1) feed=\$(pgrep -f '[v]t-feed.py' | wc -l) guard=\$(pgrep -f 'novos-rollback.s[h]' | wc -l) relay=\$(pgrep -f 'banner-relay.p[y]' | wc -l) marker=\$(ls /tmp/novos-banner-active 2>/dev/null | wc -l)" || true
    ;;
esac
