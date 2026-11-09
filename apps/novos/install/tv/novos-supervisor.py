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
  closed, and "novOS X ist installiert" once after the restart into the new release.
- ends when the overlays are no longer mounted, for example after a test rollback.
"""

import json
import os
import select
import signal
import subprocess
import sys
import time

ROOT = "/var/lib/novos"
STATE = ROOT + "/state"
PANEL = ROOT + "/current"
MARKER = "/tmp/novos-banner-active"
BOOTING = "/tmp/novos-booting"
LAUNCHER_OPEN = "/tmp/novos-launcher-open.ini"
VIDEO_BEAT = "/tmp/novos-launcher-video.ini"
TARGETS = PANEL + "/lg-targets.txt"
FAILURES = STATE + "/boot-failures"
DISABLED = STATE + "/disabled"
STABLE = "/tmp/novos-stable"
EARLY_RELEASE = STATE + "/early-release"
UPDATE = "/tmp/novos-update"
UPDATE_CHECKED = STATE + "/update-checked"
UPDATE_ANNOUNCED = STATE + "/update-announced"     # the version "ist da" was shown for
UPDATE_SHOWN = UPDATE + "/shown.json"               # progress and installed, per command
SYSTEM_UI_LAUNCH = "luna://com.webos.service.systemUIManager/launch"

STABLE_SECONDS = 120
CRASH_WINDOW = 300
CRASH_LIMIT = 3
RELAY_HEALTHY = 60
RELAY_RETRIES = 3
RELAY_DELAY = 2
BEAT_TIMEOUT = 5
UPDATER_RETRY = 15
NOTICE_DELAY = 8          # seconds of a running surface-manager before a notice
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


class Updater:
    """Starts the updater for a command of the settings; it fetches itself from GitHub."""

    def __init__(self):
        self.process = None
        self.started = 0.0
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
        if command == "update" and state.get("busy") and state.get("phase") == "running":
            settings_open = read_ini(UPDATE + "/ui.ini").get("settingsOpen") == "true"
            if shown.get("progress") != serial and not settings_open:
                self.show({"novosProgress": True})
                shown["progress"] = serial
        elif command == "update" and state.get("phase") == "done" and result.get("installed"):
            if shown.get("installed") != serial and \
                    result["installed"] == os.path.basename(os.path.realpath(PANEL)):
                self.show({"notice": True, "novos": "installed", "version": result["installed"]})
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
    pid = surface_manager()
    since = time.time()
    restarts = []
    counted = False
    last_note = time.time()
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
                # Windows die with surface-manager: the launcher's note would be stale.
                remove(LAUNCHER_OPEN)
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
                updater.announce(bool(pid) and time.time() - since >= NOTICE_DELAY and relay.alive())
            except OSError as error:
                log("updater: %s" % error)
            time.sleep(1)
    finally:
        relay.stop()


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
