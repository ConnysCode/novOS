#!/usr/bin/env python3
"""Supervisor of the installed novOS interface, and a small luna-send helper.

    novos-supervisor.py run                   watches until the mounts are gone
    novos-supervisor.py foreground            prints the foreground app
    novos-supervisor.py call <url> <json>     prints the answer of one luna call

While it runs it
- keeps banner-relay.py alive. The marker file goes as soon as the relay dies, so
  LG's toasts, dialogs and Home come back at once. Three quick deaths in a row and it
  leaves the relay off.
- resets the count of failed starts once surface-manager ran 120 s without a restart.
- undoes the install for this boot after three restarts of surface-manager within
  five minutes: it writes state/disabled and hands over to novos-stop.sh.
- grows the video plane back to full screen when the launcher died while the plane
  was small. The launcher writes a beat every second while it holds the plane small.
- starts bin/novos-updater.py when novOS' settings left a command for it in
  /tmp/novos-update/command.ini and no updater answers, and once a day, after the
  interface ran stable, leaves a check there itself.
- has the source window show novOS' update notices: "novOS X ist da" once per version
  after a daily check, the progress pill while an update runs and the settings are
  closed, "novOS X ist bereit" once a download from the settings is through, and once
  after the restart into the new release "Neu in novOS" (minor or major) or the notice
  "novOS X ist installiert" with its fixes (patch).
- installs between 2 and 5 at night, while the TV is not on, the version planned for
  tonight (state/update-tonight) or, with automatic updates on, what the last check
  offered. A daily check that found no connection is tried again after an hour.
- starts bin/novos-upload.py when the settings left a command in
  /tmp/novos-upload/command.ini: "open" for the page "Vom Handy oder Computer", "delete"
  and "edit" for an own power-off video. The service ends by itself.
- starts bin/novos-login.py the same way for /tmp/novos-login/command.ini: "code" for the
  page "Profil hinzufügen", which signs an LG account in with a code from LG.
- removes the way back of the last update (rollback.json, the kept release and the copy
  of its user data, see novos-setupd.py) once its 14 days are over, and leaves a version
  just rolled back from (state/update-skip) to the night.
- ends when the overlays are no longer mounted, for example after a test rollback.
"""

import json
import os
import select
import shutil
import signal
import subprocess
import re
import sys
import time

ROOT = "/var/lib/novos"
STATE = ROOT + "/state"
PANEL = ROOT + "/current"
MARKER = "/tmp/novos-banner-active"
BOOTING = "/tmp/novos-booting"
LAUNCHER_OPEN = "/tmp/novos-launcher-open.ini"
# The screen without a picture and the quick panel note the same way (banner-relay.py reads them).
WINDOW_NOTES = ("/tmp/novos-nosignal-open.ini", "/tmp/novos-panel-open.ini")
VIDEO_BEAT = "/tmp/novos-launcher-video.ini"
TARGETS = PANEL + "/lg-targets.txt"
FAILURES = STATE + "/boot-failures"
DISABLED = STATE + "/disabled"
STABLE = "/tmp/novos-stable"
EARLY_RELEASE = STATE + "/early-release"
UPDATE = "/tmp/novos-update"
UPLOAD = "/tmp/novos-upload"
LOGIN = "/tmp/novos-login"
UPDATE_CHECKED = STATE + "/update-checked"
UPDATE_ANNOUNCED = STATE + "/update-announced"     # the version "ist da" was shown for
UPDATE_SHOWN = UPDATE + "/shown.json"               # progress, ready and installed, per command
UPDATE_TONIGHT = STATE + "/update-tonight"          # the version to install at night
AUTO_UPDATE = STATE + "/auto-update"                # "on": install offered updates at night
LAST_CHECK = STATE + "/last-check.json"
# The updater's commands that end with another release running: each gets "ist installiert".
# restore also installs a newer version from the list of versions (novOS 0.9.1-beta.3).
INSTALLING = ("update", "restore", "rollback")
UPDATE_SKIP = STATE + "/update-skip"                # the version a rollback left: not at night
ROLLBACK = ROOT + "/rollback.json"
RELEASES = ROOT + "/releases"
SYSTEM_UI_LAUNCH = "luna://com.webos.service.systemUIManager/launch"

STABLE_SECONDS = 120
EXPIRY_EVERY = 3600
CRASH_WINDOW = 300
CRASH_LIMIT = 3
RELAY_HEALTHY = 60
RELAY_RETRIES = 3
RELAY_DELAY = 2
BEAT_TIMEOUT = 5
UPDATER_RETRY = 15
NOTICE_DELAY = 8          # seconds of a running surface-manager before a notice
RETRY_OFFLINE = 3600      # a daily check without connection is tried again after this
NIGHT_HOURS = (2, 5)      # local time, from 2:00 to 4:59
CHECK_EVERY = 24 * 3600


def log(text):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), text, flush=True)


def luna(url, payload, timeout=6.0):
    """luna-send only writes its answer to a terminal, so it gets one."""
    master, slave = os.openpty()
    process = subprocess.Popen(["luna-send", "-n", "1", "-w", str(int(timeout * 1000)), url,
                                json.dumps(payload)],
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
    if start < 0:
        return {}
    try:
        return json.JSONDecoder().raw_decode(text[start:])[0]
    except ValueError:
        return {}


def foreground():
    return luna("luna://com.webos.applicationManager/getForegroundAppInfo", {}).get("appId") or ""


def targets():
    result = []
    with open(TARGETS) as file:
        for line in file:
            parts = line.split()
            if len(parts) == 3 and not parts[0].startswith("#"):
                result.append(parts[1])
    return result


def mounted(files):
    with open("/proc/mounts") as file:
        points = {line.split()[1] for line in file if len(line.split()) > 1}
    return [path for path in files if path in points]


def surface_manager():
    """The service's main process. A second process of the same name can linger for a
    while, so the name alone is not enough."""
    try:
        output = subprocess.run(["systemctl", "show", "-p", "MainPID", "--value",
                                 "surface-manager-daemon.service"],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=5).stdout
        return int(output.strip() or 0)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 0


def read_ini(path):
    values = {}
    try:
        with open(path) as file:
            for line in file:
                if "=" in line:
                    key, value = line.split("=", 1)
                    values[key.strip()] = value.strip().strip('"')
    except OSError:
        pass
    return values


def write_text(path, text):
    with open(path, "w") as file:
        file.write(text)
        file.flush()
        os.fsync(file.fileno())


class Relay:
    def __init__(self):
        self.process = None
        self.started = 0.0
        self.quick_deaths = 0
        self.given_up = False
        self.retry_at = 0.0

    def start(self):
        write_text(MARKER, "on\n")
        self.process = subprocess.Popen(["python3", PANEL + "/banner-relay.py", "0", MARKER],
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, start_new_session=True)
        self.started = time.time()
        # From now on the marker decides what of LG stays hidden.
        remove(BOOTING)
        log("relay started, pid %d" % self.process.pid)

    def alive(self):
        return self.process is not None and self.process.poll() is None

    def check(self):
        if self.given_up:
            return
        if self.process is not None and not self.alive():
            # LG's views first, then try again.
            remove(MARKER)
            code = self.process.returncode
            self.process = None
            quick = time.time() - self.started < RELAY_HEALTHY
            self.quick_deaths = self.quick_deaths + 1 if quick else 1
            log("relay ended with %s, marker removed (%d quick in a row)" % (code, self.quick_deaths))
            if self.quick_deaths >= RELAY_RETRIES:
                self.given_up = True
                log("relay left off, LG's toasts, dialogs and Home stay")
                return
            self.retry_at = time.time() + RELAY_DELAY
        if self.process is None and time.time() >= self.retry_at:
            self.start()

    def stop(self):
        remove(MARKER)
        if self.alive():
            self.process.terminate()


# ---- After an update: "Neu in novOS" or the notice ---------------------------------------

VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$")


def version_key(text):
    """As release.py orders versions; None for a local build."""
    match = VERSION.match(text or "")
    if not match:
        return None
    key = [int(part) for part in match.group(1, 2, 3)] + [0 if match.group(4) else 1]
    for part in (match.group(4) or "").split(".") if match.group(4) else []:
        key.append((0, int(part)) if part.isdigit() else (1, part))
    return key


def after_update(state, version):
    """A minor or major update shows "Neu in novOS" (WhatsNew in the source window), a patch
    only the notice with the number of fixes (K3-Neu-5). Minor or major: the version
    numbers say so, or a release since the one before names its level so (a beta)."""
    previous = ""
    for step in state.get("steps") or []:
        found = re.search(r"\(before: ([^)]+)\)", step.get("message", ""))
        if found:
            previous = found.group(1)
    try:
        with open(PANEL + "/module/release-notes.json") as file:
            notes = json.load(file)
    except (OSError, ValueError):
        notes = {}
    current, before = version_key(version), version_key(previous)
    if current and before and current < before:
        # Back to an earlier version (restore, rollback): nothing is new.
        return {"notice": True, "novos": "installed", "version": version, "back": True}
    since = [name for name in notes if version_key(name) and version_key(name) <= current and
             (version_key(name) > before if before else name == version)] if current else []
    bigger = bool(before and current and current[:2] > before[:2])
    bigger = bigger or any(notes[name].get("level") in ("minor", "major") for name in since)
    if bigger and any(item.get("kind", "feature") == "feature" for name in since for item in notes[name].get("items", [])):
        return {"novosWhatsNew": True, "version": version, "previous": previous if before else "",
                "installed": int(state.get("updated") or time.time())}
    fixes = sum(1 for name in since for item in notes[name].get("items", []) if item.get("kind") == "fix")
    return {"notice": True, "novos": "installed", "version": version, "fixes": fixes}


class Updater:
    """Starts the updater for a command of the settings; it fetches itself from GitHub."""

    def __init__(self):
        self.process = None
        self.started = 0.0
        self.night = ""           # the date of the night install asked for
        self.retried = ""         # the failed daily check already moved to an hour later
        os.makedirs(UPDATE, exist_ok=True)

    def answering(self):
        """An updater runs: ours, or one an earlier supervisor started before a restart."""
        if self.process is not None and self.process.poll() is None:
            return True
        try:
            with open(UPDATE + "/state.json") as file:
                state = json.load(file)
            if state.get("serving"):
                os.kill(int(state.get("pid") or 0), 0)
                return True
        except (OSError, ValueError, TypeError):
            pass
        return False

    def check(self, stable):
        if stable and self.check_due():
            write_text(UPDATE + "/command.ini", "[General]\ncommand=check\nserial=auto-%d\n" % time.time())
            write_text(UPDATE_CHECKED, time.strftime("%Y-%m-%d %H:%M:%S") + "\n")
            log("daily update check asked for")
        waiting = read_ini(UPDATE + "/command.ini")
        serial = waiting.get("serial") or waiting.get("id") or ""
        if not serial or time.time() - self.started < UPDATER_RETRY:
            return
        try:
            with open(UPDATE + "/state.json") as file:
                answered = json.load(file).get("id", "")
        except (OSError, ValueError):
            answered = ""
        if serial == answered or self.answering():
            return
        self.started = time.time()
        self.process = subprocess.Popen(["python3", PANEL + "/bin/novos-updater.py", "serve"],
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, start_new_session=True)
        log("updater started for %s %s, pid %d" % (waiting.get("command", "?"), serial, self.process.pid))

    def announce(self, settled):
        """The notices of the updater's state, each once; settled: the interface stands."""
        if not settled:
            return
        try:
            with open(UPDATE + "/state.json") as file:
                state = json.load(file)
        except (OSError, ValueError):
            return
        try:
            with open(UPDATE_SHOWN) as file:
                shown = json.load(file)
        except (OSError, ValueError):
            shown = {}
        before = dict(shown)
        serial = state.get("id", "")
        command = state.get("command", "")
        result = state.get("result") or {}
        found = result.get("check") or {}
        if command in INSTALLING and state.get("busy") and state.get("phase") == "running":
            settings_open = read_ini(UPDATE + "/ui.ini").get("settingsOpen") == "true"
            if shown.get("progress") != serial and not settings_open:
                self.show({"novosProgress": True})
                shown["progress"] = serial
        elif command == "download" and state.get("phase") == "done" and result.get("downloaded"):
            settings_open = read_ini(UPDATE + "/ui.ini").get("settingsOpen") == "true"
            if shown.get("ready") != serial and not settings_open:
                self.show({"notice": True, "novos": "ready", "version": result["downloaded"],
                           "restarts": found.get("restarts") or 1})
                shown["ready"] = serial
        elif command == "check" and serial.startswith("auto-") and state.get("phase") == "error" and \
                state.get("errorKind") == "offline" and self.retried != serial:
            # No connection at the daily check: again in an hour instead of tomorrow.
            self.retried = serial
            stamp = time.time() - CHECK_EVERY + RETRY_OFFLINE
            os.utime(UPDATE_CHECKED, (stamp, stamp))
            log("daily check without connection, again in an hour")
        elif command in INSTALLING and state.get("phase") == "done" and result.get("installed"):
            if shown.get("installed") != serial and \
                    result["installed"] == os.path.basename(os.path.realpath(PANEL)):
                self.show(after_update(state, result["installed"]))
                shown["installed"] = serial
        elif command == "check" and serial.startswith("auto-") and state.get("phase") == "done" and \
                found.get("newer") and not found.get("problems"):
            try:
                with open(UPDATE_ANNOUNCED) as file:
                    announced = file.read().strip()
            except OSError:
                announced = ""
            if announced != found.get("available"):
                self.show({"notice": True, "novos": "available", "version": found.get("available", ""),
                           "size": found.get("size", 0), "channel": found.get("channel") or ""})
                write_text(UPDATE_ANNOUNCED, found.get("available", "") + "\n")
        if shown != before:
            write_text(UPDATE_SHOWN, json.dumps(shown))

    def at_night(self, settled):
        """Between 2 and 5 at night, with the TV not on: the planned or offered update."""
        now = time.localtime()
        today = time.strftime("%Y-%m-%d", now)
        if not settled or not NIGHT_HOURS[0] <= now.tm_hour < NIGHT_HOURS[1] or self.night == today:
            return
        try:
            with open(UPDATE_TONIGHT) as file:
                planned = file.read().strip()
        except OSError:
            planned = ""
        offered = ""
        try:
            with open(AUTO_UPDATE) as file:
                automatic = file.read().strip() == "on"
            with open(LAST_CHECK) as file:
                found = json.load(file)
            if automatic and found.get("newer") and not found.get("problems"):
                offered = found.get("available", "")
        except (OSError, ValueError):
            pass
        try:
            with open(UPDATE_SKIP) as file:
                if offered == file.read().strip():
                    offered = ""
        except OSError:
            pass
        current = os.path.basename(os.path.realpath(PANEL))
        if not (planned or offered) or (planned or offered) == current:
            return
        power = luna("luna://com.webos.service.tvpower/power/getPowerState", {}).get("state", "")
        if power in ("", "Active"):
            return            # someone watches, or the question failed: not now
        self.night = today
        write_text(UPDATE + "/command.ini", "[General]\ncommand=update\nserial=night-%d\n" % time.time())
        log("night update of %s asked for, TV %s" % (planned or offered, power))

    @staticmethod
    def show(params):
        answer = luna(SYSTEM_UI_LAUNCH, {"appId": "com.webos.app.quickinputpicker", "params": params})
        log("update notice %s: %s" % (json.dumps(params), json.dumps(answer)))

    @staticmethod
    def check_due():
        try:
            return time.time() - os.path.getmtime(UPDATE_CHECKED) >= CHECK_EVERY
        except OSError:
            return True


class ServiceStarter:
    """Starts a service of bin/ for a command the settings left in <folder>/command.ini and
    lets it answer in <folder>/state.json: novos-upload.py for the page "Vom Handy oder
    Computer" ("open") and an own power-off video ("delete", "edit"), novos-login.py for
    "Profil hinzufügen" ("code"). Windows run inside surface-manager and cannot start it."""

    def __init__(self, folder, script, commands, name):
        self.folder = folder
        self.script = script
        self.commands = commands
        self.name = name
        self.process = None
        self.started = 0.0
        os.makedirs(folder, exist_ok=True)

    def check(self):
        waiting = read_ini(self.folder + "/command.ini")
        if waiting.get("command") not in self.commands or not waiting.get("serial"):
            return
        if self.process is not None and self.process.poll() is None:
            return
        if time.time() - self.started < UPDATER_RETRY:
            return
        try:
            with open(self.folder + "/state.json") as file:
                state = json.load(file)
            # An answered command of a service that ended needs nothing more.
            if state.get("id") == waiting.get("serial") and not state.get("serving"):
                return
            if state.get("serving"):
                os.kill(int(state.get("pid") or 0), 0)
                return
        except (OSError, ValueError, TypeError):
            pass
        self.started = time.time()
        self.process = subprocess.Popen(["python3", PANEL + "/bin/" + self.script, "serve"],
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, start_new_session=True)
        log("%s service started for %s %s, pid %d" % (self.name, waiting.get("command"), waiting.get("serial"),
                                                        self.process.pid))

    def stop(self):
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()


def expire_rollback(now=None):
    """After its 14 days the way back goes: the kept release, its data and rollback.json."""
    try:
        with open(ROLLBACK) as file:
            info = json.load(file)
        target = info["version"]
        until = float(info["until"])
    except (OSError, ValueError, KeyError, TypeError):
        return False
    if (now or time.time()) < until:
        return False
    if target and "/" not in target and not target.startswith(".") and \
            target != os.path.basename(os.path.realpath(PANEL)):
        shutil.rmtree(os.path.join(RELEASES, target), ignore_errors=True)
    for name in os.listdir(RELEASES) if os.path.isdir(RELEASES) else []:
        shutil.rmtree(os.path.join(RELEASES, name, "backup"), ignore_errors=True)
    remove(ROLLBACK)
    log("way back to novOS %s expired" % target)
    return True


def remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def grow_video():
    """The launcher holds the plane small and died: give the picture back."""
    beat = read_ini(VIDEO_BEAT)
    if beat.get("shrunk") != "true":
        return
    try:
        age = time.time() - float(beat.get("beat") or 0) / 1000
    except ValueError:
        age = BEAT_TIMEOUT + 1
    if age < BEAT_TIMEOUT:
        return
    context = beat.get("context") or ""
    answer = luna("luna://com.webos.service.videooutput/display/setDisplayWindow",
                  {"context": context, "fullScreen": True,
                   "displayOutput": {"x": 0, "y": 0, "width": 1920, "height": 1080}})
    write_text(VIDEO_BEAT, "[General]\nshrunk=false\ncontext=\nbeat=0\n")
    log("launcher beat %.0f s old, video plane %s back to full screen: %s" % (
        age, context or "(no context)", json.dumps(answer)))


def give_up(reason):
    log("undoing the install for this boot: " + reason)
    write_text(DISABLED, time.strftime("%Y-%m-%d %H:%M:%S") + " supervisor: " + reason + "\n")
    remove(MARKER)
    os.execv("/bin/sh", ["sh", PANEL + "/bin/novos-stop.sh"])


def run():
    files = targets()
    relay = Relay()
    updater = Updater()
    uploader = ServiceStarter(UPLOAD, "novos-upload.py", ("open", "delete", "edit"), "upload")
    login = ServiceStarter(LOGIN, "novos-login.py", ("code",), "login")
    pid = surface_manager()
    since = time.time()
    restarts = []
    counted = False
    last_note = time.time()
    last_expiry = 0.0
    log("supervisor started, surface-manager pid %d" % pid)
    try:
        while True:
            if not mounted(files):
                log("overlays no longer mounted, supervisor ends")
                return
            current = surface_manager()
            # 0 means the question failed or took too long, which happens while the TV
            # is busy after a boot. A real restart shows as a new pid.
            if current and current != pid:
                # A gap without any surface-manager in between is the same restart.
                if pid:
                    restarts = [moment for moment in restarts if time.time() - moment < CRASH_WINDOW]
                    restarts.append(time.time())
                    log("surface-manager now pid %d (%d restarts in %d s)" % (
                        current, len(restarts), CRASH_WINDOW))
                    if len(restarts) >= CRASH_LIMIT:
                        relay.stop()
                        give_up("surface-manager restarted %d times within %d s" % (
                            len(restarts), CRASH_WINDOW))
                pid = current
                since = time.time()
                # Windows die with surface-manager: their notes would be stale.
                remove(LAUNCHER_OPEN)
                for note in WINDOW_NOTES:
                    remove(note)
            relay.check()
            if not counted and pid and time.time() - since >= STABLE_SECONDS and relay.alive():
                counted = True
                write_text(FAILURES, "0\n")
                # From the next boot on the early start may mount this release before
                # surface-manager starts: it passed its compile check and ran stable.
                write_text(STABLE, "on\n")
                write_text(EARLY_RELEASE, os.path.basename(os.path.realpath(PANEL)) + "\n")
                log("surface-manager stable for %d s, failed starts reset" % STABLE_SECONDS)
            elif not counted and time.time() - last_note >= 60:
                last_note = time.time()
                log("not reset yet: surface-manager pid %d for %.0f s, relay %s" % (
                    pid, time.time() - since, "alive" if relay.alive() else "not running"))
            grow_video()
            try:
                updater.check(counted)
                settled = bool(pid) and time.time() - since >= NOTICE_DELAY and relay.alive()
                updater.announce(settled)
                updater.at_night(settled and counted)
            except OSError as error:
                log("updater: %s" % error)
            if time.time() - last_expiry >= EXPIRY_EVERY:
                last_expiry = time.time()
                try:
                    expire_rollback()
                except OSError as error:
                    log("way back: %s" % error)
            for starter in (uploader, login):
                try:
                    starter.check()
                except OSError as error:
                    log("%s service: %s" % (starter.name, error))
            time.sleep(1)
    finally:
        relay.stop()
        uploader.stop()
        login.stop()


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "run":
        # novos-stop.sh ends it with SIGTERM: leave through finally, relay and marker go.
        signal.signal(signal.SIGTERM, lambda number, frame: sys.exit(0))
        run()
    elif command == "foreground":
        print(foreground())
    elif command == "call" and len(sys.argv) == 4:
        print(json.dumps(luna(sys.argv[2], json.loads(sys.argv[3]))))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
