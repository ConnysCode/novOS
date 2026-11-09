#!/usr/bin/env python3
"""Tests of the update part of tv/novos-supervisor.py: when it shows which notice and when
it asks for a night install. Paths go to a temporary folder, luna calls are recorded.

    python3 apps/novos/install/test_supervisor.py
"""

import importlib.util
import json
import os
import shutil
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def load_supervisor():
    spec = importlib.util.spec_from_file_location("novos_supervisor", os.path.join(HERE, "tv", "novos-supervisor.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UpdatesTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="novos-supervisor-")
        m = self.m = load_supervisor()
        m.UPDATE = self.folder + "/update"
        m.STATE = self.folder + "/state"
        for name in ("UPDATE_SHOWN", "UPDATE_CHECKED", "UPDATE_ANNOUNCED", "UPDATE_TONIGHT", "AUTO_UPDATE", "LAST_CHECK"):
            setattr(m, name, getattr(m, name).replace("/tmp/novos-update", m.UPDATE)
                    .replace("/var/lib/novos/state", m.STATE))
        os.makedirs(m.STATE)
        os.makedirs(self.folder + "/releases/1.0.0")
        os.makedirs(self.folder + "/releases/1.1.0")
        os.symlink(self.folder + "/releases/1.0.0", self.folder + "/current")
        m.PANEL = self.folder + "/current"
        self.calls = []
        self.power = "Active Standby"

        def luna(url, payload, timeout=6.0):
            self.calls.append((url, payload))
            return {"state": self.power} if url.endswith("getPowerState") else {"returnValue": True}
        m.luna = luna
        m.log = lambda text: None
        self.updater = m.Updater()

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def state(self, **fields):
        with open(self.m.UPDATE + "/state.json", "w") as handle:
            json.dump(fields, handle)

    def settings_open(self, value):
        with open(self.m.UPDATE + "/ui.ini", "w") as handle:
            handle.write("[General]\nsettingsOpen=%s\n" % ("true" if value else "false"))

    def shown(self):
        return [payload["params"] for url, payload in self.calls if url.endswith("/launch")]

    def test_notices_each_once(self):
        offer = {"available": "1.1.0", "newer": True, "problems": [], "size": 18e6, "channel": "beta", "restarts": 1}
        self.state(id="auto-1", command="check", phase="done", busy=False, result={"check": offer})
        self.updater.announce(False)
        self.assertEqual(self.shown(), [])          # the interface does not stand yet
        self.updater.announce(True)
        self.updater.announce(True)
        self.state(id="d1", command="download", phase="done", busy=False, result={"downloaded": "1.1.0"})
        self.settings_open(True)
        self.updater.announce(True)
        self.settings_open(False)
        self.updater.announce(True)
        self.updater.announce(True)
        self.state(id="u1", command="update", phase="running", busy=True, result=None)
        self.updater.announce(True)
        self.state(id="u1", command="update", phase="done", busy=False, result={"installed": "1.0.0"})
        self.updater.announce(True)
        self.updater.announce(True)
        kinds = [params.get("novos") or ("progress" if params.get("novosProgress") else "?") for params in self.shown()]
        self.assertEqual(kinds, ["available", "ready", "progress", "installed"])

    def test_offline_check_again_in_an_hour(self):
        open(self.m.UPDATE_CHECKED, "w").close()
        self.state(id="auto-2", command="check", phase="error", errorKind="offline", busy=False)
        self.updater.announce(True)
        due = os.path.getmtime(self.m.UPDATE_CHECKED) + self.m.CHECK_EVERY - time.time()
        self.assertAlmostEqual(due, self.m.RETRY_OFFLINE, delta=5)

    def night(self, hour):
        real = time.localtime
        self.m.time.localtime = lambda *args: time.struct_time((2026, 11, 10, hour, 30, 0, 1, 314, 0))
        try:
            self.updater.at_night(True)
        finally:
            self.m.time.localtime = real
        try:
            with open(self.m.UPDATE + "/command.ini") as handle:
                return handle.read()
        except OSError:
            return ""

    def test_night_install(self):
        self.assertEqual(self.night(3), "")                       # nothing planned, nothing offered
        with open(self.m.UPDATE_TONIGHT, "w") as handle:
            handle.write("1.1.0\n")
        self.assertEqual(self.night(14), "")                      # not at night
        self.power = "Active"
        self.assertEqual(self.night(3), "")                       # the TV is on
        self.power = "Active Standby"
        self.assertIn("command=update", self.night(3))
        os.remove(self.m.UPDATE + "/command.ini")
        self.assertEqual(self.night(4), "")                       # once a night

    def test_night_install_of_an_offer(self):
        with open(self.m.AUTO_UPDATE, "w") as handle:
            handle.write("on\n")
        with open(self.m.LAST_CHECK, "w") as handle:
            json.dump({"available": "1.1.0", "newer": True, "problems": []}, handle)
        self.assertIn("command=update", self.night(2))


if __name__ == "__main__":
    unittest.main()
