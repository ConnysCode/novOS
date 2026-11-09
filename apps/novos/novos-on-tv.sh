#!/bin/sh
# Installs and controls the novOS interface under /var/lib/novos on the TV.
# See docs/permanent-install-plan.md: every phase needs its own yes.
#
#   novos-on-tv.sh install                  builds and uploads a release, no autostart
#   novos-on-tv.sh install --from <source>  uploads a signed CI release instead: stable,
#                                          beta or a manifest URL; checked on this Mac
#   novos-on-tv.sh start [seconds]          starts it by hand; a guard stops it after
#                                          <seconds>, without restarting surface-manager
#   novos-on-tv.sh stop [--no-restart]      stops it and proves LG's originals
#   novos-on-tv.sh status                   release, autostart, mounts, processes
#   novos-on-tv.sh log                      last lines of the start and supervisor logs
#   novos-on-tv.sh disable | enable         the emergency switch state/disabled
#   novos-on-tv.sh autostart once|on|off    phases 3 and 5: start hook in init.d
#   novos-on-tv.sh early on|off             mount before surface-manager's first start
#   novos-on-tv.sh uninstall [--keep-state] removes hook, mounts and files
#
# On the TV itself, after "ssh $NOVOS_TV": sh novos-uninstall.sh
set -eu
TV=${NOVOS_TV:?"set NOVOS_TV to the SSH target of the TV as root, e.g. root@<tv-ip>"}

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=/var/lib/novos
HOOK=/var/lib/webosbrew/init.d/50-novos
# PATH of surface-manager-daemon.service and rec-info-adapter.service on 10.3.2-33. The
# early start puts its folder in front.
BASE_PATH=/mnt/bsppart/bsp/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Read-only scripts run from the repository, so they work without an install too.
remote_status() {
    scp -q "$HERE/install/lg-targets.txt" "$TV:/tmp/novos-lg-targets.txt"
    ssh "$TV" sh -s /tmp/novos-lg-targets.txt < "$HERE/install/tv/novos-status.sh"
}

install_release() {
    version=$(git -C "$HERE" describe --always --dirty)
    case $version in
    *-dirty)
        [ "${NOVOS_ALLOW_DIRTY:-}" = 1 ] || {
            echo "uncommitted changes: commit first, or NOVOS_ALLOW_DIRTY=1 for a test" >&2
            exit 1
        } ;;
    esac
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    "$HERE/install/build-release.sh" "$STAGE/$version" "$ROOT/current" "$ROOT/state/"
    upload_release "$version" "$STAGE/$version"
}

# A release from GitHub, see lib/release/release.py: channel or manifest, signature checked
# against lib/release/trusted-keys.json and the archive against the manifest before
# anything goes to the TV. The archive holds one folder named after the version.
fetch_release() {
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    version=$(python3 -I "$HERE/../../lib/release/release.py" fetch "$1" --app novos --out "$STAGE/download")
    tar -C "$STAGE" -xJf "$STAGE/download/novos-$version.tar.xz"
    [ -f "$STAGE/$version/VERSION" ] || { echo "the archive has no folder $version" >&2; exit 1; }
    echo "checked: novos $version, signature and archive"
    upload_release "$version" "$STAGE/$version"
}

# Uploads the release folder $2 as releases/$1 and points current to it.
upload_release() {
    version=$1
    folder=$2
    ssh "$TV" sh -s "$version" <<'REMOTE'
set -eu
root=/var/lib/novos
version=$1
if pgrep -f 'novos-supervisor.p[y] run' >/dev/null ||
   grep -Eq ' /usr/lib/qml/(QuickSettings/QuickSettings\.qml|InputPicker/InputPicker\.qml|StoreStreamer/StoreStreamer\.qml|KeyFilters/systemUi\.js|SystemUI/Notification/Services\.qml|WebOSCompositor/views/fullscreen/StarfishFullscreenContainer\.qml|WebOSCompositor/views/StarfishImageSplash\.qml|WebOSCompositor/views/systemUi/StarfishSystemUIManager\.qml|WebOSCompositor/controllers/StarfishViewStateController\.qml|WebOSCompositor/views/StarfishVolumeView\.qml|KeyFilters/appLaunch\.js) ' /proc/mounts ||
   grep -Eq ' /usr/palm/applications/com\.palm\.app\.settings/index(\.multi)?\.html ' /proc/mounts; then
    echo "an overlay is mounted: first novos-on-tv.sh stop or gear-test-on-tv.sh rollback" >&2
    exit 1
fi
[ ! -e "$root/releases/$version" ] || { echo "release $version is there already" >&2; exit 1; }
[ "$(df -k /var | awk 'NR == 2 { print $4 }')" -gt 102400 ] || { echo "less than 100 MB free on /var" >&2; exit 1; }
mkdir -p "$root/releases" "$root/state"
rm -rf "$root/releases/.partial"
REMOTE
    scp -qr "$folder" "$TV:$ROOT/releases/.partial"
    ssh "$TV" sh -s "$version" <<'REMOTE'
set -eu
root=/var/lib/novos
version=$1
new=$root/releases/$version
sh "$root/releases/.partial/bin/make-overlays.sh" "$root/releases/.partial"
mv "$root/releases/.partial" "$new"
[ -f "$root/state/novos.conf" ] || cp "$new/bin/novos.conf" "$root/state/novos.conf"
[ -f "$root/state/debug.ini" ] || printf '[General]\nblur=84\nhideInputBanner=true\n' > "$root/state/debug.ini"
# The app order of earlier test mounts lives in /tmp until the TV restarts.
[ -f "$root/state/launcher.ini" ] || [ ! -f /tmp/novos-launcher.ini ] || cp /tmp/novos-launcher.ini "$root/state/launcher.ini"
previous=$(readlink "$root/current" 2>/dev/null || true)
# The early start mounts only a release that ran stable before. A name used once more,
# a dirty test build after its folder was deleted, must earn that again.
[ "$(cat "$root/state/early-release" 2>/dev/null)" != "$version" ] || rm -f "$root/state/early-release"
ln -sfn "releases/$version" "$root/current"
# Uninstall by hand after "ssh $NOVOS_TV": sh novos-uninstall.sh
cp "$new/bin/novos-uninstall.sh" /home/root/novos-uninstall.sh
chmod 755 /home/root/novos-uninstall.sh
# The new release and the one before stay, for a rollback in one step.
for dir in "$root"/releases/*; do
    name=${dir##*/}
    [ "$name" = "$version" ] || [ "releases/$name" = "$previous" ] || rm -rf "$dir"
done
sync
echo "installed $version ($(du -sh "$new" | cut -f1)), current -> $(readlink "$root/current"), autostart unchanged"
REMOTE
}

case "${1:-}" in
install)
    if [ "${2:-}" = --from ]; then
        [ -n "${3:-}" ] || { echo "usage: novos-on-tv.sh install --from stable|beta|<manifest-url>" >&2; exit 2; }
        fetch_release "$3"
    else
        install_release
    fi
    remote_status
    ;;
start)
    ssh "$TV" "sh $ROOT/current/bin/novos-start.sh manual ${2:-0} 2>&1 | tee -a $ROOT/state/start.log"
    ;;
stop)
    ssh "$TV" "sh $ROOT/current/bin/novos-stop.sh ${2:-} 2>&1 | tee -a $ROOT/state/start.log"
    ;;
status)
    remote_status
    ;;
log)
    ssh "$TV" "tail -n 30 $ROOT/state/start.log; echo; tail -n 30 $ROOT/state/supervisor.log"
    ;;
disable)
    ssh "$TV" "echo \"\$(date '+%Y-%m-%d %H:%M:%S') by hand\" > $ROOT/state/disabled; sync; cat $ROOT/state/disabled"
    ;;
enable)
    ssh "$TV" "rm -f $ROOT/state/disabled $ROOT/state/boot-failures; sync; echo enabled"
    ;;
autostart)
    case "${2:-}" in
    once) once=1 ;;
    on) once=0 ;;
    off)
        ssh "$TV" "rm -f $HOOK; sync; echo autostart off"
        exit 0 ;;
    *) echo "usage: novos-on-tv.sh autostart once|on|off" >&2; exit 2 ;;
    esac
    ssh "$TV" "[ -f $ROOT/current/bin/novos-start.sh ]" || { echo "nothing installed" >&2; exit 1; }
    sed "s/^ONCE=0$/ONCE=$once/" "$HERE/install/tv/init-hook.sh" |
        ssh "$TV" "cat > $HOOK.new && chmod 755 $HOOK.new && mv $HOOK.new $HOOK && sync && grep '^ONCE=' $HOOK"
    ;;
early)
    # LG's optional environment files of two services, see bin/novos-early.sh:
    #   surface-manager.env   PATH with bin/early, the PmLogCtl stand-in that mounts
    #   rec-info-adapter.env  PATH with bin/kick, the luna-send stand-in that restarts
    #                         surface-manager once /var is writable
    # Neither file nor folder existed on 10.3.2-33; a file that is not ours is never
    # touched. Which folders the install made is kept in state/, so that the uninstall
    # removes only those.
    case "${2:-}" in
    on)
        ssh "$TV" sh -s "$BASE_PATH" <<'REMOTE'
set -eu
dir=/var/systemd/system/env
root=/var/lib/novos
[ -x "$root/current/bin/early/PmLogCtl" ] && [ -x "$root/current/bin/kick/luna-send" ] ||
    { echo "the release has no early start, install first" >&2; exit 1; }
for name in surface-manager rec-info-adapter; do
    if [ -f "$dir/$name.env" ] && ! grep -q '^# novOS early start' "$dir/$name.env"; then
        echo "$dir/$name.env exists and is not ours, nothing changed" >&2
        exit 1
    fi
done
created=""
for folder in /var/systemd /var/systemd/system /var/systemd/system/env; do
    [ -d "$folder" ] || { mkdir "$folder"; created="$folder $created"; }
done
[ -z "$created" ] || echo "$created" >> "$root/state/early-env-created"
[ -f "$root/state/early-env-before" ] ||
    echo "surface-manager.env and rec-info-adapter.env absent before the install, $(date '+%Y-%m-%d %H:%M:%S')" \
        > "$root/state/early-env-before"
write() {
    printf '# novOS early start, see /var/lib/novos/current/bin/%s. Removed by novos-uninstall.sh.\nPATH=%s:%s\n' \
        "$2" "$root/current/bin/$2" "$1" > "$dir/$3.env.new"
    mv "$dir/$3.env.new" "$dir/$3.env"
}
write "$1" early surface-manager
write "$1" kick rec-info-adapter
sync
head -n 5 "$dir/surface-manager.env" "$dir/rec-info-adapter.env"
REMOTE
        ;;
    off)
        ssh "$TV" sh <<REMOTE
for f in /var/systemd/system/env/surface-manager.env /var/systemd/system/env/rec-info-adapter.env; do
    if [ -f \$f ] && grep -q '^# novOS early start' \$f; then rm -f \$f; echo "removed \$f"; fi
done
for d in \$(cat $ROOT/state/early-env-created 2>/dev/null); do rmdir \$d 2>/dev/null; done
rm -f $ROOT/state/early-env-created
sync
echo early start off
REMOTE
        ;;
    *) echo "usage: novos-on-tv.sh early on|off" >&2; exit 2 ;;
    esac
    ;;
uninstall)
    # Built from the repository, so it works whatever is left on the TV. A terminal
    # lets it read the foreground app and go back to it afterwards.
    "$HERE/install/build-release.sh" --uninstall-script |
        ssh "$TV" "cat > /tmp/novos-uninstall.sh"
    ssh -tt "$TV" "sh /tmp/novos-uninstall.sh ${2:-}; rm -f /tmp/novos-uninstall.sh"
    ;;
*)
    sed -n '2,18p' "$0" >&2
    exit 2
    ;;
esac
