#!/usr/bin/env python3
"""Loopback-only bridge from the local Express PoC to the existing setup runner."""

import argparse
import ipaddress
import json
import os
import re
import secrets
import shlex
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from discover import discover_lg_tvs, private_ipv4, ssh_reachable


HERE = Path(__file__).resolve().parent
CORE = HERE.parents[1]
SETUP_SCRIPT = HERE.parent / "setup" / "setup-on-tv.sh"
STATIC = {
    "/": (HERE / "index.html", "text/html; charset=utf-8"),
    "/app.js": (HERE / "app.js", "text/javascript; charset=utf-8"),
    "/style.css": (HERE / "style.css", "text/css; charset=utf-8"),
    "/grain.svg": (HERE / "grain.svg", "image/svg+xml"),
    "/chevron.svg": (HERE / "chevron.svg", "image/svg+xml"),
    "/inter.ttf": (CORE / "lib" / "ui" / "fonts" / "inter-variable.ttf", "font/ttf"),
}
MANUAL_LIMIT = 16
MARKERS = ("NOVOS_USER", "NOVOS_SERVICE", "NOVOS_HASHES", "NOVOS_MOUNTS")
PREFLIGHT = (
    "printf 'NOVOS_USER\\n'; id -un; "
    "printf 'NOVOS_SERVICE\\n'; systemctl is-active surface-manager-daemon.service; "
    "printf 'NOVOS_HASHES\\n'; sha256sum "
    "/usr/lib/qml/QuickSettings/QuickSettings.qml "
    "/usr/lib/qml/QuickSettings/Utils/Style.qml "
    "/usr/palm/applications/com.palm.app.settings/index.multi.html "
    "/usr/palm/applications/com.palm.app.settings/main.css; "
    "printf 'NOVOS_MOUNTS\\n'; "
    "mount | grep -E 'QuickSettings.qml|index.multi.html|main.css|/var/lib/novos' || true"
)
VERSION = (
    "luna-send -n 1 -w 5000 "
    "luna://com.webos.service.tv.systemproperty/getSystemInfo "
    "'{\"keys\":[\"modelName\",\"firmwareVersion\",\"sdkVersion\"]}'"
)


class TVUnavailable(Exception):
    """A preflight check did not establish that the TV is ready."""


def remote(command, target="lg-tv", tty=False):
    try:
        result = subprocess.run(
            [
                "ssh", "-tt" if tty else "-T", "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5", target, command,
            ],
            capture_output=True,
            text=True,
            timeout=18,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise TVUnavailable("SSH zum TV ist nicht erreichbar.") from error
    if result.returncode != 0:
        raise TVUnavailable("SSH zum TV ist nicht erreichbar oder der TV antwortet nicht.")
    return result.stdout


def preflight(target="lg-tv"):
    """Read version, service, hashes and mounts before opening a TV window."""
    sections = {marker: [] for marker in MARKERS}
    current = None
    for line in remote(PREFLIGHT, target=target).splitlines():
        line = line.strip()
        if line in sections:
            current = line
        elif current and line:
            sections[current].append(line)

    if sections["NOVOS_USER"] != ["root"]:
        raise TVUnavailable("Für diesen TV fehlt Root-Zugriff per SSH.")
    if sections["NOVOS_SERVICE"] != ["active"]:
        raise TVUnavailable("Der Oberflächendienst des TV ist nicht aktiv.")
    if len(sections["NOVOS_HASHES"]) != 4 or not all(
        re.fullmatch(r"[0-9a-f]{64}\s+/.+", line) for line in sections["NOVOS_HASHES"]
    ):
        raise TVUnavailable("Die LG-Dateien konnten nicht vollständig geprüft werden.")

    output = remote(VERSION, target=target, tty=True)
    try:
        payload = json.loads(output[output.index("{") : output.rindex("}") + 1])
    except (ValueError, json.JSONDecodeError) as error:
        raise TVUnavailable("Die TV-Version konnte nicht gelesen werden.") from error
    if not payload.get("returnValue") or not payload.get("firmwareVersion"):
        raise TVUnavailable("Die TV-Version konnte nicht gelesen werden.")
    return {
        "ready": True,
        "model": payload.get("modelName", "LG TV"),
        "firmware": payload["firmwareVersion"],
        "webos": payload.get("sdkVersion", ""),
    }


def luna(method, payload, target="lg-tv"):
    command = "luna-send -n 1 -w 5000 " + method + " "
    command += shlex.quote(json.dumps(payload, separators=(",", ":")))
    output = remote(command, target=target, tty=True)
    try:
        response = json.loads(output[output.index("{") : output.rindex("}") + 1])
    except (ValueError, json.JSONDecodeError) as error:
        raise RuntimeError("Der TV hat den Startbefehl nicht bestätigt.") from error
    if not response.get("returnValue"):
        raise RuntimeError("Der TV hat den Startbefehl abgelehnt.")


def png_has_graphics(path):
    """A GRAPHIC capture of a black first frame has no nonzero RGB image data."""
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Die TV-Aufnahme ist keine PNG-Datei.")
    offset = 8
    chunks = []
    width = height = 0
    while offset + 12 <= len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4 : offset + 8]
        value = data[offset + 8 : offset + 8 + size]
        offset += 12 + size
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", value)
            if depth != 8 or color != 2 or interlace != 0:
                raise RuntimeError("Das TV-Bild hat ein unerwartetes PNG-Format.")
        elif kind == b"IDAT":
            chunks.append(value)
        elif kind == b"IEND":
            break
    if not width or not height or not chunks:
        raise RuntimeError("Die TV-Aufnahme ist unvollständig.")
    pixels = zlib.decompress(b"".join(chunks))
    row_size = width * 3 + 1
    if len(pixels) != row_size * height:
        raise RuntimeError("Die TV-Aufnahme ist beschädigt.")
    nonzero = 0
    for row in range(height):
        start = row * row_size + 1
        nonzero += sum(byte != 0 for byte in pixels[start : start + width * 3])
        if nonzero > 1000:
            return True
    return False


def wizard_visible(build, target="lg-tv"):
    remote_file = "/tmp/novos-express-" + build + ".png"
    with tempfile.TemporaryDirectory(prefix="novos-express-") as folder:
        local_file = Path(folder) / "graphic.png"
        try:
            luna(
                "luna://com.webos.service.capture/executeOneShot",
                {"path": remote_file, "method": "GRAPHIC", "format": "PNG", "width": 1920, "height": 1080},
                target=target,
            )
            result = subprocess.run(
                [
                    "scp", "-q", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                    "-o", "ConnectTimeout=5", target + ":" + remote_file, str(local_file),
                ],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError("Das TV-Bild konnte nicht geprüft werden.")
            try:
                return png_has_graphics(local_file)
            except (struct.error, zlib.error) as error:
                raise RuntimeError("Die TV-Aufnahme ist beschädigt.") from error
        finally:
            try:
                remote("rm -f " + shlex.quote(remote_file), target=target)
            except TVUnavailable:
                pass


def relaunch_wizard(build, target="lg-tv"):
    luna(
        "luna://com.webos.service.systemUIManager/closeByAppId",
        {"appId": "com.webos.app.quicksettings"},
        target=target,
    )
    time.sleep(1)
    luna(
        "luna://com.webos.service.systemUIManager/launch",
        {
            "appId": "com.webos.app.quicksettings",
            "main": "file:///tmp/novos-setup-app/" + build + "/setup.qml",
            "params": {"flow": "install"},
        },
        target=target,
    )


def close_test_wizard(target="lg-tv"):
    try:
        result = subprocess.run(
            ["sh", str(SETUP_SCRIPT), "stop"],
            cwd=HERE.parent / "setup",
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
            env={**os.environ, "NOVOS_TV_SSH_TARGET": target},
        )
        if result.returncode != 0:
            print("Wizard-Rückbau fehlgeschlagen; TV bitte prüfen.", file=sys.stderr)
    except (OSError, subprocess.TimeoutExpired):
        print("Wizard-Rückbau fehlgeschlagen; TV bitte prüfen.", file=sys.stderr)


def start_wizard(target="lg-tv"):
    build = "express-" + datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    build += "-" + secrets.token_hex(3)
    process = subprocess.Popen(
        ["sh", str(SETUP_SCRIPT), build, "install"],
        cwd=HERE.parent / "setup",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
        env={**os.environ, "NOVOS_TV_SSH_TARGET": target},
    )
    try:
        stdout, stderr = process.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate()
        close_test_wizard(target)
        raise RuntimeError("Der Start hat zu lange gedauert.") from None
    if process.returncode != 0:
        print(stderr.strip() or stdout.strip(), file=sys.stderr)
        close_test_wizard(target)
        raise RuntimeError("Der Wizard konnte nicht geöffnet werden. Details stehen im Terminal.")
    try:
        if not wizard_visible(build, target):
            relaunch_wizard(build, target)
            if not wizard_visible(build, target):
                raise RuntimeError("Der Wizard blieb auch nach einem zweiten Start schwarz.")
    except (TVUnavailable, RuntimeError, OSError, subprocess.TimeoutExpired):
        close_test_wizard(target)
        raise


def configured_tv_address():
    """Resolve the existing SSH alias without reading or copying its config file."""
    try:
        result = subprocess.run(
            ["ssh", "-G", "lg-tv"], capture_output=True, text=True, timeout=5, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    for line in result.stdout.splitlines():
        if line.startswith("hostname "):
            name = line.split(None, 1)[1].strip()
            if private_ipv4(name):
                return name
            try:
                address = socket.gethostbyname(name)
            except OSError:
                return ""
            return address if private_ipv4(address) else ""
    return ""


def manual_entry(address, ssh):
    return {"address": address, "name": address, "model": "", "ssh": ssh, "manual": True}


def listed_device(item, alias_address):
    """Give a found TV a random id; the browser never sees an SSH target."""
    address = item["address"]
    target = "lg-tv" if address == alias_address else "root@" + address
    device = {
        "id": secrets.token_urlsafe(16),
        "name": item["name"],
        "model": item["model"],
        "address": address,
        "ssh": item["ssh"],
        "manual": item.get("manual", False),
    }
    return device, target


class ExpressServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port):
        super().__init__(("127.0.0.1", port), ExpressHandler)
        self.csrf_token = secrets.token_urlsafe(32)
        self.start_lock = threading.Lock()
        self.device_lock = threading.Lock()
        self.devices = {}
        self.devices_until = 0
        self.manual = []

    def scan_devices(self):
        message = ""
        try:
            found = discover_lg_tvs()
        except OSError:
            found = []
            message = "Die Netzwerksuche war nicht möglich."
        alias_address = configured_tv_address()
        if alias_address and all(item["address"] != alias_address for item in found):
            found.append({"address": alias_address, "name": "Konfigurierter LG-TV", "model": "", "ssh": True})
            if not message:
                message = "Der konfigurierte TV antwortete nicht auf die Netzwerksuche."
        with self.device_lock:
            manual = list(self.manual)
        for address in manual:
            if all(item["address"] != address for item in found):
                found.append(manual_entry(address, ssh_reachable(address)))
        registry = {}
        devices = []
        for item in found:
            if not private_ipv4(item["address"]):
                continue
            device, target = listed_device(item, alias_address)
            registry[device["id"]] = target
            devices.append(device)
        with self.device_lock:
            self.devices = registry
            self.devices_until = time.monotonic() + 300
        if not devices and not message:
            message = "Kein LG-TV im lokalen Netzwerk gefunden."
        return {"devices": devices, "message": message}

    def add_device(self, value):
        """Register a TV typed in by hand; it stays in the list for later scans."""
        try:
            address = str(ipaddress.IPv4Address(value))
        except ipaddress.AddressValueError:
            raise ValueError("Das ist keine gültige IP-Adresse, zum Beispiel 192.168.178.20.") from None
        if not private_ipv4(address):
            raise ValueError("Nur Adressen aus dem Heimnetz sind erlaubt, etwa 192.168.… oder 10.….")
        if not ssh_reachable(address, timeout=2):
            raise TVUnavailable("Unter " + address + " antwortet kein Fernseher per SSH.")
        device, target = listed_device(manual_entry(address, True), configured_tv_address())
        with self.device_lock:
            if time.monotonic() > self.devices_until:
                self.devices = {}
            self.devices[device["id"]] = target
            self.devices_until = time.monotonic() + 300
            if address not in self.manual:
                self.manual = (self.manual + [address])[-MANUAL_LIMIT:]
        return device

    def target_for(self, identifier):
        with self.device_lock:
            if time.monotonic() > self.devices_until:
                raise TVUnavailable("Die Geräteliste ist abgelaufen. Bitte erneut suchen.")
            target = self.devices.get(identifier)
        if target is None:
            raise TVUnavailable("Der ausgewählte TV wurde nicht gefunden. Bitte erneut suchen.")
        return target


class ExpressHandler(BaseHTTPRequestHandler):
    def selected_tv(self):
        values = parse_qs(urlsplit(self.path).query, keep_blank_values=True).get("tv", [])
        if len(values) != 1 or not values[0]:
            raise TVUnavailable("Bitte einen TV aus der Geräteliste wählen.")
        return self.server.target_for(values[0])

    def trusted_host(self):
        return self.headers.get("Host") == "127.0.0.1:%d" % self.server.server_port

    def send_bytes(self, status, data, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self'; font-src 'self'; connect-src 'self'; "
            "form-action 'none'; frame-ancestors 'none'",
        )
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, status, value):
        self.send_bytes(status, json.dumps(value, ensure_ascii=False).encode(), "application/json")

    def do_GET(self):
        if not self.trusted_host():
            self.send_json(403, {"error": "Ungültiger Host."})
            return
        path = urlsplit(self.path).path
        if path == "/api/tvs":
            self.send_json(200, self.server.scan_devices())
            return
        if path == "/api/status":
            try:
                self.send_json(200, preflight(self.selected_tv()))
            except TVUnavailable as error:
                self.send_json(200, {"ready": False, "error": str(error)})
            return
        asset = STATIC.get(path)
        if asset is None:
            self.send_json(404, {"error": "Nicht gefunden."})
            return
        file, content_type = asset
        try:
            data = file.read_bytes()
        except OSError:
            self.send_json(500, {"error": "Datei fehlt."})
            return
        if path == "/":
            data = data.replace(b"{{CSRF_TOKEN}}", self.server.csrf_token.encode())
        self.send_bytes(200, data, content_type)

    def add_device(self):
        values = parse_qs(urlsplit(self.path).query, keep_blank_values=True).get("address", [])
        if len(values) != 1 or not values[0].strip():
            self.send_json(400, {"error": "Bitte eine IP-Adresse eingeben."})
            return
        try:
            device = self.server.add_device(values[0].strip())
        except ValueError as error:
            self.send_json(400, {"error": str(error)})
            return
        except TVUnavailable as error:
            self.send_json(404, {"error": str(error)})
            return
        self.send_json(200, {"device": device})

    def do_POST(self):
        origin = "http://127.0.0.1:%d" % self.server.server_port
        if (
            not self.trusted_host()
            or self.headers.get("Origin") != origin
            or self.headers.get("X-Novos-CSRF") != self.server.csrf_token
            or self.headers.get("Content-Length", "0") != "0"
            or self.headers.get("Transfer-Encoding")
        ):
            self.send_json(403, {"error": "Anfrage abgelehnt."})
            return
        path = urlsplit(self.path).path
        if path == "/api/device":
            self.add_device()
            return
        if path != "/api/start":
            self.send_json(404, {"error": "Nicht gefunden."})
            return
        if not self.server.start_lock.acquire(blocking=False):
            self.send_json(409, {"error": "Der Wizard wird bereits gestartet."})
            return
        try:
            target = self.selected_tv()
            preflight(target)
            start_wizard(target)
            self.send_json(200, {"ok": True, "message": "Der Wizard ist auf dem TV geöffnet."})
        except TVUnavailable as error:
            self.send_json(503, {"ok": False, "error": str(error)})
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            self.send_json(500, {"ok": False, "error": str(error)})
        finally:
            self.server.start_lock.release()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ExpressServer(args.port)
    print("novOS Express: http://127.0.0.1:%d" % server.server_port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
