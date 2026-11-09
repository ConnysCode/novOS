#!/usr/bin/env python3
"""novos-setupd: installs, updates, rolls back and removes novOS on the TV, as root.

Only signed releases are installed (lib/release/release.py): the manifest's signature must
match a key in trusted-keys.json, the archive must match the manifest, and LG's files on
this TV must have the hashes the release was built for. The work on the TV itself is done
by the release's own, tested scripts: make-overlays.sh, novos-start.sh, novos-stop.sh,
init-hook.sh and novos-uninstall.sh.

    novos-setupd.py [--json] status
    novos-setupd.py [--json] check [stable|beta|<manifest-url>]
    novos-setupd.py [--json] fetch [stable|beta|<manifest-url>]
    novos-setupd.py [--json] install [stable|beta|<manifest-url>] [--allow-downgrade] [--start]
    novos-setupd.py [--json] update [--allow-downgrade]
    novos-setupd.py [--json] rollback
    novos-setupd.py channel [stable|beta]
    novos-setupd.py autostart once|on|off
    novos-setupd.py early on|off
    novos-setupd.py uninstall [--keep-state]
    novos-setupd.py settings [--keyboard qwertz|t9] [--auto-update on|off] [--block-updates on|off]
    novos-setupd.py serve --dir <folder> [--window <url>] [--app <id>] [--idle <seconds>]

settings stores the setup's choices: the keyboard novOS starts with, whether novOS updates
itself at night (used from step 6 of the plan on) and whether LG's system updates are
blocked. The block is the Homebrew Channel's own: its flag file makes its startup.sh point
LG's update servers to the TV itself, from the next restart on. Whether the flag was there
before novOS is kept, and the uninstall restores that.

serve is the bridge to the setup's window, which runs inside surface-manager and can neither
start programs nor delete files: the window writes commands into <folder>/command.ini
(Qt.labs.settings), serve runs them and keeps <folder>/state.json up to date. When an
install restarts surface-manager, the window goes with it; serve opens it again (--window,
--app) once novOS runs.

Without a source, check, fetch and install use the channel set with "channel" (stable by
default). install stops a running novOS first and starts it again afterwards; --start
starts it also when it did not run. With --json every message is one JSON object per line:
{"event": "step" | "progress" | "result" | "error", ...}.

NOVOS_SETUPD_SANDBOX=<dir> puts every system path below <dir>, for tests away from a TV.
Runs on Python 3.6 and later, with the standard library only.
"""

import argparse
import contextlib
import select
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
for candidate in (HERE, os.path.join(HERE, "..", "..", "..", "lib", "release")):
    if os.path.exists(os.path.join(candidate, "release.py")):
        sys.path.insert(0, os.path.abspath(candidate))
        break
import release  # noqa: E402

SANDBOX = os.environ.get("NOVOS_SETUPD_SANDBOX", "")


def system(path):
    """A path of the TV, below the sandbox in tests."""
    return SANDBOX + path if SANDBOX else path


ROOT = system("/var/lib/novos")
STATE = ROOT + "/state"
RELEASES = ROOT + "/releases"
DOWNLOADS = ROOT + "/downloads"
CURRENT = ROOT + "/current"
HOOK = system("/var/lib/webosbrew/init.d/50-novos")
ENV_DIR = system("/var/systemd/system/env")
ENV_FILES = ("surface-manager", "rec-info-adapter")
ENV_MARK = "# novOS early start"
HOME_UNINSTALL = system("/home/root/novos-uninstall.sh")
# The Homebrew Channel blocks LG's update servers at boot while this file exists.
BLOCK_FLAG = system("/var/luna/preferences/webosbrew_block_updates")
HOSTS = system("/etc/hosts")
LOCK = system("/tmp/novos-setupd.lock")
PROC = system("/proc")
# PATH of surface-manager-daemon.service and rec-info-adapter.service on 10.3.2-33. The
# early start puts its folder in front.
BASE_PATH = "/mnt/bsppart/bsp/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"
MIN_FREE = 100 * 1024 * 1024
OVERLAY_ROOTS = ("/usr/lib/qml/", "/usr/palm/applications/com.palm.app.settings/")


class SetupError(Exception):
    pass


class Reporter:
    def __init__(self, as_json, listener=None):
        self.as_json = as_json
        self.listener = listener
        self.last_percent = -1

    def emit(self, event, message, **fields):
        if self.listener:
            self.listener(event, message, dict(fields))
        if self.as_json:
            fields.update(event=event, message=message)
            sys.stdout.write(json.dumps(fields, ensure_ascii=False) + "\n")
        elif event != "progress":
            sys.stdout.write(message + "\n")
        sys.stdout.flush()
        if event in ("step", "result", "error"):
            log("%s: %s" % (event, message))

    def step(self, message, key=None, **fields):
        """key names the stage for the setup's screens: manifest, download, verify, stop,
        unpack, overlays, switch, settings, start."""
        if key:
            fields["key"] = key
        self.emit("step", message, **fields)

    def progress(self, what, done, total):
        percent = int(done * 100 / total) if total else 0
        if percent == self.last_percent:
            return
        self.last_percent = percent
        if self.as_json or self.listener:
            self.emit("progress", what, done=done, total=total, percent=percent)
        elif percent % 10 == 0:
            sys.stdout.write("  %s %d %%\n" % (what, percent))
            sys.stdout.flush()

    def result(self, message, **fields):
        self.emit("result", message, **fields)


def log(line):
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(STATE + "/setup.log", "a") as handle:
            handle.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), line))
    except OSError:
        pass


@contextlib.contextmanager
def single_run():
    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    with open(LOCK, "w") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise SetupError("another novos-setupd is running")
        yield


# ---- what is on the TV ---------------------------------------------------------------

def read_version_file(folder):
    values = {}
    try:
        with open(os.path.join(folder, "VERSION")) as handle:
            for line in handle:
                if "=" in line:
                    key, value = line.rstrip("\n").split("=", 1)
                    values[key] = value
    except OSError:
        pass
    return values


def current_release():
    try:
        return os.path.basename(os.readlink(CURRENT))
    except OSError:
        return ""


def installed_releases():
    if not os.path.isdir(RELEASES):
        return []
    return sorted(name for name in os.listdir(RELEASES) if not name.startswith("."))


def overlays_mounted():
    try:
        with open(PROC + "/mounts") as handle:
            for line in handle:
                fields = line.split()
                if len(fields) > 1 and fields[1].startswith(OVERLAY_ROOTS):
                    return True
    except OSError:
        pass
    return False


def supervisor_running():
    if not os.path.isdir(PROC):
        return False
    for pid in os.listdir(PROC):
        if not pid.isdigit():
            continue
        try:
            with open(os.path.join(PROC, pid, "cmdline"), "rb") as handle:
                command = handle.read().replace(b"\0", b" ")
        except OSError:
            continue
        if b"novos-supervisor.py run" in command:
            return True
    return False


def running():
    return overlays_mounted() or supervisor_running()


def free_bytes(path):
    while not os.path.exists(path):
        path = os.path.dirname(path)
    stats = os.statvfs(path)
    return stats.f_bavail * stats.f_frsize


def lg_file_hash(target):
    try:
        return release.sha256_file(system(target))
    except OSError:
        return ""


def lg_mismatches(targets):
    """LG files whose hash differs from what a release was built for."""
    return [t["target"] for t in targets if lg_file_hash(t["target"]) != t["sha256"]]


def read_setting(name, default=""):
    try:
        with open(os.path.join(STATE, name)) as handle:
            return handle.read().strip() or default
    except OSError:
        return default


def write_file(path, text, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + ".new"
    with open(temporary, "w") as handle:
        handle.write(text)
    os.chmod(temporary, mode)
    os.rename(temporary, path)


def sync():
    if hasattr(os, "sync"):
        os.sync()


def version_or_none(name):
    try:
        release.version_key(name)
        return name
    except release.ReleaseError:
        return None


# ---- the release's own scripts ----------------------------------------------------------

def run_script(report, script, *args, **options):
    """Runs a script of the installed release; options["env"] adds variables."""
    path = os.path.join(CURRENT, "bin", script)
    if not os.path.isfile(path):
        raise SetupError("the installed release has no bin/%s" % script)
    key = {"novos-stop.sh": "stop", "novos-start.sh": "start"}.get(script)
    report.step(("%s %s" % (script, " ".join(args))).strip(), key=key)
    with open(STATE + "/start.log", "a") as output:
        env = dict(os.environ, **options.get("env", {}))
        code = subprocess.call(["sh", path] + list(args), stdout=output, stderr=subprocess.STDOUT, env=env)
    if code != 0:
        raise SetupError("%s failed with %d, see %s/start.log" % (script, code, STATE))


# ---- commands ------------------------------------------------------------------------------

def source_of(args):
    return args.source or read_setting("channel", "stable")


def status(report):
    current = current_release()
    previous = [name for name in installed_releases() if name != current]
    info = read_version_file(CURRENT) if current else {}
    manifest = load_installed_manifest(current)
    targets = manifest.get("lg_targets") if manifest else None
    result = {
        "installed": current or None,
        "signed": manifest is not None,
        "previous": previous[-1] if previous else None,
        "channel": read_setting("channel", "stable"),
        "running": running(),
        "autostart": os.path.exists(HOOK),
        "early": any(os.path.exists(os.path.join(ENV_DIR, n + ".env")) for n in ENV_FILES),
        "disabled": os.path.exists(STATE + "/disabled"),
        "built": info.get("built"),
        # While novOS runs, the overlays cover LG's files and their hashes say nothing.
        "lg_files_match": (not lg_mismatches(targets)) if targets and not running() else None,
    }
    lines = ["novOS %s%s" % (current or "not installed", " (signed release)" if result["signed"] else "")]
    for key in ("previous", "channel", "running", "autostart", "early", "disabled", "lg_files_match"):
        lines.append("  %-15s %s" % (key, result[key]))
    report.result("\n".join(lines), status=result)


def load_installed_manifest(name):
    """The checked manifest of an installed release, or None for a local build."""
    if not name:
        return None
    folder = os.path.join(RELEASES, name)
    manifest_path = os.path.join(folder, "manifest.json")
    if not os.path.exists(manifest_path):
        return None
    try:
        return release.verify_files(manifest_path, manifest_path + ".sig", app="novos")
    except (release.ReleaseError, OSError, ValueError):
        return None


def check(report, source):
    """What an install of source would meet; changes nothing on the TV."""
    report.step("reading %s" % source)
    folder = os.path.join(DOWNLOADS, ".check")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    try:
        manifest = fetch_manifest(source, folder)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    current = current_release()
    if manifest["version"] == current:
        report.result("novOS %s is installed, nothing newer in %s" % (current, source),
                      check={"available": current, "installed": current, "newer": False, "problems": [],
                             "size": manifest["archive"]["size"]})
        return False
    problems = preflight(manifest, allow_downgrade=False)
    result = {"available": manifest["version"], "installed": current or None, "size": manifest["archive"]["size"],
              "newer": is_newer(manifest["version"], current), "problems": problems}
    if problems:
        message = "novOS %s cannot be installed: %s" % (manifest["version"], "; ".join(problems))
    else:
        message = "novOS %s can be installed (installed: %s)" % (manifest["version"], current or "nothing")
    report.result(message, check=result)
    return not problems


def is_newer(version, installed):
    if not installed:
        return True
    if version_or_none(installed) is None:
        return True        # a local build: any release counts as newer
    return release.version_key(version) > release.version_key(installed)


def preflight(manifest, allow_downgrade):
    problems = []
    if manifest.get("app") != "novos":
        problems.append("the release is not novOS")
    targets = manifest.get("lg_targets", [])
    if not targets:
        problems.append("the release names no LG files")
    mismatched = lg_mismatches(targets) if not running() else []
    if mismatched:
        problems.append("LG's files differ from what the release was built for (%d of %d), "
                        "for example after a firmware update: %s" % (len(mismatched), len(targets), mismatched[0]))
    if free_bytes(ROOT) < MIN_FREE + 3 * manifest["archive"]["size"]:
        problems.append("not enough free space on /var")
    current = current_release()
    if manifest["version"] == current:
        problems.append("novOS %s is installed already" % current)
    elif not allow_downgrade and not is_newer(manifest["version"], current):
        problems.append("novOS %s is older than the installed %s" % (manifest["version"], current))
    return problems


def fetch_manifest(source, folder):
    """Downloads and checks only the manifest of source."""
    if source in ("stable", "beta"):
        pointer_path = os.path.join(folder, "channel.json")
        release.download("%s/novos/%s.json" % (release.PAGES, source), pointer_path)
        with open(pointer_path) as handle:
            pointer = json.load(handle)
        manifest_url, signature_url = pointer["manifest"], pointer["signature"]
    else:
        manifest_url, signature_url = source, source + ".sig"
    manifest_path = os.path.join(folder, "manifest.json")
    release.download(manifest_url, manifest_path)
    release.download(signature_url, manifest_path + ".sig")
    manifest = release.verify_files(manifest_path, manifest_path + ".sig", app="novos")
    if source in ("stable", "beta") and manifest["version"] != pointer.get("version"):
        raise SetupError("channel %s points to %s, its manifest is %s" % (source, pointer.get("version"), manifest["version"]))
    return manifest


def fetch(report, source):
    """Downloads and checks a release into downloads/<version>; returns its folder and manifest."""
    os.makedirs(DOWNLOADS, exist_ok=True)
    partial = os.path.join(DOWNLOADS, ".partial")
    shutil.rmtree(partial, ignore_errors=True)
    os.makedirs(partial)
    report.step("reading %s" % source, key="manifest")
    manifest = fetch_manifest(source, partial)
    archive = os.path.join(partial, manifest["archive"]["name"])
    report.step("downloading novOS %s (%d MB)" % (manifest["version"], manifest["archive"]["size"] // 1000000),
                key="download", size=manifest["archive"]["size"])
    download_with_progress(report, manifest["archive"]["url"], archive, manifest["archive"]["size"])
    release.check_archive(manifest, archive)
    report.step("signature and archive of novOS %s are right" % manifest["version"], key="verify")
    folder = os.path.join(DOWNLOADS, manifest["version"])
    shutil.rmtree(folder, ignore_errors=True)
    os.rename(partial, folder)
    for name in os.listdir(DOWNLOADS):
        if name not in (manifest["version"], ".check"):
            shutil.rmtree(os.path.join(DOWNLOADS, name), ignore_errors=True)
    return folder, manifest


def download_with_progress(report, url, path, total):
    request = release.urllib.request.Request(url, headers={"User-Agent": "novos-setupd/1"})
    done = 0
    with release.urllib.request.urlopen(request, timeout=60) as response, open(path, "wb") as handle:
        for block in iter(lambda: response.read(1 << 16), b""):
            handle.write(block)
            done += len(block)
            if done > total:
                raise SetupError("the archive is larger than the manifest says")
            report.progress("download", done, total)


def safe_extract(archive, version, target):
    """Unpacks the release folder <version> of archive into target, refusing anything else."""
    try:
        bundle = tarfile.open(archive, "r:xz")
    except (tarfile.CompressionError, ImportError):
        bundle = None
    if bundle is None:
        # Some Pythons lack lzma; tar on the TV unpacks into a scratch folder first.
        scratch = target + ".tar"
        shutil.rmtree(scratch, ignore_errors=True)
        os.makedirs(scratch)
        if subprocess.call(["tar", "-C", scratch, "-xJf", archive]) != 0:
            raise SetupError("tar could not unpack the archive")
        names = os.listdir(scratch)
        if names != [version]:
            raise SetupError("the archive holds %s, expected only %s" % (names, version))
        check_tree(os.path.join(scratch, version))
        os.rename(os.path.join(scratch, version), target)
        shutil.rmtree(scratch, ignore_errors=True)
        return
    with bundle:
        for member in bundle.getmembers():
            name = os.path.normpath(member.name)
            if name != version and not name.startswith(version + os.sep):
                raise SetupError("unexpected entry in the archive: %s" % member.name)
            if member.issym() or member.islnk() or not (member.isdir() or member.isfile()):
                raise SetupError("the archive holds a link or a special file: %s" % member.name)
        scratch = target + ".tar"
        shutil.rmtree(scratch, ignore_errors=True)
        # Newer Pythons check members once more; the checks above are the ones that count.
        if hasattr(tarfile, "data_filter"):
            bundle.extractall(scratch, filter="data")
        else:
            bundle.extractall(scratch)
    os.rename(os.path.join(scratch, version), target)
    shutil.rmtree(scratch, ignore_errors=True)


def check_tree(folder):
    for base, folders, files in os.walk(folder):
        for name in folders + files:
            if os.path.islink(os.path.join(base, name)):
                raise SetupError("the archive holds a link: %s" % os.path.join(base, name))


# Apps that show no picture of their own: closing them is not needed to keep the screen dark.
NO_PICTURE = ("", "com.webos.app.home", "com.webos.app.store-streamer", "com.webos.app.quicksettings")


def close_foreground(report):
    """Closes the app or source in front, so that its picture is gone from the video plane."""
    app = luna("luna://com.webos.applicationManager/getForegroundAppInfo", {}).get("appId", "")
    if app not in NO_PICTURE:
        luna("luna://com.webos.applicationManager/closeByAppId", {"id": app})
        report.step("closed %s, so that nothing but the setup shows" % app, key="start")
    return app


def screen(report, on):
    """Switches the panel off and on again, as novOS' "screen off" does; sound and apps go on."""
    with contextlib.suppress(OSError):
        luna("luna://com.webos.service.tvpower/power/%s" % ("turnOnScreen" if on else "turnOffScreen"), {})
        report.step("panel %s" % ("on" if on else "off"), key="start")


def install(report, source, allow_downgrade=False, start=False, before_start=None, after_start=None,
            stay_dark=False):
    """stay_dark (the setup's window): nothing but the setup shows until it is done. The
    window covers everything up to the restart and shows its black restart page; then the
    panel goes off, the source is closed (closing it brings up LG's Home), surface-manager
    restarts without going back to the source, the window opens again, and only then the
    panel comes back on."""
    with single_run():
        folder, manifest = fetch(report, source)
        version = manifest["version"]
        problems = preflight(manifest, allow_downgrade)
        if problems:
            raise SetupError("; ".join(problems))
        was_running = running()
        if was_running:
            # novos-start.sh restarts surface-manager afterwards anyway: one restart instead of
            # two, and the setup's window stays up until then.
            run_script(report, "novos-stop.sh", "--no-restart")
            if running():
                raise SetupError("novOS still runs after the stop, nothing was changed")
            mismatched = lg_mismatches(manifest["lg_targets"])
            if mismatched:
                raise SetupError("LG's files differ from what the release was built for: %s" % mismatched[0])
        place_release(report, folder, manifest)
        if was_running or start:
            if before_start:
                before_start()
            env = {}
            if stay_dark:
                time.sleep(1.5)             # the window draws its restart page first
                screen(report, False)
                with contextlib.suppress(OSError):
                    close_foreground(report)
                env["NOVOS_RESTORE"] = "0"
            try:
                run_script(report, "novos-start.sh", "manual", env=env)
                if after_start:
                    after_start()
                if stay_dark:
                    time.sleep(3)           # the window stands again before the panel comes on
            finally:
                if stay_dark:
                    screen(report, True)
        report.result("installed novOS %s%s" % (version, ", started" if was_running or start else ""),
                      installed=version, started=was_running or start)


def place_release(report, folder, manifest):
    """Unpacks, prepares and switches to the release, as novos-on-tv.sh install does."""
    version = manifest["version"]
    new = os.path.join(RELEASES, version)
    partial = os.path.join(RELEASES, ".partial")
    if os.path.exists(new):
        raise SetupError("release %s is there already" % version)
    os.makedirs(RELEASES, exist_ok=True)
    os.makedirs(STATE, exist_ok=True)
    shutil.rmtree(partial, ignore_errors=True)
    report.step("unpacking novOS %s" % version, key="unpack")
    safe_extract(os.path.join(folder, manifest["archive"]["name"]), version, partial)
    if read_version_file(partial).get("version") != version:
        raise SetupError("the archive's VERSION is not %s" % version)
    if release.read_targets(os.path.join(partial, "lg-targets.txt")) != manifest["lg_targets"]:
        raise SetupError("the archive's lg-targets.txt differs from the signed manifest")
    report.step("deriving the overlays of LG's files", key="overlays")
    code = subprocess.call(["sh", os.path.join(partial, "bin", "make-overlays.sh"), partial])
    if code != 0:
        shutil.rmtree(partial, ignore_errors=True)
        raise SetupError("make-overlays.sh failed with %d" % code)
    shutil.copy(os.path.join(folder, "manifest.json"), os.path.join(partial, "manifest.json"))
    shutil.copy(os.path.join(folder, "manifest.json.sig"), os.path.join(partial, "manifest.json.sig"))
    os.rename(partial, new)
    if not os.path.exists(STATE + "/novos.conf"):
        shutil.copy(os.path.join(new, "bin", "novos.conf"), STATE + "/novos.conf")
    if not os.path.exists(STATE + "/debug.ini"):
        write_file(STATE + "/debug.ini", "[General]\nblur=84\nhideInputBanner=true\n")
    previous = current_release()
    # The early start mounts only a release that ran stable before.
    if read_setting("early-release") == version:
        os.remove(STATE + "/early-release")
    link = CURRENT + ".new"
    if os.path.lexists(link):
        os.remove(link)
    os.symlink("releases/" + version, link)
    os.rename(link, CURRENT)
    os.makedirs(os.path.dirname(HOME_UNINSTALL), exist_ok=True)
    shutil.copy(os.path.join(new, "bin", "novos-uninstall.sh"), HOME_UNINSTALL)
    os.chmod(HOME_UNINSTALL, 0o755)
    # The new release and the one before stay, for a rollback in one step.
    for name in installed_releases():
        if name not in (version, previous):
            shutil.rmtree(os.path.join(RELEASES, name), ignore_errors=True)
    sync()
    report.step("current -> releases/%s (before: %s)" % (version, previous or "nothing"), key="switch")


def rollback(report):
    with single_run():
        current = current_release()
        others = [name for name in installed_releases() if name != current]
        if not others:
            raise SetupError("there is no release to go back to")
        target = others[-1]
        was_running = running()
        if was_running:
            run_script(report, "novos-stop.sh", "--no-restart")
        link = CURRENT + ".new"
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("releases/" + target, link)
        os.rename(link, CURRENT)
        if read_setting("early-release") != target and os.path.exists(STATE + "/early-release"):
            os.remove(STATE + "/early-release")
        sync()
        if was_running:
            run_script(report, "novos-start.sh", "manual")
        report.result("back to novOS %s (was %s)" % (target, current), installed=target)


def set_channel(report, channel):
    if channel:
        if channel not in ("stable", "beta"):
            raise SetupError("the channel is stable or beta")
        os.makedirs(STATE, exist_ok=True)
        write_file(STATE + "/channel", channel + "\n")
    report.result("channel %s" % read_setting("channel", "stable"), channel=read_setting("channel", "stable"))


def autostart(report, mode):
    if mode == "off":
        if os.path.exists(HOOK):
            os.remove(HOOK)
        sync()
        report.result("autostart off", autostart=False)
        return
    source = os.path.join(CURRENT, "bin", "init-hook.sh")
    if not os.path.isfile(source):
        raise SetupError("nothing installed")
    with open(source) as handle:
        text = handle.read()
    if "\nONCE=0\n" not in text:
        raise SetupError("init-hook.sh has no ONCE=0 line")
    write_file(HOOK, text.replace("\nONCE=0\n", "\nONCE=%d\n" % (1 if mode == "once" else 0)), 0o755)
    sync()
    report.result("autostart %s" % mode, autostart=True, once=mode == "once")


def early(report, mode):
    """LG's optional environment files of two services, see bin/novos-early.sh."""
    created_file = STATE + "/early-env-created"
    if mode == "off":
        for name in ENV_FILES:
            path = os.path.join(ENV_DIR, name + ".env")
            if os.path.isfile(path) and read_first_line(path).startswith(ENV_MARK):
                os.remove(path)
                report.step("removed %s" % path)
        for folder in read_setting("early-env-created").split():
            with contextlib.suppress(OSError):
                os.rmdir(system(folder))
        with contextlib.suppress(OSError):
            os.remove(created_file)
        sync()
        report.result("early start off", early=False)
        return
    for script in ("early/PmLogCtl", "kick/luna-send"):
        if not os.access(os.path.join(CURRENT, "bin", script), os.X_OK):
            raise SetupError("the release has no early start, install first")
    for name in ENV_FILES:
        path = os.path.join(ENV_DIR, name + ".env")
        if os.path.isfile(path) and not read_first_line(path).startswith(ENV_MARK):
            raise SetupError("%s exists and is not ours, nothing changed" % path)
    created = []
    for folder in ("/var/systemd", "/var/systemd/system", "/var/systemd/system/env"):
        if not os.path.isdir(system(folder)):
            os.mkdir(system(folder))
            created.insert(0, folder)
    os.makedirs(STATE, exist_ok=True)
    if created:
        with open(created_file, "a") as handle:
            handle.write(" ".join(created) + "\n")
    if not os.path.exists(STATE + "/early-env-before"):
        write_file(STATE + "/early-env-before", "surface-manager.env and rec-info-adapter.env absent before "
                   "the install, %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
    for name, folder in zip(ENV_FILES, ("early", "kick")):
        write_file(os.path.join(ENV_DIR, name + ".env"),
                   "%s, see /var/lib/novos/current/bin/%s. Removed by novos-uninstall.sh.\nPATH=%s:%s\n"
                   % (ENV_MARK, folder, "/var/lib/novos/current/bin/" + folder, BASE_PATH))
    sync()
    report.result("early start on", early=True)


def read_first_line(path):
    with open(path) as handle:
        return handle.readline()


def uninstall(report, keep_state):
    script = HOME_UNINSTALL if os.path.isfile(HOME_UNINSTALL) else os.path.join(CURRENT, "bin", "novos-uninstall.sh")
    if not os.path.isfile(script):
        raise SetupError("no novos-uninstall.sh found; nothing installed?")
    report.step("running %s" % script)
    code = subprocess.call(["sh", script] + (["--keep-state"] if keep_state else []))
    if code != 0:
        raise SetupError("novos-uninstall.sh failed with %d" % code)
    report.result("novOS removed", installed=None)


# ---- the setup's choices ------------------------------------------------------------------

def read_ini(path):
    """Keys of a Qt.labs.settings file; quotes around values are dropped."""
    values = {}
    try:
        with open(path) as handle:
            for line in handle:
                line = line.strip()
                if "=" in line and not line.startswith(("[", "#", ";")):
                    key, value = line.split("=", 1)
                    values[key.strip()] = value.strip().strip('"')
    except OSError:
        pass
    return values


def set_ini_value(path, key, value):
    """Sets one key below [General] of an ini file and keeps every other line."""
    try:
        with open(path) as handle:
            lines = handle.read().splitlines()
    except OSError:
        lines = ["[General]", "blur=84", "hideInputBanner=true"]
    if "[General]" not in lines:
        lines.insert(0, "[General]")
    for index, line in enumerate(lines):
        if line.split("=", 1)[0].strip() == key:
            lines[index] = "%s=%s" % (key, value)
            break
    else:
        lines.insert(lines.index("[General]") + 1, "%s=%s" % (key, value))
    write_file(path, "\n".join(lines) + "\n")


def updates_blocked_now():
    """Whether LG's update servers point to the TV in this boot."""
    try:
        with open(HOSTS) as handle:
            return "snu.lge.com" in handle.read()
    except OSError:
        return False


def block_updates(report, mode):
    """The Homebrew Channel's block of LG's system updates: its flag, from the next restart on."""
    os.makedirs(STATE, exist_ok=True)
    before = STATE + "/block-updates-before"
    if mode in ("on", "off") and not os.path.exists(before):
        write_file(before, ("present" if os.path.exists(BLOCK_FLAG) else "absent") + "\n")
    if mode == "on" and not os.path.exists(BLOCK_FLAG):
        write_file(BLOCK_FLAG, "")
        report.step("LG's system updates are blocked from the next restart on", key="settings")
    elif mode == "off" and os.path.exists(BLOCK_FLAG):
        os.remove(BLOCK_FLAG)
        report.step("LG's system updates are allowed again from the next restart on", key="settings")
    sync()
    return {"blockUpdates": os.path.exists(BLOCK_FLAG), "blockedNow": updates_blocked_now(),
            "before": read_setting("block-updates-before") or None}


def current_choices():
    return {"keyboard": read_ini(STATE + "/debug.ini").get("keyboardMode", "qwertz"),
            "autoUpdate": read_setting("auto-update", "off") == "on",
            "blockUpdates": os.path.exists(BLOCK_FLAG),
            "blockedNow": updates_blocked_now()}


def apply_choices(report, keyboard=None, auto_update=None, block=None):
    os.makedirs(STATE, exist_ok=True)
    if keyboard:
        if keyboard not in ("qwertz", "t9"):
            raise SetupError("the keyboard is qwertz or t9")
        set_ini_value(STATE + "/debug.ini", "keyboardMode", keyboard)
        report.step("keyboard %s" % keyboard, key="settings")
    if auto_update:
        if auto_update not in ("on", "off"):
            raise SetupError("auto-update is on or off")
        write_file(STATE + "/auto-update", auto_update + "\n")
        report.step("automatic updates %s" % auto_update, key="settings")
    if block:
        if block not in ("on", "off"):
            raise SetupError("block-updates is on or off")
        block_updates(report, block)
    sync()
    return current_choices()


# ---- the bridge to the setup's window ---------------------------------------------------------

def luna(url, payload, timeout=6.0):
    """luna-send only writes its answer to a terminal, so it gets one (as in the supervisor)."""
    master, slave = os.openpty()
    process = subprocess.Popen(["luna-send", "-n", "1", "-w", str(int(timeout * 1000)), url, json.dumps(payload)],
                               stdin=subprocess.DEVNULL, stdout=slave, stderr=slave)
    os.close(slave)
    output = b""
    deadline = time.time() + timeout + 1
    try:
        while time.time() < deadline:
            ready, _, _ = select.select([master], [], [], 0.5)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
            elif process.poll() is not None:
                break
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)
    text = output.decode("utf-8", "replace")
    start = text.find("{")
    try:
        return json.JSONDecoder().raw_decode(text[start:])[0] if start >= 0 else {}
    except ValueError:
        return {}


def tv_facts():
    """What the check screen shows about this TV."""
    facts = {"model": "", "webos": "", "free": free_bytes(ROOT), "root": os.geteuid() == 0}
    try:
        with open(system("/etc/starfish-release")) as handle:
            words = handle.readline().split()
        facts["webos"] = words[2] if len(words) > 2 else ""
    except OSError:
        pass
    try:
        info = luna("luna://com.webos.service.tv.systemproperty/getSystemInfo", {"keys": ["modelName"]})
        facts["model"] = info.get("modelName", "")
    except OSError:
        pass
    return facts


# Share of the whole install each stage stands for, for one progress bar.
STAGES = [("manifest", 2), ("download", 55), ("verify", 3), ("stop", 8), ("unpack", 10),
          ("overlays", 8), ("switch", 2), ("settings", 2), ("start", 10)]


class Bridge:
    def __init__(self, folder, window, app):
        self.folder = folder
        self.window = window
        self.app = app
        self.state_path = os.path.join(folder, "state.json")
        self.command_path = os.path.join(folder, "command.ini")
        # phase is what the window shows ("done" may come before the command ends, so that
        # the reopened window shows its last page at once); busy is whether a command runs.
        self.state = {"serving": True, "pid": os.getpid(), "id": "", "command": "", "phase": "idle", "busy": False,
                      "stage": "", "percent": 0, "steps": [], "result": None, "error": None,
                      "choices": current_choices(), "tv": tv_facts(), "updated": time.time()}
        self.last_written = 0.0

    def write(self, force=True):
        now = time.time()
        if not force and now - self.last_written < 0.25:
            return
        self.state["updated"] = now
        write_file(self.state_path, json.dumps(self.state, ensure_ascii=False))
        self.last_written = now

    def listen(self, event, message, fields):
        if event == "step":
            key = fields.get("key", "")
            self.state["steps"].append({"key": key, "message": message})
            if key:
                self.state["stage"] = key
                self.state["percent"] = self.stage_start(key)
            self.write()
        elif event == "progress":
            span = dict(STAGES).get(self.state["stage"], 0)
            self.state["percent"] = self.stage_start(self.state["stage"]) + span * fields.get("percent", 0) // 100
            self.write(force=False)
        elif event == "result":
            self.state["result"] = {k: v for k, v in fields.items() if k not in ("event", "message")}
            self.state["result"]["message"] = message
            self.write()
        elif event == "error":
            self.state["error"] = message.replace("novos-setupd: ", "")
            self.write()

    @staticmethod
    def stage_start(key):
        total = 0
        for name, span in STAGES:
            if name == key:
                return total
            total += span
        return 0

    def restarting(self):
        self.state["phase"] = "restarting"
        self.write()

    def reopen(self):
        """surface-manager restarted and took the window along: open it again."""
        self.state["phase"] = "done"
        self.state["percent"] = 100
        self.write()
        if self.window:
            time.sleep(2)
            luna("luna://com.webos.service.systemUIManager/launch",
                 {"appId": self.app, "main": self.window, "params": {"setup": "reopened"}})

    def run(self, command):
        name = command.get("command", "")
        self.state.update(id=command_serial(command), command=name, phase="running", stage="", percent=0,
                          steps=[], result=None, error=None, busy=True)
        self.write()
        report = Reporter(False, self.listen)
        source = command.get("source") or read_setting("channel", "stable")
        try:
            if name in ("install", "update"):
                apply_choices(report, command.get("keyboard") or None, command.get("autoUpdate") or None,
                              command.get("blockUpdates") or None)
                if name == "update" and not check(report, source):
                    raise SetupError("nothing newer to install")
                install(report, source, start=True, before_start=self.restarting, after_start=self.reopen,
                        stay_dark=True)
            elif name == "check":
                check(report, source)
            elif name == "settings":
                result = apply_choices(report, command.get("keyboard") or None, command.get("autoUpdate") or None,
                                       command.get("blockUpdates") or None)
                report.result("settings stored", choices=result)
            elif name == "rollback":
                rollback(report)
            elif name == "uninstall":
                self.restarting()
                uninstall(report, command.get("keepState") == "true")
            elif name == "status":
                status(report)
            else:
                raise SetupError("unknown command %r" % name)
            self.state["phase"] = "done"
        except (SetupError, release.ReleaseError, OSError, ValueError, KeyError) as error:
            self.state["phase"] = "error"
            self.state["error"] = str(error)
        self.state["choices"] = current_choices()
        self.state["busy"] = False
        self.write()


def command_serial(command):
    """The window writes "serial" (QML has no property named id); scripts may write "id"."""
    return command.get("serial") or command.get("id") or ""


def serve(folder, window, app, idle):
    os.makedirs(folder, exist_ok=True)
    bridge = Bridge(folder, window, app)
    # A command left over from an earlier run is not run again.
    last_id = command_serial(read_ini(bridge.command_path))
    bridge.state["id"] = last_id
    bridge.write()
    log("serve %s, window %s" % (folder, window or "-"))
    last_activity = time.time()
    while True:
        command = read_ini(bridge.command_path)
        serial = command_serial(command)
        if serial not in ("", last_id):
            last_id = serial
            last_activity = time.time()
            if command.get("command") == "close":
                # "Zum Startbildschirm": the setup ends on novOS' own Home, as the home key opens it.
                if bridge.state["command"] in ("install", "update") and bridge.state["phase"] == "done" and running():
                    with contextlib.suppress(OSError):
                        luna("luna://com.webos.service.systemUIManager/launch", {"appId": "com.webos.app.store-streamer"})
                break
            bridge.run(command)
            last_activity = time.time()
        if idle and time.time() - last_activity > idle:
            break
        time.sleep(0.3)
    bridge.state["serving"] = False
    bridge.write()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--json", action="store_true", help="one JSON object per line")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("status")
    for name in ("check", "fetch"):
        sub.add_parser(name).add_argument("source", nargs="?")
    install_parser = sub.add_parser("install")
    install_parser.add_argument("source", nargs="?")
    install_parser.add_argument("--allow-downgrade", action="store_true")
    install_parser.add_argument("--start", action="store_true")
    update_parser = sub.add_parser("update")
    update_parser.add_argument("--allow-downgrade", action="store_true")
    sub.add_parser("rollback")
    sub.add_parser("channel").add_argument("channel", nargs="?")
    sub.add_parser("autostart").add_argument("mode", choices=("once", "on", "off"))
    sub.add_parser("early").add_argument("mode", choices=("on", "off"))
    sub.add_parser("uninstall").add_argument("--keep-state", action="store_true")
    settings_parser = sub.add_parser("settings")
    settings_parser.add_argument("--keyboard", choices=("qwertz", "t9"))
    settings_parser.add_argument("--auto-update", choices=("on", "off"))
    settings_parser.add_argument("--block-updates", choices=("on", "off"))
    serve_parser = sub.add_parser("serve")
    serve_parser.add_argument("--dir", required=True)
    serve_parser.add_argument("--window", help="file:// URL of the setup's window, opened again after a restart")
    serve_parser.add_argument("--app", default="com.webos.app.quicksettings")
    serve_parser.add_argument("--idle", type=int, default=1800, help="ends after this many seconds without a command")
    args = parser.parse_args(argv)
    report = Reporter(args.json)
    try:
        if args.command == "status":
            status(report)
        elif args.command == "check":
            return 0 if check(report, source_of(args)) else 1
        elif args.command == "fetch":
            with single_run():
                folder, manifest = fetch(report, source_of(args))
            report.result("novOS %s downloaded and checked in %s" % (manifest["version"], folder),
                          version=manifest["version"], folder=folder)
        elif args.command == "install":
            install(report, source_of(args), args.allow_downgrade, args.start)
        elif args.command == "update":
            source = read_setting("channel", "stable")
            if check(report, source):
                install(report, source, args.allow_downgrade)
        elif args.command == "rollback":
            rollback(report)
        elif args.command == "channel":
            set_channel(report, args.channel)
        elif args.command == "autostart":
            autostart(report, args.mode)
        elif args.command == "early":
            early(report, args.mode)
        elif args.command == "uninstall":
            uninstall(report, args.keep_state)
        elif args.command == "settings":
            choices = apply_choices(report, args.keyboard, args.auto_update, args.block_updates)
            report.result("keyboard %s, automatic updates %s, LG updates %s%s" % (
                choices["keyboard"], "on" if choices["autoUpdate"] else "off",
                "blocked" if choices["blockUpdates"] else "allowed",
                "" if choices["blockUpdates"] == choices["blockedNow"] else " (from the next restart on)"),
                choices=choices)
        elif args.command == "serve":
            serve(args.dir, args.window, args.app, args.idle)
        else:
            parser.print_help()
            return 2
    except (SetupError, release.ReleaseError, OSError, ValueError, KeyError) as error:
        report.emit("error", "novos-setupd: %s" % error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
