#!/usr/bin/env python3
"""Signed releases of novOS' apps: manifest, signature, channel files, checked download.

A release is an archive plus <app>-<version>.manifest.json, which names the archive with its
size and SHA-256, and <app>-<version>.manifest.json.sig, an Ed25519 signature of the
manifest's exact bytes. Channel files (<app>/stable.json, <app>/beta.json on GitHub Pages)
only point to a manifest; whatever they say, nothing is used before the signature and the
archive's hash are checked against a key in trusted-keys.json.

    release.py keygen <secret-file> [--trust]
    release.py manifest --app novos --version 1.0.0 --tag novos-v1.0.0 --archive <file>
                        --url <download-url> [--targets <lg-targets.txt>] [--restarts 1]
                        [--commit <sha>]                               > manifest.json
    release.py sign <manifest>              (secret in NOVOS_SIGNING_KEY)  > manifest.json.sig
    release.py verify <manifest> <signature> [--archive <file>]
    release.py channel --app novos --version 1.0.0 --manifest-url <url> --signature-url <url>
                       [--keep-newer <current channel file>]
    release.py fetch <stable|beta|manifest-url> --app novos --out <dir>

Runs on Python 3.6 and later, with the standard library only, also on the TV.
"""

import argparse
import base64
import hashlib
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ed25519  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
# NOVOS_TRUSTED_KEYS points elsewhere for tests with a throwaway key.
TRUSTED_KEYS = os.environ.get("NOVOS_TRUSTED_KEYS") or os.path.join(HERE, "trusted-keys.json")
PAGES = "https://connyscode.github.io/novOS"
FORMAT = 1
VERSION_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$")


class ReleaseError(Exception):
    pass


def key_id(public):
    return hashlib.sha256(public).hexdigest()[:16]


def channel_of(version):
    match = VERSION_PATTERN.match(version)
    if not match:
        raise ReleaseError("not a version: %r (expected 1.2.3 or 1.2.3-beta.1)" % version)
    return "beta" if match.group(4) else "stable"


def version_key(version):
    """Sort key: 1.0.0-beta.2 < 1.0.0-rc.1 < 1.0.0 < 1.0.1."""
    match = VERSION_PATTERN.match(version)
    if not match:
        raise ReleaseError("not a version: %r" % version)
    numbers = tuple(int(part) for part in match.group(1, 2, 3))
    if match.group(4) is None:
        return numbers + (1, ())
    parts = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in match.group(4).split("."))
    return numbers + (0, parts)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def read_targets(path):
    targets = []
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, target, digest = line.split()
            targets.append({"file": name, "target": target, "sha256": digest})
    return targets


def trusted_keys():
    with open(TRUSTED_KEYS) as handle:
        return json.load(handle).get("keys", {})


def dump(data):
    return json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


def make_manifest(args):
    channel = channel_of(args.version)
    manifest = {
        "format": FORMAT,
        "app": args.app,
        "version": args.version,
        "channel": channel,
        "tag": args.tag,
        "commit": args.commit or "",
        "published": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "archive": {
            "name": os.path.basename(args.archive),
            "url": args.url,
            "size": os.path.getsize(args.archive),
            "sha256": sha256_file(args.archive),
        },
    }
    if args.targets:
        manifest["lg_targets"] = read_targets(args.targets)
    if args.restarts is not None:
        manifest["restarts"] = args.restarts
    return manifest


def sign_bytes(data):
    encoded = os.environ.get("NOVOS_SIGNING_KEY", "").strip()
    if not encoded:
        raise ReleaseError("NOVOS_SIGNING_KEY is empty")
    secret = base64.b64decode(encoded)
    public = ed25519.public_key(secret)
    return {"format": FORMAT, "key": key_id(public),
            "signature": base64.b64encode(ed25519.sign(secret, data)).decode()}


def check_signature(data, signature):
    keys = trusted_keys()
    public = keys.get(signature.get("key", ""))
    if public is None:
        raise ReleaseError("signed with key %r, which is not in trusted-keys.json" % signature.get("key"))
    if not ed25519.verify(base64.b64decode(public), data, base64.b64decode(signature.get("signature", ""))):
        raise ReleaseError("the signature does not match the manifest")


def check_archive(manifest, path):
    archive = manifest["archive"]
    if os.path.getsize(path) != archive["size"]:
        raise ReleaseError("archive size %d, manifest says %d" % (os.path.getsize(path), archive["size"]))
    if sha256_file(path) != archive["sha256"]:
        raise ReleaseError("archive SHA-256 does not match the manifest")


def verify_files(manifest_path, signature_path, archive_path=None, app=None):
    """Checks signature, form and optionally the archive; returns the manifest."""
    with open(manifest_path, "rb") as handle:
        data = handle.read()
    with open(signature_path) as handle:
        signature = json.load(handle)
    check_signature(data, signature)
    manifest = json.loads(data.decode("utf-8"))
    if manifest.get("format") != FORMAT:
        raise ReleaseError("manifest format %r is not %d" % (manifest.get("format"), FORMAT))
    if app and manifest.get("app") != app:
        raise ReleaseError("manifest is for %r, not %r" % (manifest.get("app"), app))
    channel_of(manifest["version"])
    if archive_path:
        check_archive(manifest, archive_path)
    return manifest


def download(url, path):
    request = urllib.request.Request(url, headers={"User-Agent": "novos-release/1"})
    with urllib.request.urlopen(request, timeout=60) as response, open(path, "wb") as handle:
        for block in iter(lambda: response.read(1 << 16), b""):
            handle.write(block)


def fetch(source, app, out):
    """Downloads a release into out and checks it; returns the manifest."""
    os.makedirs(out, exist_ok=True)
    if source in ("stable", "beta"):
        pointer_path = os.path.join(out, "channel.json")
        download("%s/%s/%s.json" % (PAGES, app, source), pointer_path)
        with open(pointer_path) as handle:
            pointer = json.load(handle)
        manifest_url, signature_url = pointer["manifest"], pointer["signature"]
    else:
        manifest_url, signature_url = source, source + ".sig"
    manifest_path = os.path.join(out, os.path.basename(manifest_url))
    signature_path = manifest_path + ".sig"
    download(manifest_url, manifest_path)
    download(signature_url, signature_path)
    manifest = verify_files(manifest_path, signature_path, app=app)
    if source in ("stable", "beta") and manifest["version"] != pointer.get("version"):
        raise ReleaseError("channel points to %s, manifest is %s" % (pointer.get("version"), manifest["version"]))
    archive_path = os.path.join(out, manifest["archive"]["name"])
    download(manifest["archive"]["url"], archive_path)
    check_archive(manifest, archive_path)
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command")

    keygen = sub.add_parser("keygen", help="new signing key; the secret goes to a file, never to the screen")
    keygen.add_argument("secret_file")
    keygen.add_argument("--trust", action="store_true", help="add the public key to trusted-keys.json")

    manifest = sub.add_parser("manifest")
    manifest.add_argument("--app", required=True)
    manifest.add_argument("--version", required=True)
    manifest.add_argument("--tag", required=True)
    manifest.add_argument("--archive", required=True)
    manifest.add_argument("--url", required=True)
    manifest.add_argument("--targets")
    manifest.add_argument("--restarts", type=int)
    manifest.add_argument("--commit")

    sign = sub.add_parser("sign")
    sign.add_argument("manifest")

    verify = sub.add_parser("verify")
    verify.add_argument("manifest")
    verify.add_argument("signature")
    verify.add_argument("--archive")
    verify.add_argument("--app")

    channel = sub.add_parser("channel")
    channel.add_argument("--app", required=True)
    channel.add_argument("--version", required=True)
    channel.add_argument("--manifest-url", required=True)
    channel.add_argument("--signature-url", required=True)
    channel.add_argument("--keep-newer", help="channel file to keep when it already names a newer version")

    fetch_parser = sub.add_parser("fetch")
    fetch_parser.add_argument("source", help="stable, beta or the URL of a manifest")
    fetch_parser.add_argument("--app", required=True)
    fetch_parser.add_argument("--out", required=True)

    args = parser.parse_args(argv)
    try:
        if args.command == "keygen":
            if os.path.exists(args.secret_file):
                raise ReleaseError("%s exists; refusing to overwrite a key" % args.secret_file)
            secret = os.urandom(32)
            descriptor = os.open(args.secret_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as handle:
                handle.write(base64.b64encode(secret).decode() + "\n")
            public = ed25519.public_key(secret)
            print("key id     %s" % key_id(public))
            print("public key %s" % base64.b64encode(public).decode())
            if args.trust:
                with open(TRUSTED_KEYS) as handle:
                    data = json.load(handle)
                data.setdefault("keys", {})[key_id(public)] = base64.b64encode(public).decode()
                with open(TRUSTED_KEYS, "w") as handle:
                    handle.write(dump(data))
                print("added to %s" % TRUSTED_KEYS)
        elif args.command == "manifest":
            sys.stdout.write(dump(make_manifest(args)))
        elif args.command == "sign":
            with open(args.manifest, "rb") as handle:
                sys.stdout.write(dump(sign_bytes(handle.read())))
        elif args.command == "verify":
            result = verify_files(args.manifest, args.signature, args.archive, args.app)
            print("ok: %s %s, signed by a trusted key%s" % (result["app"], result["version"],
                                                           ", archive matches" if args.archive else ""))
        elif args.command == "channel":
            if args.keep_newer and os.path.exists(args.keep_newer):
                with open(args.keep_newer) as handle:
                    current = json.load(handle)
                if version_key(current["version"]) > version_key(args.version):
                    sys.stdout.write(dump(current))
                    return 0
            sys.stdout.write(dump({"format": FORMAT, "app": args.app, "version": args.version,
                                   "channel": channel_of(args.version),
                                   "manifest": args.manifest_url, "signature": args.signature_url}))
        elif args.command == "fetch":
            result = fetch(args.source, args.app, args.out)
            print(result["version"])
        else:
            parser.print_help()
            return 2
    except (ReleaseError, KeyError, ValueError, OSError) as error:
        sys.stderr.write("release.py: %s\n" % error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
