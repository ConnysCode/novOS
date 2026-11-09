#!/usr/bin/env python3
"""HTTP security and launch behavior without contacting a TV."""

import http.client
import importlib.util
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))
import discover


spec = importlib.util.spec_from_file_location("express_server", Path(__file__).with_name("server.py"))
express = importlib.util.module_from_spec(spec)
spec.loader.exec_module(express)


class ExpressServerTest(unittest.TestCase):
    def setUp(self):
        self.server = express.ExpressServer(0)
        self.server.devices = {"known-tv": "root@192.168.1.10"}
        self.server.devices_until = time.monotonic() + 300
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method, path, headers=None, body=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, data

    def test_page_serves_local_token_and_loopback_binding(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        status, data = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(self.server.csrf_token.encode(), data)

    def test_start_requires_same_origin_and_token(self):
        with patch.object(express, "preflight") as preflight, patch.object(
            express, "start_wizard"
        ) as launch:
            status, _ = self.request("POST", "/api/start?tv=known-tv")
            self.assertEqual(status, 403)
            status, _ = self.request(
                "POST",
                "/api/start?tv=known-tv",
                headers={
                    "Origin": "https://other.example",
                    "X-Novos-CSRF": self.server.csrf_token,
                },
            )
            self.assertEqual(status, 403)
            preflight.assert_not_called()
            launch.assert_not_called()

    def test_authorized_start_checks_tv_before_launch(self):
        origin = "http://127.0.0.1:%d" % self.port
        headers = {"Origin": origin, "X-Novos-CSRF": self.server.csrf_token}
        with patch.object(express, "preflight", return_value={"ready": True}) as preflight, patch.object(
            express, "start_wizard"
        ) as launch:
            status, data = self.request("POST", "/api/start?tv=known-tv", headers=headers)
            self.assertEqual(status, 200)
            self.assertTrue(json.loads(data)["ok"])
            preflight.assert_called_once_with("root@192.168.1.10")
            launch.assert_called_once_with("root@192.168.1.10")

    def test_failed_preflight_never_launches(self):
        headers = {
            "Origin": "http://127.0.0.1:%d" % self.port,
            "X-Novos-CSRF": self.server.csrf_token,
        }
        with patch.object(express, "preflight", side_effect=express.TVUnavailable("TV offline")), patch.object(
            express, "start_wizard"
        ) as launch:
            status, data = self.request("POST", "/api/start?tv=known-tv", headers=headers)
            self.assertEqual(status, 503)
            self.assertEqual(json.loads(data)["error"], "TV offline")
            launch.assert_not_called()

    def test_unknown_tv_cannot_start_wizard(self):
        headers = {
            "Origin": "http://127.0.0.1:%d" % self.port,
            "X-Novos-CSRF": self.server.csrf_token,
        }
        with patch.object(express, "preflight") as preflight, patch.object(express, "start_wizard") as launch:
            status, _ = self.request("POST", "/api/start?tv=unknown", headers=headers)
            self.assertEqual(status, 503)
            preflight.assert_not_called()
            launch.assert_not_called()

    def test_two_discovered_tvs_get_distinct_targets(self):
        found = [
            {"address": "192.168.1.10", "name": "Wohnzimmer", "model": "LG A", "ssh": True},
            {"address": "192.168.1.11", "name": "Schlafzimmer", "model": "LG B", "ssh": False},
        ]
        with patch.object(express, "discover_lg_tvs", return_value=found), patch.object(
            express, "configured_tv", return_value=("mein-tv", "192.168.1.10")
        ):
            status, data = self.request("GET", "/api/tvs")
        self.assertEqual(status, 200)
        devices = json.loads(data)["devices"]
        self.assertEqual(len(devices), 2)
        self.assertNotEqual(devices[0]["id"], devices[1]["id"])
        by_address = {device["address"]: device for device in devices}
        self.assertEqual(self.server.target_for(by_address["192.168.1.10"]["id"]), "mein-tv")
        self.assertEqual(self.server.target_for(by_address["192.168.1.11"]["id"]), "root@192.168.1.11")
        with patch.object(express, "preflight", return_value={"ready": True}) as preflight:
            status, _ = self.request(
                "GET", "/api/status?tv=" + by_address["192.168.1.11"]["id"]
            )
            self.assertEqual(status, 200)
            preflight.assert_called_once_with("root@192.168.1.11")

    def authorized(self):
        return {
            "Origin": "http://127.0.0.1:%d" % self.port,
            "X-Novos-CSRF": self.server.csrf_token,
        }

    def test_manual_address_requires_same_origin_and_token(self):
        with patch.object(express, "ssh_reachable", return_value=True) as probe:
            status, _ = self.request("POST", "/api/device?address=192.168.1.20")
            self.assertEqual(status, 403)
            probe.assert_not_called()
        self.assertEqual(self.server.manual, [])

    def test_manual_address_rejects_invalid_and_public_addresses(self):
        with patch.object(express, "ssh_reachable", return_value=True) as probe:
            for value in ("", "mein-tv", "192.168.1.256", "192.168.001.20", "8.8.8.8", "127.0.0.1"):
                status, data = self.request(
                    "POST", "/api/device?address=" + value, headers=self.authorized()
                )
                self.assertEqual(status, 400, value)
                self.assertIn("error", json.loads(data))
            probe.assert_not_called()
        self.assertEqual(self.server.manual, [])

    def test_manual_address_without_ssh_is_not_listed(self):
        with patch.object(express, "ssh_reachable", return_value=False):
            status, data = self.request(
                "POST", "/api/device?address=192.168.1.20", headers=self.authorized()
            )
        self.assertEqual(status, 404)
        self.assertIn("192.168.1.20", json.loads(data)["error"])
        self.assertEqual(self.server.manual, [])

    def test_manual_address_is_added_and_kept_on_rescan(self):
        with patch.object(express, "ssh_reachable", return_value=True), patch.object(
            express, "configured_tv", return_value=("", "")
        ):
            status, data = self.request(
                "POST", "/api/device?address=192.168.1.20", headers=self.authorized()
            )
            self.assertEqual(status, 200)
            device = json.loads(data)["device"]
            self.assertEqual(device["address"], "192.168.1.20")
            self.assertEqual(self.server.target_for(device["id"]), "root@192.168.1.20")
            self.assertEqual(self.server.target_for("known-tv"), "root@192.168.1.10")
            with patch.object(express, "discover_lg_tvs", return_value=[]):
                status, data = self.request("GET", "/api/tvs")
        devices = json.loads(data)["devices"]
        self.assertEqual([item["address"] for item in devices], ["192.168.1.20"])
        self.assertEqual(self.server.target_for(devices[0]["id"]), "root@192.168.1.20")

    def test_ssdp_filter_only_accepts_lg_response(self):
        good = (
            b"HTTP/1.1 200 OK\r\n"
            b"ST: urn:lge-com:service:webos-second-screen:1\r\n"
            b"LOCATION: http://192.168.1.10:1798/\r\n\r\n"
        )
        self.assertEqual(discover.parse_ssdp(good)["location"], "http://192.168.1.10:1798/")
        self.assertIsNone(discover.parse_ssdp(good.replace(b"webos-second-screen", b"other")))

    def test_black_graphic_capture_does_not_count_as_wizard(self):
        def chunk(kind, value):
            content = kind + value
            return struct.pack(">I", len(value)) + content + struct.pack(">I", zlib.crc32(content))

        def graphic(color):
            width = height = 100
            row = b"\0" + bytes(color) * width
            header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
            return (
                b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", header)
                + chunk(b"IDAT", zlib.compress(row * height))
                + chunk(b"IEND", b"")
            )

        with tempfile.TemporaryDirectory() as folder:
            capture = Path(folder) / "graphic.png"
            capture.write_bytes(graphic((0, 0, 0)))
            self.assertFalse(express.png_has_graphics(capture))
            capture.write_bytes(graphic((20, 40, 60)))
            self.assertTrue(express.png_has_graphics(capture))

    def test_black_first_launch_is_retried_once(self):
        with patch.object(express.subprocess, "Popen") as popen, patch.object(
            express, "wizard_visible", side_effect=[False, True]
        ) as visible, patch.object(express, "relaunch_wizard") as relaunch:
            popen.return_value.communicate.return_value = ("", "")
            popen.return_value.returncode = 0
            express.start_wizard("root@192.168.1.11")
            self.assertEqual(visible.call_count, 2)
            visible.assert_called_with(visible.call_args.args[0], "root@192.168.1.11")
            relaunch.assert_called_once_with(visible.call_args.args[0], "root@192.168.1.11")
            self.assertEqual(
                popen.call_args.kwargs["env"]["NOVOS_TV"], "root@192.168.1.11"
            )

    def test_setup_runner_needs_novos_tv_and_uses_it(self):
        script = express.SETUP_SCRIPT
        with tempfile.TemporaryDirectory() as folder:
            capture = Path(folder) / "target"
            fake_ssh = Path(folder) / "ssh"
            fake_ssh.write_text('#!/bin/sh\nprintf "%s" "$1" > "$NOVOS_TEST_CAPTURE"\n')
            fake_ssh.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": folder + os.pathsep + os.environ["PATH"],
                "NOVOS_TEST_CAPTURE": str(capture),
            }
            environment.pop("NOVOS_TV", None)
            result = subprocess.run(["sh", str(script), "state"], env=environment, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"NOVOS_TV", result.stderr)
            self.assertFalse(capture.exists())
            environment["NOVOS_TV"] = "root@192.168.1.11"
            subprocess.run(["sh", str(script), "state"], env=environment, check=True, capture_output=True)
            self.assertEqual(capture.read_text(), "root@192.168.1.11")

    def test_configured_tv_comes_only_from_novos_tv(self):
        with patch.object(express, "target_address", return_value="192.168.1.10") as resolve:
            with patch.dict(os.environ, {}, clear=False):
                os.environ.pop("NOVOS_TV", None)
                self.assertEqual(express.configured_tv(), ("", ""))
            with patch.dict(os.environ, {"NOVOS_TV": "-oProxyCommand=x"}):
                self.assertEqual(express.configured_tv(), ("", ""))
            resolve.assert_not_called()
            with patch.dict(os.environ, {"NOVOS_TV": "mein-tv"}):
                self.assertEqual(express.configured_tv(), ("mein-tv", "192.168.1.10"))
            resolve.assert_called_once_with("mein-tv")

if __name__ == "__main__":
    unittest.main()
