#!/bin/sh
# Performance runs of the panel as a /tmp preview, with the probe switched on in the
# uploaded copy only (lib/ui/PerfProbe.qml). A scenario under perf/ names the launch and
# the key steps; the probe writes every opening to /tmp/novos-perf.ini on the TV. Nothing
# is mounted and nothing is written to the TV's settings.
#
# Usage: perf-on-tv.sh <build-name> <out-dir> <scenario>...
#        scenario: a name under perf/ (panel-open) or the path of a file
# Then:  python3 -I perf-report.py <out-dir>
#
# Use a new build name for every run: surface-manager keeps components per URL, and the
# first opening of a build is the cold one. PERF_SED and PERF_MODULE_SED are sed scripts
# for the uploaded copy only (main file and module/*.qml). Scenario files may set, in comment lines,
# "# page: <launch page>", "# opens: <n>" and "# seconds: <open time>".
set -eu

BUILD_NAME=$1
OUT=$2
shift 2
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REMOTE_DIR=/tmp/lg-quicksettings-final/$BUILD_NAME
APP=com.webos.app.quicksettings
MAIN=file://$REMOTE_DIR/QuickSettings.glass.qml
CLOSE='{\"appId\":\"'$APP'\"}'

mkdir -p "$OUT"
# PERF_SED and PERF_MODULE_SED change the uploaded copy further, for comparing variants.
PROBE_ON='s/readonly property bool enabled: false/readonly property bool enabled: true/'
PREVIEW_UPLOAD_ONLY=1 PREVIEW_SED="${PERF_SED:-}" \
PREVIEW_MODULE_SED="$PROBE_ON
${PERF_MODULE_SED:-}" \
    "$HERE/preview-on-tv.sh" "$BUILD_NAME" /dev/null
scp -q "$HERE/perf/perf-open.sh" lg-tv:/tmp/novos-perf-open.sh
ssh lg-tv "rm -f /tmp/novos-perf.ini /tmp/novos-perf-script.txt"
printf 'build=%s date=%s\n' "$BUILD_NAME" "$(date '+%Y-%m-%d %H:%M')" > "$OUT/runs.txt"

for scenario in "$@"; do
    file=$scenario
    [ -f "$file" ] || file=$HERE/perf/$scenario.txt
    name=$(basename "$file" .txt)
    page=$(sed -n 's/^# page: *//p' "$file")
    opens=$(sed -n 's/^# opens: *//p' "$file")
    seconds=$(sed -n 's/^# seconds: *//p' "$file")
    scp -q "$file" lg-tv:/tmp/novos-perf-script.txt
    open=1
    while [ "$open" -le "${opens:-1}" ]; do
        # A timer on the TV closes the window even if this script dies. The old one goes in a
        # call of its own: a shell whose command line names the guard would kill itself.
        ssh lg-tv "pkill -f '[n]ovos-perf-guard'" || true
        ssh lg-tv "nohup sh -c 'sleep $(( ${seconds:-6} + 20 )); luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId \"$CLOSE\"; : novos-perf-guard' >/dev/null 2>&1 &"
        result=$(ssh -tt lg-tv "sh /tmp/novos-perf-open.sh $APP $MAIN '$page' ${seconds:-6}" | tr -d '\r' | sed -n 's/^result //p')
        echo "scenario=$name open=$open page=${page:-none} $result" | tee -a "$OUT/runs.txt"
        open=$((open + 1))
    done
done

ssh lg-tv "pkill -f '[n]ovos-perf-guard'" || true
scp -q lg-tv:/tmp/novos-perf.ini "$OUT/novos-perf.ini"
# /tmp on the TV is RAM: the upload goes once its results are in.
ssh lg-tv "rm -rf $REMOTE_DIR"
echo "$OUT"
