#!/usr/bin/env python3
"""Tests of the no-signal part of banner-relay.py: when it opens our screen in place of LG's
"Kein Signal", and when it leaves it. Luna calls, notes and time are replaced.

    python3 apps/novos/install/test_relay.py
"""

import importlib.util
import json
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def load_relay():
    spec = importlib.util.spec_from_file_location("banner_relay", os.path.join(HERE, "..", "banner-relay.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def video(app_id, picture):
    source = {"width": 3840, "height": 2160} if picture else {"width": 0, "height": 0}
    return json.dumps({"video": [{"sink": "MAIN", "appId": app_id, "sourceInput": source,
                                  "frameRate": 60 if picture else 0},
                                 {"sink": "SUB0", "appId": "unknown", "sourceInput": {}, "frameRate": 0}],
                       "returnValue": True, "subscribed": True})


class NoSignalTest(unittest.TestCase):
    def setUp(self):
        m = self.m = load_relay()
        self.now = 1000.0
        self.opened = []
        self.notes = {}
        self.device = {"appId": "com.webos.app.hdmi4", "hdmiPlugIn": False, "hdmiSignalExist": False}
        m.time.time = lambda: self.now
        m.open_window = lambda params: self.opened.append(params)
        m.input_of = lambda app_id: dict(self.device, appId=app_id)
        m.note_open = lambda path, app_id="": self.notes.get(path, "") in ("open", "open:" + app_id)
        self.watch = m.NoSignal()

    def at(self, seconds, front="com.webos.app.hdmi4"):
        self.now = 1000.0 + seconds
        self.watch.tick(front)

    def test_empty_port_opens_at_once(self):
        self.watch.video(video("com.webos.app.hdmi4", False), "com.webos.app.hdmi4")
        self.at(0)
        self.assertEqual(self.opened, [{"noSignal": {"appId": "com.webos.app.hdmi4", "kind": ""}}])

    def test_plugged_device_gets_the_grace(self):
        self.device["hdmiPlugIn"] = True
        self.watch.video(video("com.webos.app.hdmi3", False), "com.webos.app.hdmi3")
        self.at(0, "com.webos.app.hdmi3")
        self.at(3.9, "com.webos.app.hdmi3")
        self.assertEqual(self.opened, [])
        self.at(4.0, "com.webos.app.hdmi3")
        self.assertEqual(len(self.opened), 1)

    def test_picture_lost_while_watching(self):
        self.device["hdmiPlugIn"] = True
        self.watch.video(video("com.webos.app.hdmi1", True), "com.webos.app.hdmi1")
        self.watch.video(video("com.webos.app.hdmi1", False), "com.webos.app.hdmi1")
        self.at(4, "com.webos.app.hdmi1")
        self.assertEqual(self.opened, [{"noSignal": {"appId": "com.webos.app.hdmi1", "kind": "lost"}}])

    def test_picture_back_ends_the_watch(self):
        self.device["hdmiPlugIn"] = True
        self.watch.video(video("com.webos.app.hdmi3", False), "com.webos.app.hdmi3")
        self.watch.video(video("com.webos.app.hdmi3", True), "com.webos.app.hdmi3")
        self.at(10, "com.webos.app.hdmi3")
        self.assertEqual(self.opened, [])

    def test_state_told_before_the_source_came_to_the_front(self):
        self.watch.video(video("com.webos.app.hdmi4", False), "")
        self.at(0, "")
        self.assertEqual(self.opened, [])
        self.watch.front_changed("com.webos.app.hdmi4")
        self.at(0.5)
        self.assertEqual(len(self.opened), 1)

    def test_not_over_an_app_or_another_source(self):
        self.watch.video(video("com.webos.app.hdmi4", False), "youtube.leanback.v4")
        self.at(5, "youtube.leanback.v4")
        self.assertEqual(self.opened, [])

    def test_standing_screen_or_panel_is_left_alone(self):
        self.watch.video(video("com.webos.app.hdmi4", False), "com.webos.app.hdmi4")
        self.notes[self.m.NO_SIGNAL_STATE] = "open:com.webos.app.hdmi4"
        self.at(0)
        self.notes[self.m.NO_SIGNAL_STATE] = ""
        self.notes[self.m.PANEL_STATE] = "open"
        self.at(5)
        self.assertEqual(self.opened, [])
        # The panel closed, our screen is gone: it comes back at the next look.
        self.notes[self.m.PANEL_STATE] = ""
        self.at(10)
        self.assertEqual(len(self.opened), 1)

    def test_signal_without_picture_waits(self):
        self.device.update(hdmiPlugIn=True, hdmiSignalExist=True)
        self.watch.video(video("com.webos.app.hdmi3", False), "com.webos.app.hdmi3")
        self.at(4, "com.webos.app.hdmi3")
        self.assertEqual(self.opened, [])


class NotesTest(unittest.TestCase):
    def test_note_names_the_source(self):
        m = load_relay()
        path = os.path.join(os.environ.get("TMPDIR", "/tmp"), "novos-relay-note-test.ini")
        with open(path, "w") as file:
            file.write("[General]\napp=com.webos.app.hdmi4\nopen=true\n")
        try:
            self.assertTrue(m.note_open(path))
            self.assertTrue(m.note_open(path, "com.webos.app.hdmi4"))
            self.assertFalse(m.note_open(path, "com.webos.app.hdmi3"))
        finally:
            os.remove(path)
        self.assertFalse(m.note_open(path))

    def test_main_picture(self):
        m = load_relay()
        self.assertEqual(m.main_picture(video("com.webos.app.hdmi2", True)), ("com.webos.app.hdmi2", True))
        self.assertEqual(m.main_picture(video("com.webos.app.hdmi2", False)), ("com.webos.app.hdmi2", False))
        self.assertIsNone(m.main_picture("not json"))


if __name__ == "__main__":
    unittest.main()
