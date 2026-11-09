#!/bin/sh
# Runs novos-setupd on the TV from /tmp, for development before the setup app installs it:
# copies the service with lib/release to /tmp/novos-setupd and calls it there as root.
#
#   setupd-on-tv.sh status
#   setupd-on-tv.sh check beta
#   setupd-on-tv.sh install beta        changes the installed novOS: ask first
#
# /tmp is RAM: nothing of the copy survives a restart.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RELEASE=$HERE/../../lib/release
REMOTE=/tmp/novos-setupd
ssh lg-tv "rm -rf $REMOTE && mkdir -p $REMOTE"
scp -q "$HERE/tv/novos-setupd.py" "$RELEASE/release.py" "$RELEASE/ed25519.py" "$RELEASE/trusted-keys.json" "lg-tv:$REMOTE/"
quoted=""
for arg in "$@"; do quoted="$quoted '$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")'"; done
ssh lg-tv "python3 $REMOTE/novos-setupd.py$quoted"
