#!/bin/sh
# Starts the installed novOS interface: checks LG's files, mounts the overlays,
# restarts surface-manager when it runs already and hands over to the supervisor.
#
#   novos-start.sh boot              from the init.d hook, counts failed starts
#   novos-start.sh manual [seconds]  by hand; with seconds a guard stops it again,
#                                   without restarting surface-manager
#
# Nothing of LG is written: the bind mounts vanish with every restart of the TV.
set -u

ROOT=/var/lib/novos
STATE=$ROOT/state
PANEL=$ROOT/current
BIN=$PANEL/bin
MODE=${1:-manual}
LIMIT=${2:-0}
FAILSAFE=/var/luna/preferences/webosbrew_failsafe

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') start[$MODE] $*"; }
# A manual start reports the refusal, a boot simply leaves LG's interface running.
refuse() {
    log "$*, LG's interface stays"
    [ "$MODE" = boot ] && exit 0
    exit 1
}
# The service's main process: a second one of the same name can linger for a while.
sm_pid() { main=$(systemctl show -p MainPID --value surface-manager-daemon.service 2>/dev/null); [ "${main:-0}" = 0 ] || echo "$main"; }
ticks() { awk '{ printf "%d", $1 * 100 }' /proc/uptime; }
setting() { sed -n "s/^$1=//p" "$STATE/novos.conf" 2>/dev/null | tail -1; }
# LG's Home can still arrive after the call. Done only when the app is in front three times,
# 3 s apart; otherwise it is called again, at most five times.
restore_app() {
    tries=0
    good=0
    while [ "$tries" -lt 5 ] && [ "$good" -lt 3 ]; do
        if [ "$(python3 "$BIN/novos-supervisor.py" foreground 2>/dev/null)" = "$1" ]; then
            good=$((good + 1))
            # LG's banner for inputs, which the input app draws itself, stays hidden by
            # the compositor overlay during the restart; a second start as guest, as in
            # the relay, ends it.
            if [ "$good" = 1 ] && [ "$2" != '{}' ]; then
                python3 "$BIN/novos-supervisor.py" call \
                    luna://com.webos.applicationManager/launch "{\"id\":\"$1\",\"params\":$2}" >/dev/null
            fi
        else
            good=0
            tries=$((tries + 1))
            python3 "$BIN/novos-supervisor.py" call luna://com.webos.applicationManager/launch \
                "{\"id\":\"$1\",\"params\":$2}" >/dev/null
            # Watch closely for the new card. A card takes about four seconds; only
            # after eight comes another call.
            waited=0
            while [ "$(python3 "$BIN/novos-supervisor.py" foreground 2>/dev/null)" != "$1" ] && [ "$waited" -lt 26 ]; do
                sleep 0.3
                waited=$((waited + 1))
            done
            continue
        fi
        sleep 3
    done
    [ "$good" -ge 3 ]
}
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
cap() { [ "$({ wc -c < "$1"; } 2>/dev/null || echo 0)" -lt 262144 ] || { tail -n 400 "$1" > "$1.old"; mv "$1.old" "$1"; }; }

case $MODE in
boot|manual) ;;
*) echo "usage: novos-start.sh boot | manual [seconds]" >&2; exit 2 ;;
esac
case $LIMIT in ''|*[!0-9]*) echo "seconds must be a number" >&2; exit 2 ;; esac
mkdir -p "$STATE"
[ ! -e "$STATE/disabled" ] || refuse "disabled: $(cat "$STATE/disabled")"
exec 9>/tmp/novos-start.lock
flock -n 9 || refuse "another start runs"
[ -f "$PANEL/lg-targets.txt" ] || refuse "no release at $PANEL"
version=$(sed -n 's/^version=//p' "$PANEL/VERSION" 2>/dev/null)

# 0. The early start (bin/novos-early.sh) mounted this boot's overlays before surface-manager
#    started: nothing to check, mount or restart. Its watch starts the supervisor once the
#    boot has settled; only without the watch does it start here.
if [ "$MODE" = boot ] && [ -e /tmp/novos-early-mounted ]; then
    log "overlays mounted early, release $(cat /tmp/novos-early-mounted), no restart"
    if ! pgrep -f 'novos-early.s[h] watch' >/dev/null && ! pgrep -f 'novos-supervisor.p[y] run' >/dev/null; then
        cap "$STATE/supervisor.log"
        setsid python3 "$BIN/novos-supervisor.py" run </dev/null >>"$STATE/supervisor.log" 2>&1 9>&- &
        log "supervisor started here, the watch did not run"
    fi
    log "running"
    exit 0
fi

# 1. LG's files must be the originals the overlays were made for, and free.
while read -r name target hash; do
    case $name in ''|'#'*) continue ;; esac
    if grep -Fq " $target " /proc/mounts; then refuse "$target is mounted already"; fi
    [ -s "$PANEL/$name" ] || refuse "$PANEL/$name is missing"
    [ "$(sha256sum "$target" | cut -d' ' -f1)" = "$hash" ] ||
        refuse "$target differs from the checked original, firmware update?"
done < "$PANEL/lg-targets.txt"

# 2. Two failed boots in a row switch the install off. The supervisor resets the
#    count once surface-manager ran for 120 s.
if [ "$MODE" = boot ]; then
    failures=$(cat "$STATE/boot-failures" 2>/dev/null)
    case $failures in ''|*[!0-9]*) failures=0 ;; esac
    if [ "$failures" -ge 2 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') start: $failures failed starts in a row" > "$STATE/disabled"
        sync
        refuse "$failures failed starts in a row, now disabled"
    fi
    echo $((failures + 1)) > "$STATE/boot-failures"
    sync
fi

# 3. Compile check inside the running surface-manager, before anything is mounted. A
#    broken file would not crash surface-manager, it would only leave a window that
#    never opens, so none of the other checks would notice.
selfcheck() {
    real=$(readlink -f "$PANEL")
    check=/tmp/novos-selfcheck-$(date +%s)-$$
    rm -rf /tmp/novos-selfcheck-* /tmp/novos-selfcheck.ini
    mkdir -p "$check/notification"
    for file in selfcheck.qml selfcheck-keys.qml; do
        sed "s#@RELEASE@#$real#g" "$BIN/$file" > "$check/$file"
    done
    lg_dir=$(dirname "$(awk '$1 == "Services.qml" { print $2 }' "$PANEL/lg-targets.txt")")
    for file in "$lg_dir"/*; do ln -s "$file" "$check/notification/"; done
    rm -f "$check/notification/Services.qml"
    ln -s "$real/Services.qml" "$check/notification/Services.qml"
    # The compositor's container imports "../../services/base": a small mirror of its tree.
    # The compositor's files import "../../services/base" and "base": a mirror of its
    # tree from symlinks, with our four copies in place of LG's.
    compositor=$(awk '$1 == "StarfishFullscreenContainer.qml" { print $2 }' "$PANEL/lg-targets.txt")
    views=$(dirname "$(dirname "$compositor")")
    mkdir -p "$check/compositor/views/fullscreen"
    ln -s "$(dirname "$views")/services" "$check/compositor/services"
    mkdir -p "$check/compositor/views/systemUi"
    for file in "$views"/*; do
        case ${file##*/} in fullscreen|systemUi|StarfishImageSplash.qml|StarfishVolumeView.qml) ;; *) ln -s "$file" "$check/compositor/views/" ;; esac
    done
    for file in "$views/fullscreen"/*; do ln -s "$file" "$check/compositor/views/fullscreen/"; done
    for file in "$views/systemUi"/*; do
        [ "${file##*/}" = StarfishSystemUIManager.qml ] || ln -s "$file" "$check/compositor/views/systemUi/"
    done
    ln -s "$real/StarfishSystemUIManager.qml" "$check/compositor/views/systemUi/StarfishSystemUIManager.qml"
    mkdir -p "$check/compositor/controllers"
    for file in "$(dirname "$views")/controllers"/*; do
        [ "${file##*/}" = StarfishViewStateController.qml ] || ln -s "$file" "$check/compositor/controllers/"
    done
    ln -s "$real/StarfishViewStateController.qml" "$check/compositor/controllers/StarfishViewStateController.qml"
    rm -f "$check/compositor/views/fullscreen/StarfishFullscreenContainer.qml"
    ln -s "$real/StarfishFullscreenContainer.qml" "$check/compositor/views/fullscreen/StarfishFullscreenContainer.qml"
    ln -s "$real/StarfishImageSplash.qml" "$check/compositor/views/StarfishImageSplash.qml"
    ln -s "$real/StarfishVolumeView.qml" "$check/compositor/views/StarfishVolumeView.qml"
    # The window runs as LG's StoreStreamer: no key opens that before the mount. As the
    # quick menu it collided with a menu the user had open, and nothing was checked.
    attempt=0
    while [ "$attempt" -lt 4 ] && ! grep -q '^verdict=.' /tmp/novos-selfcheck.ini 2>/dev/null; do
        attempt=$((attempt + 1))
        [ "$attempt" = 1 ] || {
            log "compile check: no answer, attempt $attempt"
            python3 "$BIN/novos-supervisor.py" call luna://com.webos.service.systemUIManager/closeByAppId \
                '{"appId":"com.webos.app.store-streamer"}' >/dev/null
            sleep 5
        }
        answer=$(python3 "$BIN/novos-supervisor.py" call luna://com.webos.service.systemUIManager/launch \
            "{\"appId\":\"com.webos.app.store-streamer\",\"main\":\"file://$check/selfcheck.qml\"}")
        case $answer in *'"returnValue": true'*) ;; *) log "compile check: launch answered $answer" ;; esac
        waited=0
        while ! grep -q '^verdict=.' /tmp/novos-selfcheck.ini 2>/dev/null && [ "$waited" -lt 15 ]; do
            sleep 1
            waited=$((waited + 1))
        done
    done
    verdict=$(sed -n 's/^verdict=//p' /tmp/novos-selfcheck.ini 2>/dev/null)
    detail=$(sed -n 's/^detail=//p' /tmp/novos-selfcheck.ini 2>/dev/null)
    rm -rf "$check"
    [ "$verdict" = ok ]
}
waited=0
while [ -z "$(sm_pid)" ] && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
[ -n "$(sm_pid)" ] || refuse "surface-manager does not run, nothing to check the release with"
if ! selfcheck; then
    if [ "$verdict" = fail ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') start: release $version does not compile: $detail" > "$STATE/disabled"
        sync
        refuse "release $version does not compile, now disabled: $detail"
    fi
    refuse "no answer from the compile check after 4 attempts"
fi
log "compile check passed"

# 4. Defaults: blur 84 px. The pointer of the Magic Remote is set off by the overlay
#    of systemUi.js at every start. Changed debug values are kept.
[ -f "$STATE/debug.ini" ] || printf '[General]\nblur=84\nhideInputBanner=true\n' > "$STATE/debug.ini"

# 5. Mount. What runs in front now comes back after the restart below.
app=""
[ -z "$(sm_pid)" ] || app=$(python3 "$BIN/novos-supervisor.py" foreground 2>/dev/null)
done_mounts=""
while read -r name target hash; do
    case $name in ''|'#'*) continue ;; esac
    if ! mount --bind "$PANEL/$name" "$target"; then
        for undo in $done_mounts; do umount "$undo"; done
        refuse "mount of $target failed"
    fi
    done_mounts="$done_mounts $target"
done < "$PANEL/lg-targets.txt"
mounted_at=$(ticks)
log "mounted release $version"

# 6. A surface-manager that started before the mounts still holds LG's files.
pid=$(sm_pid)
if [ -n "$pid" ] && [ "$(awk '{ print $22 }' "/proc/$pid/stat")" -lt "$mounted_at" ]; then
    # While the interface restarts LG's Home, its input splash, its banner and its
    # toasts stay out of sight. The overlays honour the flag for three minutes at most.
    echo "on $(date +%s)" > /tmp/novos-booting
    # The launcher's note dies with surface-manager; a stale one would block the source key.
    rm -f /tmp/novos-launcher-open.ini
    if [ "$MODE" = boot ]; then
        # Homebrew removes its failsafe flag 10 s after the hooks. A restart before
        # that could pass for a crash during startup.
        waited=0
        while [ -e "$FAILSAFE" ] && [ "$waited" -lt 90 ]; do sleep 1; waited=$((waited + 1)); done
    fi
    log "restarting surface-manager $pid${app:+, then back to $app}"
    release_clients
    systemctl restart --no-block surface-manager-daemon.service
    waited=0
    while { [ -z "$(sm_pid)" ] || [ "$(sm_pid)" = "$pid" ]; } && [ "$waited" -lt 30 ]; do
        sleep 1
        waited=$((waited + 1))
    done
    return_clients
    # The new surface-manager starts LG's Home (out of sight) by itself; the way back
    # to the source starts once Home is there, so that Home does not follow it.
    until_time=$(( $(date +%s) + 60 ))
    until [ "$(python3 "$BIN/novos-supervisor.py" foreground 2>/dev/null)" = com.webos.app.home ] ||
          [ "$(date +%s)" -ge "$until_time" ]; do
        sleep 0.3
    done
    sleep 1
    if [ -n "$app" ] && [ "$app" != com.webos.app.home ] && [ "$(setting restoreSource)" != false ]; then
        params='{}'
        case $app in
        com.webos.app.hdmi*)
            grep -q '^hideInputBanner=false' "$STATE/debug.ini" || params='{"appViewRole":"appViewGuest"}' ;;
        esac
        if restore_app "$app" "$params"; then log "back to $app"; else log "could not go back to $app"; fi
    fi
elif [ -z "$pid" ]; then
    log "surface-manager not running yet, it starts with the overlays"
fi

# The restart is over: LG's input layer shows again, our pill names the source.
if [ -e /tmp/novos-booting ]; then
    echo done > /tmp/novos-booting
    case $app in
    com.webos.app.hdmi*|com.webos.app.livetv)
        sleep 1
        python3 "$BIN/novos-supervisor.py" call luna://com.webos.service.systemUIManager/launch \
            "{\"appId\":\"com.webos.app.quickinputpicker\",\"params\":{\"banner\":true,\"appId\":\"$app\"}}" >/dev/null ;;
    esac
fi

# 7. The supervisor keeps the relay alive and watches surface-manager. A manual
#    test can get a guard that stops everything again.
pkill -f 'novos-supervisor.p[y] run' 2>/dev/null
cap "$STATE/supervisor.log"
# 9>&- : the lock of this start must not live on in the children.
setsid python3 "$BIN/novos-supervisor.py" run </dev/null >>"$STATE/supervisor.log" 2>&1 9>&- &
if [ "$LIMIT" -gt 0 ]; then
    setsid sh -c "sleep $LIMIT; sh '$BIN/novos-stop.sh' --no-restart; : novos-guard" \
        </dev/null >>"$STATE/start.log" 2>&1 9>&- &
    log "guard stops it in $LIMIT s"
fi
log "running"
