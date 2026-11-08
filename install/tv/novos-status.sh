#!/bin/sh
# Shows the state of the novOS install and of test mounts, without changing anything.
#   novos-status.sh [lg-targets.txt]
set -u

ROOT=/var/lib/novos
HOOK=/var/lib/webosbrew/init.d/50-novos
TARGETS=${1:-$ROOT/current/lg-targets.txt}
count() { pgrep -f "$1" | wc -l | tr -d ' '; }

echo "release        $(readlink "$ROOT/current" 2>/dev/null || echo none) $(sed -n 's/^version=//p' "$ROOT/current/VERSION" 2>/dev/null)"
echo "releases       $(ls "$ROOT/releases" 2>/dev/null | tr '\n' ' ')"
if [ ! -f "$HOOK" ]; then
    echo "autostart      off"
elif grep -q '^ONCE=1' "$HOOK"; then
    echo "autostart      once, next boot only"
else
    echo "autostart      on"
fi
for env in /var/systemd/system/env/surface-manager.env /var/systemd/system/env/rec-info-adapter.env; do
    if [ ! -f "$env" ]; then
        state="off"
    elif grep -q '^# novOS early start' "$env"; then
        state="on"
    else
        state="NOT OURS"
    fi
    printf '%-14s %s\n' "$(basename "$env")" "$state"
done
echo "early start    release $(cat "$ROOT/state/early-release" 2>/dev/null || echo none) cleared, this boot $([ -e /tmp/novos-early-mounted ] && echo mounted early || echo not early)"
echo "disabled       $(cat "$ROOT/state/disabled" 2>/dev/null || echo no)"
echo "failed starts  $(cat "$ROOT/state/boot-failures" 2>/dev/null || echo 0)"
if [ -f "$TARGETS" ]; then
    while read -r name target hash; do
        case $name in ''|'#'*) continue ;; esac
        if grep -Fq " $target " /proc/mounts; then
            state="mounted"
        elif [ "$(sha256sum "$target" | cut -d' ' -f1)" = "$hash" ]; then
            state="LG original"
        else
            state="DIFFERS from the checked original"
        fi
        printf '%-14s %s\n' "$name" "$state"
    done < "$TARGETS"
fi
echo "surface-mgr    $(systemctl is-active surface-manager-daemon.service) pid $(systemctl show -p MainPID --value surface-manager-daemon.service)"
echo "processes      supervisor=$(count 'novos-supervisor.p[y] run') relay=$(count 'banner-relay.p[y]') feed=$(count '[v]t-feed.py') guard=$(count 'novos-guar[d]') test-guard=$(count 'novos-rollback.s[h]')"
echo "marker         $([ -e /tmp/novos-banner-active ] && echo on || echo off)"
echo "free on /var   $(df -h /var | awk 'NR == 2 { print $4 }')"
