#!/bin/sh
# novOS start hook. Installed as /var/lib/webosbrew/init.d/50-novos, run once per boot
# by the Homebrew Channel's startup.sh through run-parts. It returns at once, so it
# never holds up startup.sh and its failsafe.
ONCE=0
ROOT=/var/lib/novos

# Phase 3 of the install plan: the hook removes itself before its only run.
if [ "$ONCE" = 1 ]; then
    rm -f "$0"
    sync
fi
[ ! -e "$ROOT/state/disabled" ] || exit 0
[ -f "$ROOT/current/bin/novos-start.sh" ] || exit 0
mkdir -p "$ROOT/state"
log=$ROOT/state/start.log
[ "$({ wc -c < "$log"; } 2>/dev/null || echo 0)" -lt 262144 ] || { tail -n 400 "$log" > "$log.old"; mv "$log.old" "$log"; }
setsid sh "$ROOT/current/bin/novos-start.sh" boot </dev/null >>"$log" 2>&1 &
exit 0
