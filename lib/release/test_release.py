#!/usr/bin/env python3
"""Tests of ed25519.py and release.py, run in CI before every release.

    python3 lib/release/test_release.py
"""

import base64
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ed25519  # noqa: E402
import release  # noqa: E402

# RFC 8032, section 7.1: tests 1 to 3 (secret, public, message, signature).
VECTORS = [
    ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
     "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
    ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
     "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
     "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
     "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
]


class Ed25519Test(unittest.TestCase):
    def test_rfc_vectors(self):
        for secret, public, message, signature in VECTORS:
            secret, public = bytes.fromhex(secret), bytes.fromhex(public)
            message, signature = bytes.fromhex(message), bytes.fromhex(signature)
            self.assertEqual(ed25519.public_key(secret), public)
            self.assertEqual(ed25519.sign(secret, message), signature)
            self.assertTrue(ed25519.verify(public, message, signature))

    def test_rejects_changes(self):
        secret, public, message, signature = (bytes.fromhex(v) for v in VECTORS[1])
        self.assertFalse(ed25519.verify(public, message + b"x", signature))
        self.assertFalse(ed25519.verify(public, message, signature[:-1] + bytes([signature[-1] ^ 1])))
        self.assertFalse(ed25519.verify(public, message, signature[:63]))
        other = ed25519.public_key(bytes(32))
        self.assertFalse(ed25519.verify(other, message, signature))

    def test_matches_cryptography(self):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        except ImportError:
            self.skipTest("cryptography is not installed")
        secret = os.urandom(32)
        key = Ed25519PrivateKey.from_private_bytes(secret)
        message = os.urandom(200)
        self.assertEqual(ed25519.sign(secret, message), key.sign(message))
        self.assertTrue(ed25519.verify(ed25519.public_key(secret), message, key.sign(message)))


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.secret = os.urandom(32)
        public = ed25519.public_key(self.secret)
        self.keys = os.path.join(self.folder, "trusted-keys.json")
        with open(self.keys, "w") as handle:
            json.dump({"keys": {release.key_id(public): base64.b64encode(public).decode()}}, handle)
        self.saved_keys = release.TRUSTED_KEYS
        release.TRUSTED_KEYS = self.keys
        os.environ["NOVOS_SIGNING_KEY"] = base64.b64encode(self.secret).decode()
        self.archive = os.path.join(self.folder, "novos-1.0.0.tar.xz")
        with open(self.archive, "wb") as handle:
            handle.write(os.urandom(5000))

    def tearDown(self):
        release.TRUSTED_KEYS = self.saved_keys
        del os.environ["NOVOS_SIGNING_KEY"]

    def build(self, version="1.0.0"):
        manifest = os.path.join(self.folder, "m.json")
        signature = manifest + ".sig"
        args = ["manifest", "--app", "novos", "--version", version, "--tag", "novos-v" + version,
                "--archive", self.archive, "--url", "https://example.invalid/a.tar.xz"]
        self.run_to(args, manifest)
        self.run_to(["sign", manifest], signature)
        return manifest, signature

    def run_to(self, args, path):
        saved = sys.stdout
        with open(path, "w") as handle:
            sys.stdout = handle
            try:
                self.assertEqual(release.main(args), 0)
            finally:
                sys.stdout = saved

    def test_round_trip(self):
        manifest, signature = self.build()
        result = release.verify_files(manifest, signature, self.archive, "novos")
        self.assertEqual(result["version"], "1.0.0")
        self.assertEqual(result["channel"], "stable")

    def test_beta_channel(self):
        manifest, signature = self.build("1.1.0-beta.2")
        self.assertEqual(release.verify_files(manifest, signature)["channel"], "beta")

    def test_tampered_manifest(self):
        manifest, signature = self.build()
        with open(manifest) as handle:
            text = handle.read()
        with open(manifest, "w") as handle:
            handle.write(text.replace("1.0.0", "1.0.1"))
        with self.assertRaises(release.ReleaseError):
            release.verify_files(manifest, signature)

    def test_tampered_archive(self):
        manifest, signature = self.build()
        with open(self.archive, "ab") as handle:
            handle.write(b"x")
        with self.assertRaises(release.ReleaseError):
            release.verify_files(manifest, signature, self.archive)

    def test_unknown_key(self):
        manifest, signature = self.build()
        with open(self.keys, "w") as handle:
            json.dump({"keys": {}}, handle)
        with self.assertRaises(release.ReleaseError):
            release.verify_files(manifest, signature)

    def test_wrong_app(self):
        manifest, signature = self.build()
        with self.assertRaises(release.ReleaseError):
            release.verify_files(manifest, signature, app="setup")

    def test_version_order(self):
        ordered = ["0.9.0", "1.0.0-beta.1", "1.0.0-beta.2", "1.0.0-beta.10", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.10.0"]
        self.assertEqual(sorted(reversed(ordered), key=release.version_key), ordered)
        with self.assertRaises(release.ReleaseError):
            release.channel_of("v1.0")


if __name__ == "__main__":
    unittest.main(verbosity=1)
