#!/bin/sh
# Stops the novOS interface and proves that LG's originals are back.
#
#   novos-stop.sh                 restarts surface-manager, so that no window of ours
#                                stays loaded, and goes back to what ran before
#   novos-stop.sh --no-restart    leaves the picture alone; windows already loaded
#                                stay ours until surface-manager restarts
#   novos-stop.sh --no-restart --keep-hidden
#                                as before, for an update: the relay's marker stays, so
#                                that the windows still loaded keep LG's Home, toasts and
#                                dialogs out of sight until novos-start.sh restarts the
#                                interface. The updater removes it if novOS does not start.
#
# Exits with 1 when a mount is left or a hash differs.
set -u

BIN=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGETS=${NOVOS_TARGETS:-$BIN/../lg-targets.txt}
[ -f "$TARGETS" ] || TARGETS=$BIN/lg-targets.txt
RESTART=yes
KEEP_HIDDEN=no
for arg in "$@"; do
    case $arg in
    --no-restart) RESTART=no ;;
    --keep-hidden) KEEP_HIDDEN=yes ;;
    esac
done
# Only without a restart: a new surface-manager without our overlays would hide LG's Home
# with nothing in its place.
[ "$RESTART" = no ] || KEEP_HIDDEN=no

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') stop $*"; }
# The service's main process: a second one of the same name can linger for a while.
sm_pid() { main=$(systemctl show -p MainPID --value surface-manager-daemon.service 2>/dev/null); [ "${main:-0}" = 0 ] || echo "$main"; }
helper() { [ -f "$BIN/novos-supervisor.py" ] && python3 "$BIN/novos-supervisor.py" "$@"; }
# LG's native apps die with an abort or a segfault when the compositor goes away under
# them, LG's input app inputcommon (from its CRIU image) among them. Each such crash is
# a fault for LG's faultmanager, and tvpowerd then reboots the TV at the next power off
# ("rebootByFault", "rebootToSuspend"). LG's surface-manager.sh kills its native apps
# itself after a respawn, but only at the next start, after the crash. Killed here
# before the stop, as LG does, they leave no crash report; SAM starts them again.
# LG's HDMI service extinput-integration is a client too and aborts the same way; it is
# stopped cleanly, which leaves no report, and started again after the restart.
release_clients() {
    pkill -9 -f '"@system_native_ap[p]"' 2>/dev/null
    pkill -9 -f '^/usr/bin/com[.]webos[.]app[.]inputcommo[n]' 2>/dev/null
    extinput_stopped=no
    if [ "$(systemctl is-active extinput-integration.service 2>/dev/null)" = active ]; then
        timeout 15 systemctl stop extinput-integration.service && extinput_stopped=yes
    fi
}
return_clients() {
    [ "${extinput_stopped:-no}" = no ] || systemctl start --no-block extinput-integration.service
}
# LG's Home can still arrive after the call. Done only when the app is in front three times,
# 3 s apart; otherwise it is called again, at most five times.
restore_app() {
    tries=0
    good=0
    while [ "$tries" -lt 5 ] && [ "$good" -lt 3 ]; do
        if [ "$(python3 "$BIN/novos-supervisor.py" foreground 2>/dev/null)" = "$1" ]; then
            good=$((good + 1))
        else
            good=0
            tries=$((tries + 1))
            python3 "$BIN/novos-supervisor.py" call luna://com.webos.applicationManager/launch \
                "{\"id\":\"$1\",\"params\":$2}" >/dev/null
        fi
        sleep 3
    done
    [ "$good" -ge 3 ]
}
[ -f "$TARGETS" ] || { log "lg-targets.txt not found"; exit 1; }

pkill -f 'novos-guar[d]' 2>/dev/null
# The early start mounts nothing more in this boot, also not before the restart below.
: > /tmp/novos-early-off
pkill -f 'novos-early.s[h] watch' 2>/dev/null
rm -f /tmp/novos-early-mounted /tmp/novos-early-starts /tmp/novos-stable
pkill -f 'novos-supervisor.p[y] run' 2>/dev/null
# Without the marker LG's toasts, dialogs and Home come back at once.
[ "$KEEP_HIDDEN" = yes ] || rm -f /tmp/novos-banner-active
rm -f /tmp/novos-booting /tmp/novos-launcher-open.ini /tmp/novos-nosignal-open.ini /tmp/novos-panel-open.ini
pkill -f 'banner-relay.p[y]' 2>/dev/null

app=""
[ "$RESTART" = no ] || app=$(helper foreground 2>/dev/null)
while read -r name target hash; do
    case $name in ''|'#'*) continue ;; esac
    tries=0
    while grep -Fq " $target " /proc/mounts && [ "$tries" -lt 5 ]; do
        umount "$target" || break
        tries=$((tries + 1))
    done
done < "$TARGETS"

if [ "$RESTART" = yes ]; then
    pid=$(sm_pid)
    release_clients
    systemctl restart --no-block surface-manager-daemon.service
    waited=0
    while { [ -z "$(sm_pid)" ] || [ "$(sm_pid)" = "$pid" ]; } && [ "$waited" -lt 30 ]; do
        sleep 1
        waited=$((waited + 1))
    done
    return_clients
    sleep 4
    if [ -n "$app" ] && [ "$app" != com.webos.app.home ]; then
        if [ -f "$BIN/novos-supervisor.py" ] && restore_app "$app" '{}'; then log "back to $app"; else log "could not go back to $app"; fi
    fi
fi

status=0
while read -r name target hash; do
    case $name in ''|'#'*) continue ;; esac
    if grep -Fq " $target " /proc/mounts; then
        log "STILL MOUNTED $target"
        status=1
    elif [ "$(sha256sum "$target" | cut -d' ' -f1)" != "$hash" ]; then
        log "HASH DIFFERS $target"
        status=1
    fi
done < "$TARGETS"
[ "$status" = 0 ] && log "all $(grep -c '^[^#]' "$TARGETS") originals restored"
log "jail copies left: $(grep -cE '(QuickSettings\.qml|InputPicker\.qml|Notification/Services\.qml|StoreStreamer\.qml|systemUi\.js|StarfishFullscreenContainer\.qml|StarfishImageSplash\.qml|StarfishSystemUIManager\.qml|StarfishViewStateController\.qml|StarfishVolumeView\.qml|appLaunch\.js|MasterBrand\.qml|com\.palm\.app\.settings/index[.a-z]*html) ' /proc/mounts)"
exit "$status"
