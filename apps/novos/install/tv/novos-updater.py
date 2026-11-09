#!/usr/bin/env python3
"""Starts the updater behind novOS' settings: the newest signed setup release, fresh from GitHub.

    novos-updater.py serve      answers the command waiting in /tmp/novos-update/command.ini

The settings write their commands (check, channel, update) into /tmp/novos-update/command.ini;
the supervisor starts this file when a command waits there and no updater runs. It reads
setup/<channel>.json from GitHub Pages, checks the manifest's signature against the trusted
keys of this novOS release and the archive against the manifest, keeps the setup's TV part
under /var/lib/novos/updater/<version> and hands over to its novos-setupd.py serve. A fixed
updater therefore reaches every TV with a new setup release, without a new novOS release;
nothing that is not signed by a trusted key ever runs.

Without internet the last checked updater runs, so that a rollback still works; without
any, state.json says why. Runs on Python 3.6 and later, with the standard library only.
"""

import contextlib
import fcntl
import json
import os
import shutil
import sys
import time
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "release"))
import release  # noqa: E402

SANDBOX = os.environ.get("NOVOS_SETUPD_SANDBOX", "")
ROOT = SANDBOX + "/var/lib/novos"
STATE = ROOT + "/state"
UPDATER = ROOT + "/updater"
FOLDER = os.environ.get("NOVOS_UPDATE_DIR") or SANDBOX + "/tmp/novos-update"
LOCK = SANDBOX + "/tmp/novos-updater.lock"
IDLE = 300


def log(line):
    with contextlib.suppress(OSError):
        os.makedirs(STATE, exist_ok=True)
        with open(STATE + "/updater.log", "a") as handle:
            handle.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), line))


def read_ini(path):
    values = {}
    with contextlib.suppress(OSError):
        with open(path) as handle:
            for line in handle:
                if "=" in line:
                    key, value = line.split("=", 1)
                    values[key.strip()] = value.strip().strip('"')
    return values


def channel():
    with contextlib.suppress(OSError):
        with open(STATE + "/channel") as handle:
            name = handle.read().strip()
            if name in ("stable", "beta"):
                return name
    return "stable"


def error_kind(error):
    if isinstance(error, urllib.error.HTTPError):
        return "missing" if error.code == 404 else "offline"
    if isinstance(error, urllib.error.URLError):
        return "missing" if isinstance(error.reason, FileNotFoundError) else "offline"
    if isinstance(error, (ConnectionError, TimeoutError)):
        return "offline"
    return "failed"


def fetch(name):
    """Downloads and checks the setup release of channel name; returns its folder."""
    work = os.path.join(UPDATER, ".download")
    shutil.rmtree(work, ignore_errors=True)
    try:
        try:
            manifest = release.fetch(name, "setup", work)
        except urllib.error.URLError as error:
            # Until the setup has a stable release, stable TVs take the newest beta.
            if name != "stable" or error_kind(error) != "missing":
                raise
            shutil.rmtree(work, ignore_errors=True)
            manifest = release.fetch("beta", "setup", work)
        version = manifest["version"]
        target = os.path.join(UPDATER, version)
        if not os.path.isfile(os.path.join(target, "tv", "novos-setupd.py")):
            shutil.rmtree(target, ignore_errors=True)
            release.extract(os.path.join(work, manifest["archive"]["name"]), version, target)
        before = os.path.basename(os.path.realpath(os.path.join(UPDATER, "current")))
        link = os.path.join(UPDATER, "current.new")
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(version, link)
        os.rename(link, os.path.join(UPDATER, "current"))
        # The updater before stays; everything older goes.
        for entry in os.listdir(UPDATER):
            path = os.path.join(UPDATER, entry)
            if entry not in (version, before, ".download") and os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path, ignore_errors=True)
        log("setup %s from %s checked" % (version, name))
        return target
    finally:
        shutil.rmtree(work, ignore_errors=True)


def cached():
    folder = os.path.realpath(os.path.join(UPDATER, "current"))
    return folder if os.path.isfile(os.path.join(folder, "tv", "novos-setupd.py")) else None


def answer_error(command, message, kind):
    """No updater could start: the settings get the answer in its place."""
    state = {"serving": False, "pid": os.getpid(), "id": command.get("serial") or command.get("id") or "",
             "command": command.get("command", ""), "phase": "error", "busy": False, "stage": "", "percent": 0,
             "steps": [], "result": None, "error": message, "errorKind": kind, "channel": channel(),
             "updated": time.time()}
    os.makedirs(FOLDER, exist_ok=True)
    temporary = os.path.join(FOLDER, "state.json.new")
    with open(temporary, "w") as handle:
        json.dump(state, handle)
    os.rename(temporary, os.path.join(FOLDER, "state.json"))


def serve():
    os.makedirs(FOLDER, exist_ok=True)
    with open(LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return 0        # another start is on its way
        command = read_ini(os.path.join(FOLDER, "command.ini"))
        os.makedirs(UPDATER, exist_ok=True)
        try:
            folder = fetch(channel())
        except (release.ReleaseError, OSError, ValueError, KeyError) as error:
            folder = cached()
            log("no new updater (%s), %s" % (error, "the last one runs" if folder else "none to run"))
            if not folder:
                answer_error(command, "the updater could not be loaded: %s" % error, error_kind(error))
                return 1
    # This lock ends with the exec; serve --pending holds its own for as long as it runs.
    args = [sys.executable, os.path.join(folder, "tv", "novos-setupd.py"), "serve", "--dir", FOLDER,
            "--in-novos", "--pending", "--idle", str(IDLE)]
    if os.environ.get("NOVOS_UPDATER_DRY"):
        print(" ".join(args))
        return 0
    os.execv(sys.executable, args)
    return 0


def main(argv):
    if argv[1:] == ["serve"]:
        return serve()
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
