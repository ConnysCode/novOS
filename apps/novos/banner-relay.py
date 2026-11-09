#!/usr/bin/env python3
"""Opens the pills that replace LG's banner and its picture attribute toasts, and our
smart home hub in place of LG's Home Hub.

LG's input app may not start a system window: its bus role only reaches public
methods. This process runs as root beside it and watches the foreground app and the
toasts instead. It ends as soon as the marker file is gone, or at the deadline. A test
mount gives it the length of the mount; the install gives 0, no deadline, and its
supervisor decides how long it runs. Nothing starts it after a reboot except the
installed start hook.

Usage: banner-relay.py <seconds, 0 for no deadline> <marker-file>
"""

import json
import os
import re
import select
import signal
import subprocess
import sys
import time

WATCH = "luna://com.webos.applicationManager/getForegroundAppInfo"
TOASTS = "luna://com.webos.notification/getToastNotification"
ALERTS = "luna://com.webos.notification/getAlertNotification"
ATTRIBUTE_SOURCES = ("com.webos.service.pqcontroller", "com.webos.service.extinputs.hdmi")
LAUNCH = "luna://com.webos.service.systemUIManager/launch"
START = "luna://com.webos.applicationManager/launch"
SOURCE = re.compile(r"^com\.webos\.app\.(hdmi[1-4]|livetv|mediadiscovery|miracast)$")
APP_ID = re.compile(r'"appId"\s*:\s*"([^"]*)"')
SETTINGS = "/tmp/novos-debug.ini"
# The system closes overlay windows while the new source takes over.
SETTLE_SECONDS = 0.4
HOME = "com.webos.app.home"
LAUNCHER = "com.webos.app.store-streamer"
# LG's Home Hub. The source key's long press opens our hub directly (appLaunch.js);
# every other way, by voice, from a notification, LG's app list or another app, ends up
# here.
LG_HUB = "com.webos.app.homeconnect"
CLOSE = "luna://com.webos.applicationManager/closeByAppId"
# How long the relay waits for the app below LG's Home Hub to come back.
HUB_WAIT_SECONDS = 2
LAUNCHER_STATE = "/tmp/novos-launcher-open.ini"
# The launcher writes its state about 0.3 s after it shows.
LAUNCHER_CHECK_SECONDS = 2
LAUNCHER_RETRIES = 2


def banner_hidden():
    try:
        with open(SETTINGS) as file:
            return "hideInputBanner=false" not in file.read()
    except OSError:
        return True


def hide_banner(app_id):
    """LG's banner comes about a second after the switch. Any way of switching ends up here,
    so this also covers Home and devices that take over by themselves."""
    if not app_id.startswith("com.webos.app.hdmi") or not banner_hidden():
        return
    payload = {"id": app_id, "params": {"appViewRole": "appViewGuest"}}
    subprocess.run(["luna-send", "-n", "1", "-w", "3000", START, json.dumps(payload)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def show_pill(app_id):
    time.sleep(SETTLE_SECONDS)
    payload = {"appId": "com.webos.app.quickinputpicker", "params": {"banner": True, "appId": app_id}}
    subprocess.run(["luna-send", "-n", "1", "-w", "3000", LAUNCH, json.dumps(payload)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def show_launcher():
    """LG's Home starts on its own too, after an app ends for example. The launcher covers it."""
    open_window_of(LAUNCHER, {})


def close_lg_hub():
    subprocess.run(["luna-send", "-n", "1", "-w", "3000", CLOSE, json.dumps({"id": LG_HUB})],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def return_to(app_id):
    """Brings back the app that ran before LG's Home Hub, which goes to the background.
    Closing LG's Home Hub in front would end on LG's Home instead (tested on 10.3.2-33).
    A source comes back without LG's banner, as in hide_banner."""
    params = {"appViewRole": "appViewGuest"} if app_id.startswith("com.webos.app.hdmi") and banner_hidden() else {}
    subprocess.run(["luna-send", "-n", "1", "-w", "3000", START, json.dumps({"id": app_id, "params": params})],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_for_launcher():
    deadline = time.time() + LAUNCHER_CHECK_SECONDS
    while not launcher_open() and time.time() < deadline:
        time.sleep(0.1)


def open_hub(below):
    """Our hub in place of LG's. Over LG's Home it opens over the launcher, so that back
    leads there and not to the hidden Home; over a source or an app it opens alone. A hub
    asked for before the launcher's window stands gets lost, hence the wait."""
    if below == HOME and not launcher_open():
        show_launcher()
        wait_for_launcher()
    open_window_of(LAUNCHER, {"page": "hub"})


def launcher_open():
    try:
        with open(LAUNCHER_STATE) as file:
            return "open=true" in file.read()
    except OSError:
        return False


def show_attribute(label):
    payload = {"appId": "com.webos.app.quickinputpicker", "params": {"attributes": True, "label": label}}
    subprocess.run(["luna-send", "-n", "1", "-w", "3000", LAUNCH, json.dumps(payload)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_window_of(app_id, params):
    payload = {"appId": app_id, "params": params}
    subprocess.run(["luna-send", "-n", "1", "-w", "3000", LAUNCH, json.dumps(payload)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_window(params):
    open_window_of("com.webos.app.quickinputpicker", params)


def show_notice(toast):
    open_window({"notice": True, "title": toast.get("title") or "", "message": toast.get("message") or "",
                 "action": toast.get("action") or None})


def replaced_alert(alert):
    """The same rule as toast-filter.inc, which keeps these dialogs from LG's view."""
    if alert.get("type") in ("progress", "spinner", "warning"):
        return False
    if alert.get("checkButton") or alert.get("thumbnailPath"):
        return False
    return len(alert.get("buttons") or []) <= 3


def handle_alert(line):
    try:
        event = json.loads(line)
    except ValueError:
        return
    action = event.get("alertAction")
    alert = event.get("alertInfo") or {}
    if action == "closeAll":
        open_window({"alertClose": "all"})
    elif action == "close":
        open_window({"alertClose": alert.get("timestamp") or ""})
    elif action == "open" and replaced_alert(alert):
        open_window({"alert": alert, "timestamp": event.get("timestamp") or ""})


def handle_toast(line):
    """Shows the toast LG would show, in its own words. New texts need no entry here."""
    try:
        toast = json.loads(line)
    except ValueError:
        return
    message = toast.get("message") or ""
    if not message:
        return
    if toast.get("type") == "light" and toast.get("sourceId") in ATTRIBUTE_SOURCES:
        show_attribute(message)
    else:
        show_notice(toast)


def watch(url):
    terminal, client = os.openpty()
    process = subprocess.Popen(["luna-send", "-i", url, '{"subscribe":true}'],
                               stdin=subprocess.DEVNULL, stdout=client, stderr=client)
    os.close(client)
    return terminal, process


def read_lines(terminal, pending):
    text = pending + os.read(terminal, 4096).decode("utf-8", "replace")
    lines = text.split("\n")
    return lines[:-1], lines[-1]


def stop(_signal, _frame):
    raise SystemExit(0)


def main():
    # pkill sends SIGTERM. Without this the finally below never runs and the three
    # luna-send subscriptions live on as orphans.
    signal.signal(signal.SIGTERM, stop)
    seconds = int(sys.argv[1])
    deadline = time.time() + seconds if seconds > 0 else float("inf")
    marker = sys.argv[2]
    # luna-send only writes its answers to a terminal.
    foreground, foreground_process = watch(WATCH)
    toasts, toast_process = watch(TOASTS)
    alerts, alert_process = watch(ALERTS)
    previous = ""
    pending = ""
    pending_toast = ""
    pending_alert = ""
    # A launch can get lost while the app before still goes, after its exit dialog for
    # example. LG's Home stays hidden, the screen would stay black: ask again.
    launcher_due = 0
    launcher_tries = 0
    # While LG's Home Hub goes: "returning" while the app before it comes back, "closing"
    # while LG's Home Hub closes in front. Our hub opens over the app that is then in front.
    # The compositor keeps LG's Home Hub out of sight (fullscreen-home.inc, splash-hide.inc).
    hub_state = ""
    hub_due = 0
    try:
        while time.time() < deadline and os.path.exists(marker):
            ready, _, _ = select.select([foreground, toasts, alerts], [], [], 0.5)
            if hub_state and time.time() >= hub_due:
                if hub_state == "returning":
                    # The app before did not come back: LG's Home Hub closes in front.
                    close_lg_hub()
                    hub_state = "closing"
                    hub_due = time.time() + HUB_WAIT_SECONDS
                else:
                    hub_state = ""
                    open_hub(previous)
            if launcher_due and time.time() >= launcher_due:
                launcher_due = 0
                if previous == HOME and not launcher_open() and launcher_tries > 0:
                    launcher_tries -= 1
                    show_launcher()
                    launcher_due = time.time() + LAUNCHER_CHECK_SECONDS
            if alerts in ready:
                lines, pending_alert = read_lines(alerts, pending_alert)
                for line in lines:
                    handle_alert(line)
            if toasts in ready:
                lines, pending_toast = read_lines(toasts, pending_toast)
                for line in lines:
                    handle_toast(line)
            if foreground not in ready:
                continue
            lines, pending = read_lines(foreground, pending)
            for line in lines:
                found = APP_ID.search(line)
                if not found or not found.group(1) or found.group(1) == previous:
                    continue
                current = found.group(1)
                if current == LG_HUB:
                    if previous and previous != HOME:
                        return_to(previous)
                        hub_state = "returning"
                    else:
                        close_lg_hub()
                        hub_state = "closing"
                    hub_due = time.time() + HUB_WAIT_SECONDS
                elif hub_state:
                    # The app below LG's Home Hub is back: no pill, no launcher of its own.
                    if hub_state == "returning":
                        close_lg_hub()
                    hub_state = ""
                    open_hub(current)
                    if current == HOME:
                        launcher_due = time.time() + LAUNCHER_CHECK_SECONDS
                        launcher_tries = LAUNCHER_RETRIES
                elif previous and SOURCE.match(current):
                    hide_banner(current)
                    show_pill(current)
                elif current == HOME:
                    show_launcher()
                    launcher_due = time.time() + LAUNCHER_CHECK_SECONDS
                    launcher_tries = LAUNCHER_RETRIES
                previous = current
    finally:
        foreground_process.terminate()
        toast_process.terminate()
        alert_process.terminate()


if __name__ == "__main__":
    main()
