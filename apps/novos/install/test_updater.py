#!/usr/bin/env python3
"""Tests of tv/novos-updater.py in a sandbox: setup releases built with build-release.sh,
signed with a throwaway key and served from file:// URLs.

    python3 apps/novos/install/test_updater.py
"""

import base64
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(CORE, "lib", "release"))
import ed25519  # noqa: E402
import release  # noqa: E402


def load_updater():
    spec = importlib.util.spec_from_file_location("novos_updater", os.path.join(HERE, "tv", "novos-updater.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UpdaterTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = tempfile.mkdtemp(prefix="novos-updater-")
        self.server = tempfile.mkdtemp(prefix="novos-pages-")
        os.environ["NOVOS_SETUPD_SANDBOX"] = self.sandbox
        os.environ["NOVOS_UPDATER_DRY"] = "1"
        os.makedirs(os.path.join(self.sandbox, "tmp"))
        secret = os.urandom(32)
        public = ed25519.public_key(secret)
        self.keys = os.path.join(self.server, "trusted-keys.json")
        with open(self.keys, "w") as handle:
            json.dump({"keys": {release.key_id(public): base64.b64encode(public).decode()}}, handle)
        os.environ["NOVOS_SIGNING_KEY"] = base64.b64encode(secret).decode()
        self.updater = load_updater()
        # The updater's copy of release.py is the one in lib/release here.
        self.saved = (self.updater.release.TRUSTED_KEYS, self.updater.release.PAGES)
        self.updater.release.TRUSTED_KEYS = self.keys
        self.updater.release.PAGES = "file://" + self.server

    def tearDown(self):
        self.updater.release.TRUSTED_KEYS, self.updater.release.PAGES = self.saved
        for name in ("NOVOS_SETUPD_SANDBOX", "NOVOS_UPDATER_DRY", "NOVOS_SIGNING_KEY"):
            del os.environ[name]
        shutil.rmtree(self.sandbox, ignore_errors=True)
        shutil.rmtree(self.server, ignore_errors=True)

    def publish(self, version, channel, tamper=False, note=None):
        build = os.path.join(self.server, "build", version)
        shutil.rmtree(build, ignore_errors=True)
        subprocess.check_call(["sh", os.path.join(CORE, "apps", "setup", "build-release.sh"), build],
                              env=dict(os.environ, SETUP_VERSION=version))
        if note:
            with open(os.path.join(build, "tv", "note"), "w") as handle:
                handle.write(note + "\n")
        archive = os.path.join(self.server, "setup-%s.tar.xz" % version)
        with tarfile.open(archive, "w:xz") as bundle:
            bundle.add(build, arcname=version)
        manifest = os.path.join(self.server, "setup-%s.manifest.json" % version)
        self.release(["manifest", "--app", "setup", "--version", version, "--tag", "setup-v" + version,
                      "--archive", archive, "--url", "file://" + archive], manifest)
        self.release(["sign", manifest], manifest + ".sig")
        os.makedirs(os.path.join(self.server, "setup"), exist_ok=True)
        self.release(["channel", "--app", "setup", "--version", version, "--manifest-url", "file://" + manifest,
                      "--signature-url", "file://" + manifest + ".sig"],
                     os.path.join(self.server, "setup", channel + ".json"))
        if tamper:
            with open(archive, "ab") as handle:
                handle.write(b"x")

    def release(self, args, output):
        saved = release.TRUSTED_KEYS
        release.TRUSTED_KEYS = self.keys
        try:
            with open(output, "w") as handle, redirect_stdout(handle):
                self.assertEqual(release.main(args), 0)
        finally:
            release.TRUSTED_KEYS = saved

    def serve(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = self.updater.serve()
        return code, out.getvalue().split()

    def current(self):
        return os.path.basename(os.path.realpath(self.sandbox + "/var/lib/novos/updater/current"))

    def state(self):
        with open(self.sandbox + "/tmp/novos-update/state.json") as handle:
            return json.load(handle)

    def test_fetches_checks_and_hands_over(self):
        self.publish("0.1.0-beta.1", "beta")
        code, args = self.serve()
        self.assertEqual(code, 0)
        # Stable has no setup release yet: the beta runs.
        self.assertEqual(self.current(), "0.1.0-beta.1")
        self.assertTrue(args[1].endswith("/updater/0.1.0-beta.1/tv/novos-setupd.py"), args)
        self.assertEqual(args[2:], ["serve", "--dir", self.sandbox + "/tmp/novos-update", "--in-novos",
                                    "--pending", "--idle", "300"])
        self.assertTrue(os.path.isfile(self.sandbox + "/var/lib/novos/updater/0.1.0-beta.1/tv/release.py"))

    def test_newer_updater_replaces_and_keeps_one(self):
        for version in ("0.1.0-beta.1", "0.1.0-beta.2", "0.1.0-beta.3"):
            self.publish(version, "beta")
            self.serve()
        self.assertEqual(self.current(), "0.1.0-beta.3")
        kept = sorted(os.listdir(self.sandbox + "/var/lib/novos/updater"))
        self.assertEqual(kept, ["0.1.0-beta.2", "0.1.0-beta.3", "current"])

    def test_same_version_published_again_is_unpacked_again(self):
        self.publish("0.1.0-beta.1", "beta")
        self.serve()
        folder = self.sandbox + "/var/lib/novos/updater/0.1.0-beta.1"
        with open(folder + "/tv/old-build", "w") as handle:
            handle.write("from the first build\n")
        self.serve()
        # The same archive: the folder stays as it is.
        self.assertTrue(os.path.isfile(folder + "/tv/old-build"))
        # Published again under the same version (a new archive): unpacked anew.
        self.publish("0.1.0-beta.1", "beta", note="second build")
        code, args = self.serve()
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(folder + "/tv/old-build"))
        with open(folder + "/tv/note") as handle:
            self.assertEqual(handle.read(), "second build\n")

    def test_offline_runs_the_last_one(self):
        self.publish("0.1.0-beta.1", "beta")
        self.serve()
        shutil.rmtree(os.path.join(self.server, "setup"))
        code, args = self.serve()
        self.assertEqual(code, 0)
        self.assertIn("/updater/0.1.0-beta.1/tv/novos-setupd.py", args[1])

    def test_tampered_updater_never_runs(self):
        self.publish("0.1.0-beta.1", "beta", tamper=True)
        os.makedirs(self.sandbox + "/tmp/novos-update")
        with open(self.sandbox + "/tmp/novos-update/command.ini", "w") as handle:
            handle.write("[General]\ncommand=check\nserial=7\n")
        code, args = self.serve()
        self.assertEqual(code, 1)
        self.assertEqual(args, [])
        state = self.state()
        self.assertEqual((state["id"], state["phase"], state["errorKind"]), ("7", "error", "failed"))
        self.assertIn("archive", state["error"])
        self.assertFalse(os.path.exists(self.sandbox + "/var/lib/novos/updater/0.1.0-beta.1"))

    def test_no_release_at_all(self):
        code, args = self.serve()
        self.assertEqual(code, 1)
        self.assertEqual(self.state()["errorKind"], "missing")

    def test_channel_of_the_tv(self):
        os.makedirs(self.sandbox + "/var/lib/novos/state")
        with open(self.sandbox + "/var/lib/novos/state/channel", "w") as handle:
            handle.write("stable\n")
        self.publish("0.1.0-beta.1", "beta")
        self.publish("0.1.0", "stable")
        self.serve()
        self.assertEqual(self.current(), "0.1.0")


if __name__ == "__main__":
    unittest.main()
