#!/bin/sh
# Removes the novOS interface completely and brings back LG's own.
#
#   ssh root@<tv-ip>
#   sh novos-uninstall.sh                 everything goes, this file too
#   sh novos-uninstall.sh --keep-state    keeps /var/lib/novos/state (app order, debug values)
#
# The install puts this file into /home/root. It needs nothing of the install: the list
# of LG files is inside, so it also works with a broken or deleted release.
# Order: start hook, processes, mounts, restart of surface-manager, proof of LG's
# originals, and only then the files. Without that proof nothing is deleted.
set -u

ROOT=/var/lib/novos
HOOK=/var/lib/webosbrew/init.d/50-novos
EARLY_ENVS="/var/systemd/system/env/surface-manager.env /var/systemd/system/env/rec-info-adapter.env"
SELF=/home/root/novos-uninstall.sh
# <file in the release> <LG file> <SHA-256 of LG's original>, filled in by the build.
TARGETS=$(cat <<'LIST'
# @LG_TARGETS@
LIST
)

say() { echo "novos-uninstall: $*"; }
main_pid() { systemctl show -p MainPID --value surface-manager-daemon.service 2>/dev/null; }
targets() { echo "$TARGETS" | grep -v '^#' | grep -v '^$'; }
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
[ -n "$(targets)" ] || { say "no list of LG files inside, use the copy the install made"; exit 1; }

# 1. No more starts. The early start's two files in LG's folder for service environments
#    go only when they are ours; the folders only when the install made them and they are
#    empty. Before the install neither the files nor the folders existed.
rm -f "$HOOK"
: > /tmp/novos-early-off
for env in $EARLY_ENVS; do
    [ -f "$env" ] || continue
    if grep -q '^# novOS early start' "$env"; then
        rm -f "$env"
        say "early start removed: $env"
    else
        say "$env is not ours, it stays"
    fi
done
if [ -f "$ROOT/state/early-env-created" ]; then
    for dir in $(cat "$ROOT/state/early-env-created"); do rmdir "$dir" 2>/dev/null; done
fi
sync
say "start hook removed"

# 2. Processes and marker. Without the marker LG's toasts, dialogs and Home come back.
pkill -f 'novos-early.s[h] watch' 2>/dev/null
rm -f /tmp/novos-early-mounted /tmp/novos-early-starts /tmp/novos-stable
pkill -f 'novos-guar[d]' 2>/dev/null
pkill -f 'novos-supervisor.p[y]' 2>/dev/null
rm -f /tmp/novos-banner-active /tmp/novos-booting
pkill -f 'banner-relay.p[y]' 2>/dev/null
pkill -f 'novos-rollback.s[h]' 2>/dev/null

# What runs now comes back after the restart. luna-send answers only in a terminal,
# so this works when run by hand over ssh, otherwise the TV stays on Home.
foreground() {
    luna-send -n 1 -w 3000 luna://com.webos.applicationManager/getForegroundAppInfo '{}' 2>/dev/null |
        sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1
}
app=$(foreground)

# 3. Mounts.
targets | while read -r name target hash; do
    tries=0
    while grep -Fq " $target " /proc/mounts && [ "$tries" -lt 5 ]; do
        umount "$target" || break
        tries=$((tries + 1))
    done
done

# 4. surface-manager loads LG's files again.
pid=$(main_pid)
release_clients
systemctl restart --no-block surface-manager-daemon.service
waited=0
while { [ "$(main_pid)" = 0 ] || [ "$(main_pid)" = "$pid" ]; } && [ "$waited" -lt 30 ]; do
    sleep 1
    waited=$((waited + 1))
done
return_clients
say "surface-manager restarted"
# LG's Home can still arrive after the call. Done only when the app is in front three times,
# 3 s apart; otherwise it is called again, at most five times.
if [ -n "$app" ] && [ "$app" != com.webos.app.home ]; then
    sleep 4
    tries=0
    good=0
    while [ "$tries" -lt 5 ] && [ "$good" -lt 3 ]; do
        if [ "$(foreground)" = "$app" ]; then
            good=$((good + 1))
        else
            good=0
            tries=$((tries + 1))
            luna-send -n 1 -w 3000 luna://com.webos.applicationManager/launch "{\"id\":\"$app\"}" >/dev/null 2>&1
        fi
        sleep 3
    done
    if [ "$good" -ge 3 ]; then say "back to $app"; else say "could not go back to $app"; fi
fi

# 5. Proof, then the files.
bad=$(targets | while read -r name target hash; do
    if grep -Fq " $target " /proc/mounts; then
        echo "still mounted: $target"
    elif [ "$(sha256sum "$target" | cut -d' ' -f1)" != "$hash" ]; then
        echo "hash differs: $target"
    fi
done)
if [ -n "$bad" ]; then
    echo "$bad"
    say "LG's originals are not proven, $ROOT and this file stay"
    exit 1
fi
say "all $(targets | wc -l | tr -d ' ') LG originals proven"

# The Homebrew Channel's block of LG's updates goes back to how it was before novOS: the
# setup notes in state/block-updates-before whether its flag existed then.
BLOCK=/var/luna/preferences/webosbrew_block_updates
if [ "$(cat "$ROOT/state/block-updates-before" 2>/dev/null)" = absent ] && [ -e "$BLOCK" ]; then
    rm -f "$BLOCK"
    say "LG's system updates allowed again from the next restart on, as before novOS"
fi

if [ "${1:-}" = --keep-state ]; then
    rm -rf "$ROOT/releases" "$ROOT/current"
    say "removed releases, kept $ROOT/state"
else
    rm -rf "$ROOT"
    say "removed $ROOT"
fi
rm -f /tmp/novos-launcher-video.ini /tmp/novos-start.lock
rm -f "$SELF"
sync
say "done"
