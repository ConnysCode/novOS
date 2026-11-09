#!/usr/bin/env python3
"""Tests of novos-setupd.py in a sandbox: a made-up TV below a temporary folder, releases
with stub scripts, signed with a throwaway key and served from file:// URLs.

    python3 apps/setup/tv/test_setupd.py
"""

import base64
import importlib.util
import io
import json
import os
import shutil
import stat
import sys
import tarfile
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "lib", "release"))
import ed25519  # noqa: E402
import release  # noqa: E402

TARGETS = [("QuickSettings.qml", "/usr/lib/qml/QuickSettings/QuickSettings.qml"),
           ("systemUi.js", "/usr/lib/qml/KeyFilters/systemUi.js"),
           ("settings-index.html", "/usr/palm/applications/com.palm.app.settings/index.html")]

# Stubs of the release's scripts: they only note their call. start and stop also play the
# mounts, so that setupd sees novOS run and stop.
STUBS = {
    "make-overlays.sh": 'echo "make-overlays $1" >> "$NOVOS_SETUPD_SANDBOX/calls"\n'
                        '[ ! -e "$NOVOS_SETUPD_SANDBOX/fail-overlays" ] || exit 3\n',
    # fail-start: this one start fails as a release that does not compile, once.
    "novos-start.sh": 'echo "start $* restore=${NOVOS_RESTORE:-1}" >> "$NOVOS_SETUPD_SANDBOX/calls"\n'
                      'if [ -e "$NOVOS_SETUPD_SANDBOX/fail-start" ]; then rm "$NOVOS_SETUPD_SANDBOX/fail-start"; '
                      'echo "does not compile" > "$NOVOS_SETUPD_SANDBOX/var/lib/novos/state/disabled"; exit 1; fi\n'
                      'echo "/var/x /usr/lib/qml/QuickSettings/QuickSettings.qml none bind 0 0" > "$NOVOS_SETUPD_SANDBOX/proc/mounts"\n',
    "novos-stop.sh": 'echo "stop $*" >> "$NOVOS_SETUPD_SANDBOX/calls"\n: > "$NOVOS_SETUPD_SANDBOX/proc/mounts"\n',
    "novos-uninstall.sh": 'echo "uninstall $*" >> "$NOVOS_SETUPD_SANDBOX/calls"\n',
    "init-hook.sh": "#!/bin/sh\n# hook\nONCE=0\nROOT=/var/lib/novos\n",
    "novos.conf": "returnToSource=1\n",
    "early/PmLogCtl": "#!/bin/sh\n",
    "kick/luna-send": "#!/bin/sh\n",
}


def load_setupd():
    spec = importlib.util.spec_from_file_location("novos_setupd_%d" % id(object()), os.path.join(HERE, "novos-setupd.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Quiet(io.StringIO):
    pass


class SetupdTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = tempfile.mkdtemp()
        self.server = tempfile.mkdtemp()
        os.environ["NOVOS_SETUPD_SANDBOX"] = self.sandbox
        os.makedirs(os.path.join(self.sandbox, "proc"))
        open(os.path.join(self.sandbox, "proc", "mounts"), "w").close()
        self.lg = {}
        for name, target in TARGETS:
            path = self.sandbox + target
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as handle:
                handle.write("LG original of %s\n" % name)
            self.lg[name] = release.sha256_file(path)
        secret = os.urandom(32)
        public = ed25519.public_key(secret)
        keys = os.path.join(self.server, "trusted-keys.json")
        with open(keys, "w") as handle:
            json.dump({"keys": {release.key_id(public): base64.b64encode(public).decode()}}, handle)
        self.saved = (release.TRUSTED_KEYS, release.PAGES)
        release.TRUSTED_KEYS = keys
        release.PAGES = "file://" + self.server
        os.environ["NOVOS_SIGNING_KEY"] = base64.b64encode(secret).decode()
        self.setupd = load_setupd()

    def tearDown(self):
        release.TRUSTED_KEYS, release.PAGES = self.saved
        del os.environ["NOVOS_SIGNING_KEY"]
        del os.environ["NOVOS_SETUPD_SANDBOX"]
        shutil.rmtree(self.sandbox, ignore_errors=True)
        shutil.rmtree(self.server, ignore_errors=True)

    # ---- helpers ------------------------------------------------------------------------

    def publish(self, version, targets=None, extra=None, channel=None, manifest_targets=None):
        """Builds, signs and serves a release; returns its manifest URL."""
        folder = os.path.join(self.server, "build", version)
        os.makedirs(os.path.join(folder, "bin", "early"))
        os.makedirs(os.path.join(folder, "bin", "kick"))
        with open(os.path.join(folder, "VERSION"), "w") as handle:
            handle.write("version=%s\nbuilt=now\n" % version)
        lines = targets or ["%s %s %s" % (name, target, self.lg[name]) for name, target in TARGETS]
        with open(os.path.join(folder, "lg-targets.txt"), "w") as handle:
            handle.write("# targets\n" + "\n".join(lines) + "\n")
        for name, text in STUBS.items():
            path = os.path.join(folder, "bin", name)
            with open(path, "w") as handle:
                handle.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        archive = os.path.join(self.server, "novos-%s.tar.xz" % version)
        with tarfile.open(archive, "w:xz") as bundle:
            bundle.add(folder, arcname=version)
            if extra:
                extra(bundle)
        manifest = os.path.join(self.server, "novos-%s.manifest.json" % version)
        self.call_release(["manifest", "--app", "novos", "--version", version, "--tag", "novos-v" + version,
                           "--archive", archive, "--url", "file://" + archive,
                           "--targets", manifest_targets or os.path.join(folder, "lg-targets.txt")], manifest)
        self.call_release(["sign", manifest], manifest + ".sig")
        if channel:
            os.makedirs(os.path.join(self.server, "novos"), exist_ok=True)
            self.call_release(["channel", "--app", "novos", "--version", version,
                               "--manifest-url", "file://" + manifest, "--signature-url", "file://" + manifest + ".sig"],
                              os.path.join(self.server, "novos", channel + ".json"))
        return "file://" + manifest

    def call_release(self, args, output):
        saved = sys.stdout
        with open(output, "w") as handle:
            sys.stdout = handle
            try:
                self.assertEqual(release.main(args), 0)
            finally:
                sys.stdout = saved

    def run_setupd(self, *args):
        saved = sys.stdout
        sys.stdout = Quiet()
        try:
            code = self.setupd.main(["--json"] + list(args))
            lines = [json.loads(line) for line in sys.stdout.getvalue().splitlines() if line.strip()]
        finally:
            sys.stdout = saved
        return code, lines

    def calls(self):
        try:
            with open(os.path.join(self.sandbox, "calls")) as handle:
                return [line.strip() for line in handle]
        except OSError:
            return []

    def path(self, tv_path):
        return self.sandbox + tv_path

    def current(self):
        return os.path.basename(os.readlink(self.path("/var/lib/novos/current")))

    def error_of(self, lines):
        return [line["message"] for line in lines if line["event"] == "error"]

    # ---- tests --------------------------------------------------------------------------

    def test_status_without_install(self):
        code, lines = self.run_setupd("status")
        self.assertEqual(code, 0)
        self.assertIsNone(lines[-1]["status"]["installed"])

    def test_install_and_status(self):
        url = self.publish("1.0.0")
        code, lines = self.run_setupd("install", url)
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.0.0")
        folder = self.path("/var/lib/novos/releases/1.0.0")
        for name in ("manifest.json", "manifest.json.sig", "VERSION", "bin/novos-start.sh"):
            self.assertTrue(os.path.exists(os.path.join(folder, name)), name)
        self.assertTrue(os.path.exists(self.path("/home/root/novos-uninstall.sh")))
        self.assertTrue(os.path.exists(self.path("/var/lib/novos/state/debug.ini")))
        self.assertEqual(self.calls(), ["make-overlays %s" % self.path("/var/lib/novos/releases/.partial")])
        code, lines = self.run_setupd("status")
        status = lines[-1]["status"]
        self.assertEqual((status["installed"], status["signed"], status["running"], status["lg_files_match"]),
                         ("1.0.0", True, False, True))

    def test_same_version_refused(self):
        url = self.publish("1.0.0")
        self.run_setupd("install", url)
        code, lines = self.run_setupd("install", url)
        self.assertEqual(code, 1)
        self.assertIn("installed already", self.error_of(lines)[0])

    def test_update_keeps_previous_and_prunes(self):
        for version in ("1.0.0", "1.1.0", "1.2.0"):
            code, lines = self.run_setupd("install", self.publish(version))
            self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.2.0")
        self.assertEqual(sorted(os.listdir(self.path("/var/lib/novos/releases"))), ["1.1.0", "1.2.0"])

    def test_downgrade_needs_permission(self):
        self.run_setupd("install", self.publish("1.1.0"))
        old = self.publish("1.0.0")
        code, lines = self.run_setupd("install", old)
        self.assertEqual(code, 1)
        self.assertIn("older", self.error_of(lines)[0])
        code, lines = self.run_setupd("install", old, "--allow-downgrade")
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.0.0")

    def test_running_novos_is_stopped_and_started_again(self):
        self.run_setupd("install", self.publish("1.0.0"), "--start")
        self.assertEqual(self.calls()[-1], "start manual restore=1")
        code, lines = self.run_setupd("install", self.publish("1.1.0"))
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.calls()[-3:], ["stop --no-restart", "make-overlays %s" % self.path("/var/lib/novos/releases/.partial"),
                                             "start manual restore=1"])
        self.assertTrue(lines[-1]["started"])

    def test_update_that_does_not_start_goes_back(self):
        self.run_setupd("install", self.publish("1.0.0"), "--start")
        open(os.path.join(self.sandbox, "fail-start"), "w").close()
        code, lines = self.run_setupd("install", self.publish("1.1.0"))
        self.assertEqual(code, 1)
        self.assertIn("1.1.0 did not start", self.error_of(lines)[0])
        self.assertIn("1.0.0 runs again", self.error_of(lines)[0])
        self.assertEqual(self.current(), "1.0.0")
        self.assertEqual(os.listdir(self.path("/var/lib/novos/releases")), ["1.0.0"])
        self.assertFalse(os.path.exists(self.path("/var/lib/novos/state/disabled")))
        self.assertTrue(self.setupd.running())
        self.assertEqual(self.calls()[-2:], ["start manual restore=1", "start manual restore=1"])

    def test_rollback(self):
        self.run_setupd("install", self.publish("1.0.0"))
        self.run_setupd("install", self.publish("1.1.0"))
        code, lines = self.run_setupd("rollback")
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.0.0")

    def test_install_again_after_rollback(self):
        self.run_setupd("install", self.publish("1.0.0"))
        newer = self.publish("1.1.0")
        self.run_setupd("install", newer)
        self.run_setupd("rollback")
        self.assertEqual(self.current(), "1.0.0")
        overlays = len([c for c in self.calls() if c.startswith("make-overlays")])
        code, lines = self.run_setupd("install", newer)
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.1.0")
        # The same signed release is switched to, not unpacked again.
        self.assertEqual(len([c for c in self.calls() if c.startswith("make-overlays")]), overlays)

    def test_error_after_stop_starts_novos_again(self):
        self.run_setupd("install", self.publish("1.0.0"), "--start")
        open(os.path.join(self.sandbox, "fail-overlays"), "w").close()
        code, lines = self.run_setupd("install", self.publish("1.1.0"))
        self.assertEqual(code, 1)
        self.assertIn("make-overlays.sh failed", self.error_of(lines)[0])
        self.assertEqual(self.current(), "1.0.0")
        self.assertEqual(self.calls()[-2:][0].split()[0], "make-overlays")
        self.assertEqual(self.calls()[-1], "start manual restore=1")
        self.assertTrue(self.setupd.running())

    def test_changed_lg_file_refused(self):
        url = self.publish("1.0.0")
        with open(self.path(TARGETS[1][1]), "a") as handle:
            handle.write("firmware update\n")
        code, lines = self.run_setupd("install", url)
        self.assertEqual(code, 1)
        self.assertIn("LG's files differ", self.error_of(lines)[0])
        self.assertFalse(os.path.lexists(self.path("/var/lib/novos/current")))

    def test_tampered_archive_refused(self):
        url = self.publish("1.0.0")
        with open(os.path.join(self.server, "novos-1.0.0.tar.xz"), "ab") as handle:
            handle.write(b"x")
        code, lines = self.run_setupd("install", url)
        self.assertEqual(code, 1)
        self.assertFalse(os.path.lexists(self.path("/var/lib/novos/current")))

    def test_unknown_key_refused(self):
        url = self.publish("1.0.0")
        with open(release.TRUSTED_KEYS, "w") as handle:
            json.dump({"keys": {}}, handle)
        code, lines = self.run_setupd("install", url)
        self.assertEqual(code, 1)
        self.assertIn("not in trusted-keys.json", self.error_of(lines)[0])

    def test_escaping_entry_refused(self):
        def escape(bundle):
            info = tarfile.TarInfo("../evil")
            data = b"x"
            info.size = len(data)
            bundle.addfile(info, io.BytesIO(data))
        code, lines = self.run_setupd("install", self.publish("1.0.0", extra=escape))
        self.assertEqual(code, 1)
        self.assertIn("unexpected entry", self.error_of(lines)[0])
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(self.path("/var/lib/novos/releases")), "evil")))

    def test_link_in_archive_refused(self):
        def link(bundle):
            info = tarfile.TarInfo("1.0.0/bin/passwd")
            info.type = tarfile.SYMTYPE
            info.linkname = "/etc/passwd"
            bundle.addfile(info)
        code, lines = self.run_setupd("install", self.publish("1.0.0", extra=link))
        self.assertEqual(code, 1)
        self.assertIn("link", self.error_of(lines)[0])

    def test_targets_must_match_manifest(self):
        # CI builds both from one file; a release whose archive overlays more LG files than
        # its signed manifest names must not go on.
        signed = os.path.join(self.server, "signed-targets.txt")
        with open(signed, "w") as handle:
            handle.write("\n".join("%s %s %s" % (n, t, self.lg[n]) for n, t in TARGETS[:2]) + "\n")
        code, lines = self.run_setupd("install", self.publish("1.0.0", manifest_targets=signed))
        self.assertEqual(code, 1)
        self.assertIn("differs from the signed manifest", self.error_of(lines)[0])
        self.assertFalse(os.path.lexists(self.path("/var/lib/novos/current")))

    def test_channels_and_check(self):
        self.publish("1.0.0", channel="stable")
        code, lines = self.run_setupd("check")
        self.assertEqual(code, 0, lines)
        self.assertTrue(lines[-1]["check"]["newer"])
        code, lines = self.run_setupd("update")
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.0.0")
        code, lines = self.run_setupd("update")
        self.assertEqual(code, 0)
        self.assertIn("nothing newer", lines[-1]["message"])
        self.publish("1.1.0-beta.1", channel="beta")
        self.run_setupd("channel", "beta")
        code, lines = self.run_setupd("update")
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.1.0-beta.1")

    def test_beta_until_stable_exists(self):
        # Nothing stored (as after removing novOS with its data) and no stable release yet.
        self.publish("0.9.0-beta.3", channel="beta")
        code, lines = self.run_setupd("check")
        self.assertEqual(code, 0, lines)
        self.assertEqual(lines[-1]["check"]["available"], "0.9.0-beta.3")
        self.publish("1.0.0", channel="stable")
        code, lines = self.run_setupd("check")
        self.assertEqual(lines[-1]["check"]["available"], "1.0.0")
        self.run_setupd("channel", "beta")
        code, lines = self.run_setupd("check")
        self.assertEqual(lines[-1]["check"]["available"], "0.9.0-beta.3")

    def test_install_stores_the_named_channel(self):
        self.publish("1.0.0", channel="stable")
        self.publish("1.1.0-beta.1", channel="beta")
        code, lines = self.run_setupd("install", "beta")
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.current(), "1.1.0-beta.1")
        with open(self.path("/var/lib/novos/state/channel")) as handle:
            self.assertEqual(handle.read().strip(), "beta")

    def test_serve_with_a_channel(self):
        import threading
        import time
        folder = os.path.join(self.sandbox, "bridge")
        os.makedirs(folder)
        self.publish("1.0.0", channel="stable")
        self.publish("1.1.0-beta.1", channel="beta")
        thread = threading.Thread(target=self.setupd.serve, args=(folder, "", "app", 60, "beta"), daemon=True)
        thread.start()
        def state():
            for _ in range(200):
                try:
                    with open(os.path.join(folder, "state.json")) as handle:
                        current = json.load(handle)
                    if current["id"] == "1" and not current.get("busy") and current["phase"] in ("done", "error"):
                        return current
                except (OSError, ValueError, KeyError):
                    pass
                time.sleep(0.05)
            self.fail("no answer")
        # Written before serve reads it, the command would count as left over.
        for _ in range(100):
            if os.path.exists(os.path.join(folder, "state.json")):
                break
            time.sleep(0.05)
        with open(os.path.join(folder, "command.ini"), "w") as handle:
            handle.write("[General]\ncommand=check\nid=1\n")
        result = state()
        self.assertEqual(result["phase"], "done", result)
        self.assertEqual(result["channel"], "beta")
        self.assertEqual(result["result"]["check"]["available"], "1.1.0-beta.1")
        self.assertFalse(os.path.exists(self.path("/var/lib/novos/state/channel")))
        with open(os.path.join(folder, "command.ini"), "w") as handle:
            handle.write("[General]\ncommand=close\nid=2\n")

    def test_error_kinds(self):
        import urllib.error
        kind = self.setupd.error_kind
        self.assertEqual(kind(urllib.error.HTTPError("u", 404, "Not Found", {}, None)), "missing")
        self.assertEqual(kind(urllib.error.HTTPError("u", 503, "Unavailable", {}, None)), "offline")
        self.assertEqual(kind(urllib.error.URLError(OSError("Network is unreachable"))), "offline")
        self.assertEqual(kind(urllib.error.URLError(FileNotFoundError())), "missing")
        self.assertEqual(kind(release.ReleaseError("bad signature")), "failed")

    def test_autostart(self):
        self.run_setupd("install", self.publish("1.0.0"))
        hook = self.path("/var/lib/webosbrew/init.d/50-novos")
        self.assertEqual(self.run_setupd("autostart", "once")[0], 0)
        with open(hook) as handle:
            self.assertIn("\nONCE=1\n", handle.read())
        self.run_setupd("autostart", "on")
        with open(hook) as handle:
            self.assertIn("\nONCE=0\n", handle.read())
        self.run_setupd("autostart", "off")
        self.assertFalse(os.path.exists(hook))

    def test_early_start(self):
        self.run_setupd("install", self.publish("1.0.0"))
        code, lines = self.run_setupd("early", "on")
        self.assertEqual(code, 0, lines)
        env = self.path("/var/systemd/system/env/surface-manager.env")
        with open(env) as handle:
            text = handle.read()
        self.assertTrue(text.startswith("# novOS early start"))
        self.assertIn("PATH=/var/lib/novos/current/bin/early:/mnt/bsppart/bsp/usr/bin", text)
        self.run_setupd("early", "off")
        self.assertFalse(os.path.exists(env))
        self.assertFalse(os.path.exists(self.path("/var/systemd")))

    def test_foreign_env_file_untouched(self):
        self.run_setupd("install", self.publish("1.0.0"))
        env = self.path("/var/systemd/system/env/rec-info-adapter.env")
        os.makedirs(os.path.dirname(env))
        with open(env, "w") as handle:
            handle.write("FOO=1\n")
        code, lines = self.run_setupd("early", "on")
        self.assertEqual(code, 1)
        with open(env) as handle:
            self.assertEqual(handle.read(), "FOO=1\n")
        self.assertFalse(os.path.exists(self.path("/var/systemd/system/env/surface-manager.env")))

    def test_settings_and_block(self):
        flag = self.path("/var/luna/preferences/webosbrew_block_updates")
        code, lines = self.run_setupd("settings", "--keyboard", "t9", "--auto-update", "on", "--block-updates", "on")
        self.assertEqual(code, 0, lines)
        choices = lines[-1]["choices"]
        self.assertEqual((choices["keyboard"], choices["autoUpdate"], choices["blockUpdates"], choices["blockedNow"]),
                         ("t9", True, True, False))
        self.assertTrue(os.path.exists(flag))
        with open(self.path("/var/lib/novos/state/block-updates-before")) as handle:
            self.assertEqual(handle.read().strip(), "absent")
        with open(self.path("/var/lib/novos/state/debug.ini")) as handle:
            text = handle.read()
        self.assertIn("keyboardMode=t9", text)
        self.assertIn("blur=84", text)
        self.run_setupd("settings", "--block-updates", "off", "--keyboard", "qwertz")
        self.assertFalse(os.path.exists(flag))
        with open(self.path("/var/lib/novos/state/debug.ini")) as handle:
            self.assertEqual(handle.read().count("keyboardMode="), 1)
        # The state before novOS stays the first one noted.
        self.run_setupd("settings", "--block-updates", "on")
        with open(self.path("/var/lib/novos/state/block-updates-before")) as handle:
            self.assertEqual(handle.read().strip(), "absent")

    def test_settings_keep_other_debug_values(self):
        path = self.path("/var/lib/novos/state/debug.ini")
        os.makedirs(os.path.dirname(path))
        with open(path, "w") as handle:
            handle.write("[General]\nblur=60\ndemoDevices=true\nkeyboardMode=qwertz\n")
        self.run_setupd("settings", "--keyboard", "t9")
        with open(path) as handle:
            self.assertEqual(handle.read(), "[General]\nblur=60\ndemoDevices=true\nkeyboardMode=t9\n")

    def test_serve_bridge(self):
        import threading
        import time
        folder = os.path.join(self.sandbox, "bridge")
        os.makedirs(folder)
        command = os.path.join(folder, "command.ini")
        with open(command, "w") as handle:
            handle.write("[General]\ncommand=install\nid=old\n")     # left over: not run
        self.publish("1.0.0", channel="stable")
        thread = threading.Thread(target=self.setupd.serve, args=(folder, "", "app", 60), daemon=True)
        thread.start()
        def state():
            for _ in range(100):
                try:
                    with open(os.path.join(folder, "state.json")) as handle:
                        return json.load(handle)
                except (OSError, ValueError):
                    time.sleep(0.05)
        def send(text, phase_from):
            with open(command, "w") as handle:
                handle.write("[General]\n" + text)
            for _ in range(200):
                current = state()
                if current and current["id"] != phase_from and not current.get("busy") and current["phase"] in ("done", "error"):
                    return current
                time.sleep(0.05)
            self.fail("no answer to " + text)
        self.assertEqual(state()["phase"], "idle")
        self.assertFalse(os.path.lexists(self.path("/var/lib/novos/current")))
        result = send("command=install\nid=1\nkeyboard=t9\nautoUpdate=on\nblockUpdates=on\n", "old")
        self.assertEqual(result["phase"], "done", result)
        self.assertEqual(result["percent"], 100)
        self.assertEqual(self.current(), "1.0.0")
        keys = [step["key"] for step in result["steps"] if step["key"]]
        for key in ("manifest", "download", "verify", "unpack", "overlays", "switch", "settings", "start"):
            self.assertIn(key, keys)
        self.assertEqual(result["choices"]["keyboard"], "t9")
        # The setup's window keeps the TV dark: no way back to the source after the restart.
        self.assertIn("start manual restore=0", self.calls())
        result = send("command=check\nid=2\n", "1")
        self.assertIn("installed", result["result"]["message"])
        result = send("command=rollback\nid=3\n", "2")
        self.assertEqual(result["phase"], "error")
        self.assertIn("no release to go back to", result["error"])
        with open(command, "w") as handle:
            handle.write("[General]\ncommand=close\nid=4\n")
        thread.join(10)
        self.assertFalse(thread.is_alive())
        self.assertFalse(state()["serving"])

    def test_serve_in_novos(self):
        """novOS' settings: the supervisor starts serve for a waiting command; channel,
        check and update run from there, and the picture stays on."""
        import threading
        import time
        folder = os.path.join(self.sandbox, "update")
        os.makedirs(folder)
        command = os.path.join(folder, "command.ini")
        state_path = os.path.join(folder, "state.json")
        self.run_setupd("install", self.publish("1.0.0"), "--start")
        self.publish("1.1.0", channel="stable")
        with open(state_path, "w") as handle:
            json.dump({"id": "a", "phase": "done"}, handle)
        with open(command, "w") as handle:
            handle.write("[General]\ncommand=check\nserial=b\n")
        thread = threading.Thread(target=self.setupd.serve, args=(folder, "", "app", 60, None, True, True),
                                  daemon=True)
        thread.start()
        def answer(serial):
            for _ in range(300):
                try:
                    with open(state_path) as handle:
                        current = json.load(handle)
                    if current["id"] == serial and not current.get("busy") and current["phase"] in ("done", "error"):
                        return current
                except (OSError, ValueError, KeyError):
                    pass
                time.sleep(0.05)
            self.fail("no answer to " + serial)
        def send(text, serial):
            with open(command, "w") as handle:
                handle.write("[General]\n%sserial=%s\n" % (text, serial))
            return answer(serial)
        # The waiting command runs at once.
        result = answer("b")
        self.assertEqual(result["result"]["check"]["available"], "1.1.0")
        self.assertTrue(result["result"]["check"]["newer"])
        self.assertEqual(result["installed"], "1.0.0")
        self.assertEqual(result["tv"], {})
        with open(self.path("/var/lib/novos/state/last-check.json")) as handle:
            self.assertEqual(json.load(handle)["available"], "1.1.0")
        result = send("command=channel\nsource=beta\n", "c")
        self.assertEqual(result["channel"], "beta")
        with open(self.path("/var/lib/novos/state/channel")) as handle:
            self.assertEqual(handle.read().strip(), "beta")
        self.publish("1.2.0-beta.1", channel="beta")
        result = send("command=update\n", "d")
        self.assertEqual(result["phase"], "done", result)
        self.assertEqual(result["installed"], "1.2.0-beta.1")
        self.assertEqual(self.current(), "1.2.0-beta.1")
        # From novOS' settings the picture stays on and the TV goes back to what ran.
        self.assertEqual(self.calls()[-1], "start manual restore=1")
        with open(self.path("/var/lib/novos/state/last-check.json")) as handle:
            remembered = json.load(handle)
        self.assertEqual((remembered["installed"], remembered["newer"]), ("1.2.0-beta.1", False))
        with open(command, "w") as handle:
            handle.write("[General]\ncommand=close\nserial=e\n")
        thread.join(10)
        self.assertFalse(thread.is_alive())
        # A command answered already is not run again by the next serve.
        with open(command, "w") as handle:
            handle.write("[General]\ncommand=update\nserial=d\n")
        calls = len(self.calls())
        self.setupd.serve(folder, "", "app", 1, None, True, True)
        self.assertEqual(len(self.calls()), calls)

    def test_uninstall(self):
        self.run_setupd("install", self.publish("1.0.0"))
        code, lines = self.run_setupd("uninstall", "--keep-state")
        self.assertEqual(code, 0, lines)
        self.assertEqual(self.calls()[-1], "uninstall --keep-state")


if __name__ == "__main__":
    unittest.main(verbosity=1)
