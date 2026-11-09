#!/usr/bin/env python3
"""Upload of power-off videos and pictures from a phone or computer in the same network.

    novos-upload.py serve [--folder DIR] [--media DIR] [--port N]
    novos-upload.py qr <text> <file.png>          writes a QR code, for tests

The settings page "Vom Handy oder Computer" leaves "command=open" in <folder>/command.ini
(SetupBridge); the supervisor starts this service for it. While it runs it serves one
plain page under a fresh random path on the TV's address, http://<ip>:<port>/<code>,
shown on the TV as a QR code and as text to type on a computer (five letters and digits
without look-alikes, any case). The page sends each chosen file with PUT; the file lands in
<media> with an entry in <media>/index.json that ShutdownScreens.js reads. The TV follows
<folder>/state.json. The service ends on "command=close", after ten minutes, or when the
settings window is gone (no new command) for ten minutes.

Only videos (MP4, MOV) and pictures (JPEG, PNG) are taken, each up to 200 MB, all of them
together up to 300 MB and never below 150 MB free on the data partition.
"""

import binascii
import html
import json
import os
import random
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FOLDER = "/tmp/novos-upload"
MEDIA = "/var/lib/novos/state/media"
PORT = 8642
LIFETIME = 600                    # seconds a code stays valid
FILE_LIMIT = 200 * 1024 * 1024
MEDIA_LIMIT = 300 * 1024 * 1024
KEEP_FREE = 150 * 1024 * 1024
THUMB_LIMIT = 2 * 1024 * 1024
PLAY_LIMIT = 15000                # ms of a video that play at power off
PICTURE_LENGTH = 3000             # ms a picture stays; the user sets it in a later step
CODE_LETTERS = "abcdefghjkmnpqrstuvwxyz23456789"
TYPES = {".mp4": "video", ".m4v": "video", ".mov": "video", ".jpg": "image", ".jpeg": "image",
         ".png": "image"}


# ---- QR code (byte mode, error correction M, versions 1 to 10) ----------------------

ECC_PER_BLOCK = [None, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
BLOCKS = [None, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]


def _raw_modules(version):
    result = (16 * version + 128) * version + 64
    if version >= 2:
        count = version // 7 + 2
        result -= (25 * count - 10) * count - 55
        if version >= 7:
            result -= 36
    return result


def _data_codewords(version):
    return _raw_modules(version) // 8 - ECC_PER_BLOCK[version] * BLOCKS[version]


def _gf_mul(x, y):
    z = 0
    for i in reversed(range(8)):
        z = (z << 1) ^ ((z >> 7) * 0x11D)
        z ^= ((y >> i) & 1) * x
    return z


def _rs_divisor(degree):
    result = [0] * (degree - 1) + [1]
    root = 1
    for _ in range(degree):
        for j in range(degree):
            result[j] = _gf_mul(result[j], root)
            if j + 1 < degree:
                result[j] ^= result[j + 1]
        root = _gf_mul(root, 0x02)
    return result


def _rs_remainder(data, divisor):
    result = [0] * len(divisor)
    for byte in data:
        factor = byte ^ result.pop(0)
        result.append(0)
        for i, coefficient in enumerate(divisor):
            result[i] ^= _gf_mul(coefficient, factor)
    return result


def _alignment_positions(version):
    if version == 1:
        return []
    count = version // 7 + 2
    size = version * 4 + 17
    step = (version * 8 + count * 3 + 5) // (count * 4 - 4) * 2
    return list(reversed([size - 7 - i * step for i in range(count - 1)] + [6]))


def qr_matrix(text):
    """Rows of booleans, True for dark, without the quiet zone."""
    data = text.encode("utf-8")
    for version in range(1, 11):
        count_bits = 8 if version < 10 else 16
        if 4 + count_bits + 8 * len(data) <= _data_codewords(version) * 8:
            break
    else:
        raise ValueError("text too long for a QR code up to version 10")
    capacity = _data_codewords(version) * 8
    bits = [0, 1, 0, 0] + [(len(data) >> i) & 1 for i in reversed(range(count_bits))]
    for byte in data:
        bits += [(byte >> i) & 1 for i in reversed(range(8))]
    bits += [0] * min(4, capacity - len(bits))
    bits += [0] * (-len(bits) % 8)
    codewords = [int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]
    pad = 0xEC
    while len(codewords) < _data_codewords(version):
        codewords.append(pad)
        pad ^= 0xEC ^ 0x11

    # Error correction per block, then interleaved.
    blocks_count = BLOCKS[version]
    ecc_length = ECC_PER_BLOCK[version]
    raw = _raw_modules(version) // 8
    short_blocks = blocks_count - raw % blocks_count
    short_length = raw // blocks_count
    divisor = _rs_divisor(ecc_length)
    blocks = []
    k = 0
    for i in range(blocks_count):
        length = short_length - ecc_length + (0 if i < short_blocks else 1)
        block = codewords[k:k + length]
        k += length
        ecc = _rs_remainder(block, divisor)
        if i < short_blocks:
            block.append(0)
        blocks.append(block + ecc)
    final = []
    for i in range(len(blocks[0])):
        for j, block in enumerate(blocks):
            if i != short_length - ecc_length or j >= short_blocks:
                final.append(block[i])

    size = version * 4 + 17
    modules = [[False] * size for _ in range(size)]
    function = [[False] * size for _ in range(size)]

    def put(x, y, dark):
        modules[y][x] = dark
        function[y][x] = True

    for i in range(size):
        put(6, i, i % 2 == 0)
        put(i, 6, i % 2 == 0)
    for cx, cy in ((3, 3), (size - 4, 3), (3, size - 4)):
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                x, y = cx + dx, cy + dy
                if 0 <= x < size and 0 <= y < size:
                    put(x, y, max(abs(dx), abs(dy)) not in (2, 4))
    positions = _alignment_positions(version)
    last = len(positions) - 1
    for i, ax in enumerate(positions):
        for j, ay in enumerate(positions):
            if (i, j) in ((0, 0), (0, last), (last, 0)):
                continue
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    put(ax + dx, ay + dy, max(abs(dx), abs(dy)) != 1)

    def format_bits(mask):
        value = (0 << 3) | mask          # level M
        remainder = value
        for _ in range(10):
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
        return ((value << 10) | remainder) ^ 0x5412

    def draw_format(mask):
        value = format_bits(mask)
        bit = lambda i: (value >> i) & 1 == 1
        for i in range(6):
            put(8, i, bit(i))
        put(8, 7, bit(6))
        put(8, 8, bit(7))
        put(7, 8, bit(8))
        for i in range(9, 15):
            put(14 - i, 8, bit(i))
        for i in range(8):
            put(size - 1 - i, 8, bit(i))
        for i in range(8, 15):
            put(8, size - 15 + i, bit(i))
        put(8, size - 8, True)

    draw_format(0)
    if version >= 7:
        remainder = version
        for _ in range(12):
            remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
        value = (version << 12) | remainder
        for i in range(18):
            dark = (value >> i) & 1 == 1
            a, b = size - 11 + i % 3, i // 3
            put(a, b, dark)
            put(b, a, dark)

    index = 0
    right = size - 1
    while right >= 1:
        if right == 6:
            right = 5
        for vertical in range(size):
            for j in range(2):
                x = right - j
                upward = ((right + 1) & 2) == 0
                y = size - 1 - vertical if upward else vertical
                if not function[y][x] and index < len(final) * 8:
                    modules[y][x] = (final[index >> 3] >> (7 - (index & 7))) & 1 == 1
                    index += 1
        right -= 2

    masks = [
        lambda x, y: (x + y) % 2 == 0,
        lambda x, y: y % 2 == 0,
        lambda x, y: x % 3 == 0,
        lambda x, y: (x + y) % 3 == 0,
        lambda x, y: (x // 3 + y // 2) % 2 == 0,
        lambda x, y: x * y % 2 + x * y % 3 == 0,
        lambda x, y: (x * y % 2 + x * y % 3) % 2 == 0,
        lambda x, y: ((x + y) % 2 + x * y % 3) % 2 == 0,
    ]

    def apply(mask):
        test = masks[mask]
        for y in range(size):
            for x in range(size):
                if not function[y][x] and test(x, y):
                    modules[y][x] = not modules[y][x]

    best = None
    for mask in range(8):
        apply(mask)
        draw_format(mask)
        score = _penalty(modules)
        if best is None or score < best[0]:
            best = (score, mask)
        apply(mask)                  # undo, the mask is its own inverse
    apply(best[1])
    draw_format(best[1])
    return modules


def _penalty(modules):
    size = len(modules)
    score = 0
    lines = [row for row in modules] + [[modules[y][x] for y in range(size)] for x in range(size)]
    finder = [True, False, True, True, True, False, True]
    for line in lines:
        run, previous = 0, None
        for dark in line:
            if dark == previous:
                run += 1
            else:
                if run >= 5:
                    score += run - 2
                run, previous = 1, dark
        if run >= 5:
            score += run - 2
        padded = [False] * 4 + list(line) + [False] * 4
        for i in range(len(padded) - 10):
            if padded[i:i + 7] == finder and not any(padded[i + 7:i + 11]):
                score += 40
            if padded[i + 4:i + 11] == finder and not any(padded[i:i + 4]):
                score += 40
    for y in range(size - 1):
        for x in range(size - 1):
            if modules[y][x] == modules[y][x + 1] == modules[y + 1][x] == modules[y + 1][x + 1]:
                score += 3
    dark = sum(sum(row) for row in modules)
    total = size * size
    score += max(0, (abs(dark * 20 - total * 10) + total - 1) // total - 1) * 10
    return score


def write_png(path, modules, scale=10, border=4):
    """A black-on-white PNG of the code, with the quiet zone of four modules."""
    size = (len(modules) + 2 * border) * scale
    rows = []
    for y in range(size):
        my = y // scale - border
        row = bytearray([0])
        for x in range(size):
            mx = x // scale - border
            dark = 0 <= my < len(modules) and 0 <= mx < len(modules) and modules[my][mx]
            row.append(0 if dark else 255)
        rows.append(bytes(row))

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload +
                struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + \
        chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
    write_bytes(path, data)


# ---- Videos: length and sound from the MP4 or MOV boxes -----------------------------

def video_facts(path):
    """(length in ms or 0, has a sound track) from moov/mvhd and the handlers of the tracks."""
    length, sound = 0, False
    try:
        with open(path, "rb") as file:
            end = os.path.getsize(path)
            for kind, start, stop in _boxes(file, 0, end):
                if kind != b"moov":
                    continue
                for inner, istart, istop in _boxes(file, start, stop):
                    if inner == b"mvhd":
                        file.seek(istart)
                        version = file.read(1)[0]
                        file.seek(istart + (20 if version == 1 else 12))
                        timescale = struct.unpack(">I", file.read(4))[0]
                        duration = struct.unpack(">Q" if version == 1 else ">I",
                                                 file.read(8 if version == 1 else 4))[0]
                        if timescale:
                            length = int(duration * 1000 / timescale)
                    elif inner == b"trak":
                        for media, mstart, mstop in _boxes(file, istart, istop):
                            if media != b"mdia":
                                continue
                            for part, pstart, _ in _boxes(file, mstart, mstop):
                                if part == b"hdlr":
                                    file.seek(pstart + 8)
                                    if file.read(4) == b"soun":
                                        sound = True
    except (OSError, struct.error, IndexError):
        pass
    return length, sound


def _boxes(file, start, stop):
    position = start
    while position + 8 <= stop:
        file.seek(position)
        size, kind = struct.unpack(">I4s", file.read(8))
        header = 8
        if size == 1:
            size = struct.unpack(">Q", file.read(8))[0]
            header = 16
        elif size == 0:
            size = stop - position
        if size < header:
            return
        yield kind, position + header, min(position + size, stop)
        position += size


# ---- Files ----------------------------------------------------------------------------

def write_bytes(path, data):
    temporary = path + ".new"
    with open(temporary, "wb") as file:
        file.write(data)
        file.flush()
        os.fsync(file.fileno())
    os.replace(temporary, path)


def write_json(path, value):
    write_bytes(path, json.dumps(value, ensure_ascii=False, indent=1).encode("utf-8"))


def read_json(path, fallback):
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file)
    except (OSError, ValueError):
        return fallback


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


def address():
    """The TV's address in the home network."""
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("192.0.2.1", 9))           # no packet goes out
        found = probe.getsockname()[0]
        probe.close()
        if not found.startswith("127."):
            return found
    except OSError:
        pass
    try:
        text = subprocess.run(["ip", "-4", "-o", "addr"], capture_output=True, text=True, timeout=5).stdout
        for line in text.splitlines():
            parts = line.split()
            if "inet" in parts:
                found = parts[parts.index("inet") + 1].split("/")[0]
                if not found.startswith("127."):
                    return found
    except (OSError, subprocess.SubprocessError):
        pass
    return ""


# ---- The page -------------------------------------------------------------------------

TEXTS = {
    "de": ("Ausschalt-Video", "Video oder Bild für den Fernseher auswählen.", "Hochladen",
           "Wird hochgeladen", "Fertig", "Fehler", "Erst eine Datei auswählen."),
    "en": ("Power-off video", "Choose a video or picture for the TV.", "Upload",
           "Uploading", "Done", "Error", "Choose a file first."),
    "es": ("Vídeo de apagado", "Elige un vídeo o una imagen para el TV.", "Subir",
           "Subiendo", "Listo", "Error", "Primero elige un archivo."),
    "fr": ("Vidéo d'extinction", "Choisis une vidéo ou une image pour le téléviseur.", "Envoyer",
           "Envoi", "Terminé", "Erreur", "Choisis d'abord un fichier."),
}

PAGE = """<!doctype html>
<html lang="{lang}">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>novOS</title>
<h1>{title}</h1>
<p>{intro}</p>
<p><input type="file" id="files" multiple accept="video/mp4,video/quicktime,image/jpeg,image/png"></p>
<p><button id="send">{upload}</button></p>
<p id="status"></p>
<script>
var texts = {texts};
var line = document.getElementById("status");   // not "status": that is window.status
function put(url, body, progress) {{
  return new Promise(function (done, failed) {{
    var request = new XMLHttpRequest();
    request.open("PUT", url);
    if (progress) request.upload.onprogress = progress;
    request.onload = function () {{
      if (request.status === 200) done(JSON.parse(request.responseText));
      else failed(request.responseText || String(request.status));
    }};
    request.onerror = function () {{ failed(""); }};
    request.send(body);
  }});
}}
// A still of the video for the TV's tile, made here because the TV cannot.
function still(file) {{
  return new Promise(function (done) {{
    var video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.preload = "auto";
    video.src = URL.createObjectURL(file);
    video.onloadedmetadata = function () {{ video.currentTime = Math.min(0.5, (video.duration || 1) / 2); }};
    video.onseeked = function () {{
      var canvas = document.createElement("canvas");
      canvas.width = 640;
      canvas.height = 360;
      var scale = Math.max(640 / video.videoWidth, 360 / video.videoHeight);
      var width = video.videoWidth * scale, height = video.videoHeight * scale;
      canvas.getContext("2d").drawImage(video, (640 - width) / 2, (360 - height) / 2, width, height);
      canvas.toBlob(function (blob) {{ done(blob); }}, "image/jpeg", 0.8);
    }};
    video.onerror = function () {{ done(null); }};
    setTimeout(function () {{ done(null); }}, 8000);
  }});
}}
document.getElementById("send").onclick = async function () {{
  var files = document.getElementById("files").files;
  if (!files.length) {{ line.textContent = texts.choose; return; }}
  for (var i = 0; i < files.length; i++) {{
    var file = files[i];
    try {{
      var answer = await put("{base}/file?name=" + encodeURIComponent(file.name), file, function (event) {{
        line.textContent = texts.busy + " " + file.name + " " +
          Math.round(100 * event.loaded / (event.total || 1)) + " %";
      }});
      if (answer.kind === "video") {{
        var blob = await still(file);
        if (blob) await put("{base}/thumb?id=" + answer.id, blob).catch(function () {{}});
      }}
      line.textContent = texts.done + ": " + file.name;
    }} catch (error) {{
      line.textContent = texts.error + ": " + file.name + " " + error;
      return;
    }}
  }}
}};
</script>
</html>
"""

ERRORS = {
    "de": {"type": "Nur MP4, MOV, JPEG oder PNG.", "size": "Größer als 200 MB.",
           "space": "Kein Platz mehr auf dem Fernseher.", "broken": "Übertragung abgebrochen."},
    "en": {"type": "Only MP4, MOV, JPEG or PNG.", "size": "Larger than 200 MB.",
           "space": "No space left on the TV.", "broken": "The transfer broke off."},
    "es": {"type": "Solo MP4, MOV, JPEG o PNG.", "size": "Más de 200 MB.",
           "space": "No queda espacio en el TV.", "broken": "La transferencia se interrumpió."},
    "fr": {"type": "Uniquement MP4, MOV, JPEG ou PNG.", "size": "Plus de 200 Mo.",
           "space": "Plus de place sur le téléviseur.", "broken": "Le transfert a été interrompu."},
}


def language(header):
    for part in (header or "").split(","):
        code = part.strip()[:2].lower()
        if code in TEXTS:
            return code
    return "en"


# ---- The service ----------------------------------------------------------------------

class Service:
    def __init__(self, folder, media, port):
        self.folder = folder
        self.media = media
        self.port = port
        self.lock = threading.Lock()
        self.token = ""
        self.expires = 0.0
        self.serial = ""
        self.url = ""
        self.qr = ""
        self.phase = "waiting"
        self.upload = {}
        self.added = []
        self.error = ""
        self.written = 0.0
        self.revision = 0            # counts the changes of index.json in this run
        self.server = None

    # State for the TV, at most a few times a second while bytes arrive.
    def publish(self, force=True):
        if not force and time.time() - self.written < 0.25:
            return
        self.written = time.time()
        write_json(self.folder + "/state.json", {
            "serving": True, "pid": os.getpid(), "id": self.serial, "phase": self.phase,
            "url": self.url, "qr": self.qr, "expires": int(self.expires), "upload": self.upload,
            "added": self.added, "revision": self.revision, "error": self.error})

    def open(self, serial):
        with self.lock:
            self.serial = serial
            self.expires = time.time() + LIFETIME
            if not self.token:
                # Short enough to type on a computer, without letters that look alike.
                self.token = "".join(random.SystemRandom().choice(CODE_LETTERS) for _ in range(5))
                host = address()
                self.url = "http://%s:%d/%s" % (host, self.port, self.token) if host else ""
                if self.url:
                    self.qr = "%s/qr-%s.png" % (self.folder, self.token)
                    write_png(self.qr, qr_matrix(self.url))
            self.phase = "waiting" if self.url else "error"
            self.error = "" if self.url else "network"
            self.publish()

    def stored(self):
        index = read_json(self.media + "/index.json", {"entries": []})
        if not isinstance(index.get("entries"), list):
            index = {"entries": []}
        return index

    def used(self):
        total = 0
        for name in os.listdir(self.media):
            try:
                total += os.path.getsize(os.path.join(self.media, name))
            except OSError:
                pass
        return total

    def receive(self, handler, name, length):
        """A file from the page. Returns (status, answer)."""
        lang = language(handler.headers.get("Accept-Language"))
        extension = os.path.splitext(name)[1].lower()
        kind = TYPES.get(extension)
        if not kind:
            return 415, ERRORS[lang]["type"]
        if length <= 0 or length > FILE_LIMIT:
            return 413, ERRORS[lang]["size"]
        os.makedirs(self.media, exist_ok=True)
        stat = os.statvfs(self.media)
        if self.used() + length > MEDIA_LIMIT or stat.f_bavail * stat.f_frsize - length < KEEP_FREE:
            return 507, ERRORS[lang]["space"]
        entry_id = "u%x" % int(time.time() * 1000)
        target = os.path.join(self.media, entry_id + extension)
        partial = target + ".partial"
        title = os.path.splitext(os.path.basename(name))[0][:40] or entry_id
        with self.lock:
            self.phase = "receiving"
            self.error = ""
            self.upload = {"name": os.path.basename(name)[:60], "size": length, "received": 0}
            self.expires = max(self.expires, time.time() + 120)
            self.publish()
        received = 0
        try:
            with open(partial, "wb") as file:
                while received < length:
                    block = handler.rfile.read(min(256 * 1024, length - received))
                    if not block:
                        break
                    file.write(block)
                    received += len(block)
                    with self.lock:
                        self.upload["received"] = received
                        self.publish(force=False)
                file.flush()
                os.fsync(file.fileno())
        except OSError:
            pass
        if received < length:
            remove(partial)
            with self.lock:
                self.phase = "error"
                self.error = "broken"
                self.publish()
            return 400, ERRORS[lang]["broken"]
        os.replace(partial, target)
        entry = {"id": entry_id, "kind": kind, "name": title, "file": os.path.basename(target),
                 "size": length, "added": int(time.time())}
        if kind == "video":
            full, sound = video_facts(target)
            entry["full"] = full
            entry["length"] = min(full, PLAY_LIMIT) if full > 0 else PLAY_LIMIT
            entry["sound"] = sound
        else:
            entry["length"] = PICTURE_LENGTH
            entry["sound"] = False
        with self.lock:
            index = self.stored()
            index["entries"].append(entry)
            write_json(self.media + "/index.json", index)
            self.revision += 1
            self.added.append(entry_id)
            self.phase = "done"
            self.upload["received"] = length
            self.publish()
        return 200, {"id": entry_id, "kind": kind}

    def receive_still(self, handler, entry_id, length):
        if length <= 0 or length > THUMB_LIMIT or not entry_id.isalnum():
            return 413, "still"
        with self.lock:
            index = self.stored()
            entry = next((item for item in index["entries"] if item.get("id") == entry_id), None)
        if entry is None:
            return 404, "unknown"
        data = handler.rfile.read(length)
        if len(data) < length or not data.startswith(b"\xff\xd8"):
            return 400, "still"
        write_bytes(os.path.join(self.media, entry_id + "-still.jpg"), data)
        with self.lock:
            index = self.stored()
            for item in index["entries"]:
                if item.get("id") == entry_id:
                    item["still"] = entry_id + "-still.jpg"
            write_json(self.media + "/index.json", index)
            self.revision += 1                   # the TV reloads the tile with its still
            self.publish()
        return 200, {"id": entry_id}

    def handler(self):
        service = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "novOS"
            sys_version = ""

            def log_message(self, *arguments):
                pass

            def valid(self):
                path = urllib.parse.urlparse(self.path)
                parts = path.path.strip("/").split("/")
                if not service.token or parts[0].lower() != service.token or time.time() > service.expires:
                    self.answer(404, "text/plain", b"")
                    return None
                return parts[1:], urllib.parse.parse_qs(path.query)

            def answer(self, status, kind, body):
                self.send_response(status)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                found = self.valid()
                if found is None:
                    return
                if found[0] not in ([], [""]):
                    self.answer(404, "text/plain", b"")
                    return
                lang = language(self.headers.get("Accept-Language"))
                words = TEXTS[lang]
                texts = {"busy": words[3], "done": words[4], "error": words[5], "choose": words[6]}
                page = PAGE.format(lang=lang, title=html.escape(words[0]), intro=html.escape(words[1]),
                                   upload=html.escape(words[2]), texts=json.dumps(texts),
                                   base="/" + service.token)
                self.answer(200, "text/html; charset=utf-8", page.encode("utf-8"))

            def do_PUT(self):
                found = self.valid()
                if found is None:
                    return
                parts, query = found
                try:
                    length = int(self.headers.get("Content-Length") or 0)
                except ValueError:
                    length = 0
                if parts == ["file"]:
                    status, result = service.receive(self, (query.get("name") or ["file"])[0], length)
                elif parts == ["thumb"]:
                    status, result = service.receive_still(self, (query.get("id") or [""])[0], length)
                else:
                    status, result = 404, ""
                if status == 200:
                    self.answer(200, "application/json", json.dumps(result).encode("utf-8"))
                else:
                    self.close_connection = True
                    self.answer(status, "text/plain; charset=utf-8", str(result).encode("utf-8"))

        return Handler

    def run(self):
        os.makedirs(self.folder, exist_ok=True)
        self.server = ThreadingHTTPServer(("0.0.0.0", self.port), self.handler())
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        handled = ""
        try:
            while True:
                command = read_ini(self.folder + "/command.ini")
                serial = command.get("serial", "")
                if serial and serial != handled:
                    handled = serial
                    if command.get("command") == "close":
                        self.phase = "closed"
                        break
                    if command.get("command") == "open":
                        self.open(serial)
                if self.expires and time.time() > self.expires and self.phase != "receiving":
                    self.phase = "expired"
                    break
                time.sleep(0.3)
        finally:
            self.server.shutdown()
            if self.qr:
                remove(self.qr)
            write_json(self.folder + "/state.json", {
                "serving": False, "id": self.serial, "phase": self.phase, "added": self.added,
                "revision": self.revision})


def remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def main():
    arguments = sys.argv[1:]
    if arguments[:1] == ["qr"] and len(arguments) == 3:
        write_png(arguments[2], qr_matrix(arguments[1]))
        return
    if arguments[:1] != ["serve"]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    options = dict(zip(arguments[1::2], arguments[2::2]))
    service = Service(options.get("--folder", FOLDER), options.get("--media", MEDIA),
                      int(options.get("--port", PORT)))
    service.run()


if __name__ == "__main__":
    main()
