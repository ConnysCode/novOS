#!/bin/sh
# Early start of the installed novOS interface, before the first picture of a boot.
#
#   novos-early.sh kick    from the luna-send stand-in in bin/kick, at about 16 s: restarts
#                         surface-manager once, which started before /var was writable
#   novos-early.sh mount   from the PmLogCtl stand-in in bin/early, before every start of
#                         surface-manager; mounts only before the first one with our
#                         environment, and counts the later ones
#   novos-early.sh undo    after a mount that failed or ran out of time
#   novos-early.sh watch   in the background after an early mount: Homebrew's startup,
#                         the end of the boot, then the supervisor
#
# It mounts only a release that ran stable once before, after its compile check through
# the Homebrew hook (state/early-release, written by the supervisor), and only over LG's
# checked originals. Otherwise it does nothing, and the start through Homebrew works as
# before: mount, restart of surface-manager.
set -u

ROOT=/var/lib/novos
STATE=$ROOT/state
PANEL=$ROOT/current
BIN=$PANEL/bin
MODE=${1:-mount}
OFF=/tmp/novos-early-off          # stop and uninstall: no early mount until the next boot
MOUNTED=/tmp/novos-early-mounted  # this boot's overlays came from here
MOUNTING=/tmp/novos-early-mounting
STARTS=/tmp/novos-early-starts    # one line per start of surface-manager since the mount
STABLE=/tmp/novos-stable          # the supervisor: surface-manager ran 120 s with the overlays
CRASH_STARTS=3                   # starts before a stable run that undo the early mount
SETTLE_LIMIT=70                  # seconds of uptime after which the boot counts as settled
RESTORE_TRIES=5                  # calls of the last source while nothing else is in front
WATCH_LIMIT=180
SM_ENV=/var/systemd/system/env/surface-manager.env
LAST_APP=/var/luna/preferences/bootd_last_foreground_app_id.json
CHECKED=/tmp/novos-early-checked  # release whose LG files the kick found original in this boot
READY=/tmp/novos-early-ready      # uptime when the surface-manager restarted by the kick was ready
MOUNTS=""

# Uptime from the shell itself, whole seconds and with hundredths.
up() { read -r uptime _ < /proc/uptime; echo "${uptime%.*}"; }
upf() { read -r uptime _ < /proc/uptime; echo "$uptime"; }
# The clock can still stand in 2023 at this point, the uptime tells the time of the boot.
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') early[$MODE] at $(upf) s: $*"; }
# <name> <LG file> <hash> per line, read without helper programs: early in a cold boot
# the CPU is busy, and every started program costs time the compositor waits for.
targets() {
    while read -r name target hash; do
        case $name in ''|'#'*) continue ;; esac
        echo "$name $target $hash"
    done < "$PANEL/lg-targets.txt"
}
# Whether an LG file has something mounted over it, from one read of /proc/mounts.
mounted_over() {
    case $MOUNTS in *" $1 "*) return 0 ;; esac
    return 1
}
read_mounts() { MOUNTS=$(cat /proc/mounts); }
setting() { sed -n "s/^$1=//p" "$STATE/debug.ini" 2>/dev/null | tail -1; }
helper() { python3 "$BIN/novos-supervisor.py" "$@"; }

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
unmount_all() {
    targets | while read -r name target hash; do
        tries=0
        while grep -Fq " $target " /proc/mounts && [ "$tries" -lt 5 ]; do
            umount "$target" || break
            tries=$((tries + 1))
        done
    done
}

# Runs outside the cgroup of surface-manager-daemon.service, whose restart would end it.
detach() {
    unit=$1
    shift
    systemd-run --no-block --quiet --unit="$unit-$(up)-$$" /bin/sh -c "$*"
}

# Everything that must hold before an early mount, for kick and mount alike. Sets
# $release and $failures.
switched_on() {
    [ ! -e "$OFF" ] || { log "off until the next boot"; return 1; }
    [ ! -e "$STATE/disabled" ] || { log "disabled: $(cat "$STATE/disabled")"; return 1; }
    [ -f "$PANEL/lg-targets.txt" ] || { log "no release"; return 1; }
    release=$(readlink "$PANEL")
    release=${release##*/}
}
ready() {
    [ "$(cat "$STATE/early-release" 2>/dev/null)" = "$release" ] || {
        log "release $release has not run stable yet, the start through Homebrew mounts it"
        return 1
    }
    failures=$(cat "$STATE/boot-failures" 2>/dev/null)
    case $failures in ''|*[!0-9]*) failures=0 ;; esac
    if [ "$failures" -ge 2 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') early: $failures failed starts in a row" > "$STATE/disabled"
        sync
        log "$failures failed starts in a row, now disabled"
        return 1
    fi
    # The hashes once per boot, in the kick; the mount relies on CHECKED for this release.
    [ "$(cat "$CHECKED" 2>/dev/null)" != "$release" ] || return 0
    read_mounts
    bad=""
    while read -r name target hash; do
        [ -s "$PANEL/$name" ] || { bad="$bad $PANEL/$name is missing;"; continue; }
        if mounted_over "$target"; then bad="$bad $target is mounted already;"; continue; fi
        sum=$(sha256sum "$target")
        [ "${sum%% *}" = "$hash" ] || bad="$bad $target differs from the checked original, firmware update?;"
    done <<LIST
$(targets)
LIST
    [ -z "$bad" ] || { log "$bad LG's interface stays"; return 1; }
    echo "$release" > "$CHECKED"
}

# surface-manager started before /var was writable and runs without our PATH: one
# restart, before the first picture, lets it read surface-manager.env.
kick() {
    switched_on || return 0
    grep -q '^# novOS early start' "$SM_ENV" 2>/dev/null || { log "no surface-manager.env of ours"; return 0; }
    pid=$(systemctl show -p MainPID --value surface-manager-daemon.service 2>/dev/null)
    [ "${pid:-0}" != 0 ] || { log "surface-manager does not run, it starts with our PATH"; return 0; }
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q "^PATH=$BIN/early:"; then
        log "surface-manager $pid has our PATH already"
        return 0
    fi
    began=$(upf)
    ready || return 0
    echo "on $(date +%s)" > /tmp/novos-booting
    log "surface-manager $pid started before /var was writable, restarting it (checks began at $began s)"
    release_clients
    systemctl restart --no-block surface-manager-daemon.service
    # Beside the kick: LG's boot restores inputcommon from its CRIU image at about 20 s,
    # and the watch's call of the source does too, while the new surface-manager is not
    # ready yet; it takes until about 30 s under the load of the boot. Such a copy
    # crashes the moment the screen appears. Until surface-manager is ready, every copy
    # is killed, which leaves no report. READY tells the watch when the source may come.
    {
        # Fast, beside the slow systemctl below: busybox pgrep only.
        {
            killed=0
            waited=0
            while [ ! -e "$READY" ] && [ "$waited" -lt 600 ]; do
                for client in $(pgrep -f '^/usr/bin/com[.]webos[.]app[.]inputcommo[n]'); do
                    kill -9 "$client" && killed=$((killed + 1))
                done
                sleep 0.2
                waited=$((waited + 1))
            done
            log "inputcommon killed $killed times until surface-manager was ready"
        } &
        waited=0
        while [ "$(systemctl show -p MainPID --value surface-manager-daemon.service 2>/dev/null)" = "$pid" ] &&
              [ "$waited" -lt 60 ]; do
            sleep 0.5
            waited=$((waited + 1))
        done
        waited=0
        while [ "$(systemctl is-active surface-manager-daemon.service 2>/dev/null)" != active ] &&
              [ "$waited" -lt 120 ]; do
            sleep 0.5
            waited=$((waited + 1))
        done
        ready_us=$(systemctl show -p ActiveEnterTimestampMonotonic --value surface-manager-daemon.service 2>/dev/null)
        ready_us=${ready_us:-0}
        upf > "$READY"
        log "new surface-manager ready at $((ready_us / 1000000)).$((ready_us / 100000 % 10)) s"
        return_clients
    } </dev/null >>"$STATE/early.log" 2>&1 &
}

mount_all() {
    switched_on || return 0
    read_mounts
    present=0
    while read -r name target hash; do
        ! mounted_over "$target" || present=$((present + 1))
    done <<LIST
$(targets)
LIST
    if [ "$present" -gt 0 ]; then
        [ -e "$MOUNTED" ] || { log "overlays mounted by a start by hand, nothing to do"; return 0; }
        [ ! -e "$STABLE" ] || { log "start of surface-manager after a stable run, overlays stay"; return 0; }
        up >> "$STARTS"
        starts=$(wc -l < "$STARTS" | tr -d ' ')
        if [ "$starts" -ge "$CRASH_STARTS" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') early: surface-manager started $starts times before it ran stable" \
                > "$STATE/disabled"
            sync
            unmount_all
            rm -f "$MOUNTED" /tmp/novos-booting /tmp/novos-banner-active
            log "surface-manager started $starts times before it ran stable: disabled, it starts with LG's files"
        else
            log "start $starts of surface-manager with the overlays"
        fi
        return 0
    fi

    began=$(upf)
    ready || return 0
    # LG's Home, its input splash, its banner and its toasts stay out of sight until the
    # boot has settled and the relay runs. The watch below keeps the flag fresh.
    echo "on $(date +%s)" > /tmp/novos-booting
    rm -f /tmp/novos-launcher-open.ini /tmp/novos-nosignal-open.ini /tmp/novos-panel-open.ini "$STARTS"
    : > "$MOUNTING"
    while read -r name target hash; do
        mount --bind "$PANEL/$name" "$target" || {
            unmount_all
            rm -f "$MOUNTING" /tmp/novos-booting
            log "mount of $target failed, LG's interface stays"
            return 1
        }
    done <<LIST
$(targets)
LIST
    up > "$STARTS"
    echo "$release" > "$MOUNTED"
    rm -f "$MOUNTING"
    # Counted only once the mount stands; the supervisor resets it after 120 s.
    echo $((failures + 1)) > "$STATE/boot-failures"
    [ -f "$STATE/debug.ini" ] || printf '[General]\nblur=84\nhideInputBanner=true\n' > "$STATE/debug.ini"
    log "mounted release $release before surface-manager starts (began at $began s)"
    # In the background: systemd-run can take seconds in a cold boot, and the compositor
    # waits for this script.
    { detach novos-early-watch "exec sh '$BIN/novos-early.sh' watch </dev/null >>'$STATE/early.log' 2>&1" ||
        log "could not start the watch"; sync; } &
    return 0
}

undo() {
    [ -e "$MOUNTING" ] || { log "no mount was cut short"; return 0; }
    unmount_all
    rm -f "$MOUNTING" "$MOUNTED" /tmp/novos-booting
    log "mount cut short, undone, LG's interface stays"
}

input_app() {
    case $1 in com.webos.app.hdmi*|com.webos.app.dp*|com.webos.app.usbc*|com.webos.app.livetv) return 0 ;; esac
    return 1
}

watch() {
    log "watch started"
    settled=0
    app=""
    supervisor=no
    tries=0
    mounted_at=$(head -n 1 "$STARTS" 2>/dev/null)
    case $mounted_at in ''|*[!0-9]*) mounted_at=$(up) ;; esac
    next_try=$((mounted_at + 6))
    launcher=no
    hb_pid=0
    hb_next=0
    hb_calls=0
    while [ "$(up)" -lt "$WATCH_LIMIT" ]; do
        [ -e "$MOUNTED" ] || { log "overlays gone, watch ends"; return 0; }
        # Homebrew's startup script brings ssh and our hook in init.d. Its own trigger
        # waits for LG's Home to load app previews; the same call comes earlier from here.
        # The script runs once per boot, a second call does nothing.
        # The call waits for the whole script, so it runs beside this loop, every 3 s.
        if [ ! -e /tmp/webosbrew_startup ] && [ "$(up)" -ge "$hb_next" ] &&
           { [ "$hb_pid" = 0 ] || ! kill -0 "$hb_pid" 2>/dev/null; }; then
            helper call luna://org.webosbrew.hbchannel.service/autostart '{}' >/dev/null 2>&1 &
            hb_pid=$!
            hb_next=$(( $(up) + 3 ))
            [ "$hb_calls" -gt 0 ] || log "Homebrew startup called"
            hb_calls=$((hb_calls + 1))
        fi
        if [ "$supervisor" = no ]; then
            # The clock jumps from 2023 to today in the first seconds, the flag follows it.
            echo "on $(date +%s)" > /tmp/novos-booting
            app=$(helper foreground 2>/dev/null)
            [ "$app" = "${seen:-?}" ] || log "in front: ${app:-no app}"
            seen=$app
            # LG's boot starts its first app, the last source, at about 20 s, while our kick
            # restarts surface-manager: that start comes to nothing. In front is then no app
            # at all, or LG's Home, hidden by us, which keys would go to. 6 s after the
            # mount the last source is called, as novos-start.sh does after its restart, and
            # again every 8 s while nothing else is in front: LG's own Home comes up only
            # about 16 s after the restart and swallows an earlier call. With Home or an app
            # as last app nothing is called.
            case $app in ''|com.webos.app.home) empty=yes ;; *) empty=no ;; esac
            # Not before the restarted surface-manager is ready, see kick.
            if [ "$empty" = yes ] && [ -e "$READY" ] && [ "$tries" -lt "$RESTORE_TRIES" ] &&
               [ "$(up)" -ge "$next_try" ]; then
                last=$(sed -n 's/.*"lastAppId" *: *"\([^"]*\)".*/\1/p' "$LAST_APP" 2>/dev/null)
                # LG's boot goes back to a source only, an app like YouTube it leaves. Without
                # a source our launcher opens instead, once the relay runs, see below.
                input_app "$last" || last=""
                case $last in
                '')
                    tries=$RESTORE_TRIES
                    launcher=yes
                    log "in front: ${app:-no app}, no source to go back to, our launcher opens"
                    ;;
                *)
                    params='{}'
                    if input_app "$last" && [ "$(setting hideInputBanner)" != false ]; then
                        params='{"appViewRole":"appViewGuest"}'
                    fi
                    log "in front: ${app:-no app}, back to $last"
                    helper call luna://com.webos.applicationManager/launch \
                        "{\"id\":\"$last\",\"params\":$params}" >/dev/null
                    tries=$((tries + 1))
                    next_try=$(( $(up) + 8 ))
                    ;;
                esac
            fi
            case $app in ''|com.webos.app.home) settled=0 ;; *) settled=$((settled + 1)) ;; esac
            # Nothing to wait for when our launcher comes instead of a source.
            [ "$launcher" = no ] || settled=3
            limit=$SETTLE_LIMIT
            if [ "$settled" -ge 3 ] || [ "$(up)" -ge "$limit" ]; then
                log "boot settled, in front: ${app:-nothing}"
                # LG's banner for inputs ends with a second start as guest, as after a restart.
                # Also after our way back above: the source can have come by LG's own way.
                if input_app "$app" && [ "$(setting hideInputBanner)" != false ]; then
                    helper call luna://com.webos.applicationManager/launch \
                        "{\"id\":\"$app\",\"params\":{\"appViewRole\":\"appViewGuest\"}}" >/dev/null
                    sleep 1
                fi
                if pgrep -f 'novos-supervisor.p[y] run' >/dev/null; then
                    log "supervisor runs already"
                else
                    # systemd-run can take seconds while the boot goes on; the wait for the
                    # marker below covers that.
                    detach novos-supervisor "exec python3 '$BIN/novos-supervisor.py' run </dev/null >>'$STATE/supervisor.log' 2>&1" &
                    log "supervisor starting"
                fi
                supervisor=yes
                # Our pill names the source, as after a restart.
                waited=0
                while [ ! -e /tmp/novos-banner-active ] && [ "$waited" -lt 20 ]; do sleep 1; waited=$((waited + 1)); done
                if input_app "$app" && [ -e /tmp/novos-banner-active ]; then
                    sleep 1
                    helper call luna://com.webos.service.systemUIManager/launch \
                        "{\"appId\":\"com.webos.app.quickinputpicker\",\"params\":{\"banner\":true,\"appId\":\"$app\"}}" >/dev/null
                elif [ "$launcher" = yes ] && [ -e /tmp/novos-banner-active ]; then
                    case $(helper foreground 2>/dev/null) in
                    ''|com.webos.app.home)
                        helper call luna://com.webos.service.systemUIManager/launch \
                            '{"appId":"com.webos.app.store-streamer"}' >/dev/null
                        log "our launcher opened" ;;
                    esac
                fi
            fi
        fi
        if [ "$supervisor" = yes ] && [ -e /tmp/webosbrew_startup ]; then
            log "watch done"
            return 0
        fi
        sleep 1
    done
    log "watch ends after $WATCH_LIMIT s: supervisor $supervisor, Homebrew startup $([ -e /tmp/webosbrew_startup ] && echo ran || echo missing)"
}

case $MODE in
kick) kick ;;
mount) mount_all ;;
undo) undo ;;
watch) watch ;;
*) echo "usage: novos-early.sh kick | mount | undo | watch" >&2; exit 2 ;;
esac
