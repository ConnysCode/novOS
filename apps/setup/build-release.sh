#!/bin/sh
# Builds the part of a setup release that runs on the TV: novos-setupd with the release
# tools and the trusted keys. novOS' supervisor fetches it fresh from the setup channel
# for every update (install/tv/novos-updater.py), so a fixed updater reaches TVs without
# a new novOS release.
#
#   apps/setup/build-release.sh <out-dir>
set -eu

OUT=$1
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RELEASE=$(CDPATH= cd -- "$HERE/../../lib/release" && pwd)

mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
mkdir "$OUT/tv"
cp "$HERE/tv/novos-setupd.py" "$RELEASE/release.py" "$RELEASE/ed25519.py" "$RELEASE/trusted-keys.json" "$OUT/tv/"
chmod 755 "$OUT/tv/novos-setupd.py"
echo "version=${SETUP_VERSION:-$(git -C "$HERE" describe --always --dirty 2>/dev/null || echo unknown)}" > "$OUT/VERSION"
