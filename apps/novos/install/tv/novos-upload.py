#!/usr/bin/env python3
"""Power-off videos and pictures of the user: upload from a phone or computer, delete, edit.

    novos-upload.py serve [--folder DIR] [--media DIR] [--port N]
    novos-upload.py qr <text> <file.png>          writes a QR code, for tests

The settings leave a command in <folder>/command.ini (SetupBridge); the supervisor starts
this service for it and the service answers in <folder>/state.json.
  open     the page "Vom Handy oder Computer" is open. Serves one plain page under a fresh
           path on the TV's address, http://<ip>:<port>/<code>, shown on the TV as a QR
           code and as text to type (five letters and digits without look-alikes, any
           case). Ends on "close", after ten minutes, or when no command comes for as long.
  delete   removes the entry "target" with its files.
  edit     stores "params" of the entry "target": the part of a video that plays (start,
           length, ms), the fade at its end (fade 1 or 0) and the framing (zoom, x, y), as
           "start:6000 length:8000 fade:1 zoom:1.5 x:0.4 y:-0.2". No JSON: QSettings would
           quote and escape its characters in the ini file.
Delete and edit end the service after their answer unless the page is open.

The TV cannot play video files inside surface-manager: QtMultimedia has no media service
there. The page therefore takes a video apart in the browser, into JPEG frames (15 per
second, at most 1280 x 720, the first 30 seconds) and a WAV track, and the TV plays the
frames with the sound (SoundEffect). Pictures (JPEG, PNG) come as they are.
Everything lands in <media>, one folder per video, with <media>/index.json for the TV
(ShutdownScreens.js). Each file up to 200 MB, all of them together up to 300 MB, and never
below 150 MB free on the data partition.
"""

import binascii
import html
import json
import os
import random
import shutil
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
FPS = 15                          # frames per second of a video
SOURCE_LIMIT = 30000              # ms of a video that the page takes over
PLAY_LIMIT = 15000                # ms of a video that play at power off
PLAY_SHORTEST = 1000
PICTURE_LENGTH = 3000             # ms a picture stays; the user sets it in a later step
ZOOM_LIMIT = 3.0
CODE_LETTERS = "abcdefghjkmnpqrstuvwxyz23456789"
IMAGE_TYPES = {".jpg": "image", ".jpeg": "image", ".png": "image"}


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


# ---- WAV: the part of the sound that plays ----------------------------------------------

def wav_part(source, target, start, length):
    """Writes the PCM of source from start for length (ms) to target, as a WAV of its own."""
    with open(source, "rb") as file:
        data = file.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a WAV file")
    position, fmt, body = 12, None, None
    while position + 8 <= len(data):
        kind, size = data[position:position + 4], struct.unpack("<I", data[position + 4:position + 8])[0]
        if kind == b"fmt ":
            fmt = data[position + 8:position + 8 + size]
        elif kind == b"data":
            body = (position + 8, min(size, len(data) - position - 8))
        position += 8 + size + (size & 1)
    if fmt is None or body is None:
        raise ValueError("WAV without fmt or data")
    channels, rate = struct.unpack("<HI", fmt[2:8])
    align = struct.unpack("<H", fmt[12:14])[0]
    first = int(rate * start / 1000) * align
    count = int(rate * length / 1000) * align
    first = min(first, body[1])
    count = max(0, min(count, body[1] - first))
    pcm = data[body[0] + first:body[0] + first + count]
    header = (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE" + b"fmt " + struct.pack("<I", len(fmt[:16])) +
              fmt[:16] + b"data" + struct.pack("<I", len(pcm)))
    write_bytes(target, header + pcm)


# ---- The page -------------------------------------------------------------------------

TEXTS = {
    "de": {"title": "Ausschalt-Video", "intro": "Video oder Bild für den Fernseher auswählen.", "upload": "Hochladen",
           "prepare": "Wird vorbereitet", "busy": "Wird hochgeladen", "done": "Fertig", "error": "Fehler",
           "choose": "Erst eine Datei auswählen.", "type": "Nur Videos, JPEG oder PNG.", "size": "Größer als 200 MB."},
    "en": {"title": "Power-off video", "intro": "Choose a video or picture for the TV.", "upload": "Upload",
           "prepare": "Preparing", "busy": "Uploading", "done": "Done", "error": "Error",
           "choose": "Choose a file first.", "type": "Only videos, JPEG or PNG.", "size": "Larger than 200 MB."},
    "es": {"title": "Vídeo de apagado", "intro": "Elige un vídeo o una imagen para el TV.", "upload": "Subir",
           "prepare": "Preparando", "busy": "Subiendo", "done": "Listo", "error": "Error",
           "choose": "Primero elige un archivo.", "type": "Solo vídeos, JPEG o PNG.", "size": "Más de 200 MB."},
    "fr": {"title": "Vidéo d'extinction", "intro": "Choisis une vidéo ou une image pour le téléviseur.",
           "upload": "Envoyer", "prepare": "Préparation", "busy": "Envoi", "done": "Terminé", "error": "Erreur",
           "choose": "Choisis d'abord un fichier.", "type": "Uniquement des vidéos, JPEG ou PNG.",
           "size": "Plus de 200 Mo."},
}

ERRORS = {
    "de": {"space": "Kein Platz mehr auf dem Fernseher.", "broken": "Übertragung abgebrochen."},
    "en": {"space": "No space left on the TV.", "broken": "The transfer broke off."},
    "es": {"space": "No queda espacio en el TV.", "broken": "La transferencia se interrumpió."},
    "fr": {"space": "Plus de place sur le téléviseur.", "broken": "Le transfert a été interrompu."},
}

# Plain on purpose: a heading, a sentence, the file picker, one button, one status line.
PAGE = """<!doctype html>
<html lang="{lang}">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>novOS</title>
<h1>{title}</h1>
<p>{intro}</p>
<p><input type="file" id="files" multiple accept="video/*,image/jpeg,image/png"></p>
<p><button id="send">{upload}</button></p>
<p id="status"></p>
<script>
var texts = {texts};
var base = "{base}";
var FPS = {fps}, SOURCE = {source}, LIMIT = {limit};
var line = document.getElementById("status");   // not "status": that is window.status
function show(text) {{ line.textContent = text; }}
function put(path, body, headers) {{
  return new Promise(function (done, failed) {{
    var request = new XMLHttpRequest();
    request.open("PUT", base + path);
    for (var name in headers || {{}}) request.setRequestHeader(name, headers[name]);
    request.onload = function () {{
      if (request.status === 200) done(JSON.parse(request.responseText));
      else failed(request.responseText || String(request.status));
    }};
    request.onerror = function () {{ failed(""); }};
    request.send(body);
  }});
}}
function wait(target, name) {{
  return new Promise(function (done) {{ target.addEventListener(name, done, {{ once: true }}); }});
}}
// 16-bit PCM WAV of a rendered AudioBuffer.
function wav(buffer) {{
  var channels = buffer.numberOfChannels, frames = buffer.length, rate = buffer.sampleRate;
  var bytes = new DataView(new ArrayBuffer(44 + frames * channels * 2));
  function text(at, value) {{ for (var i = 0; i < value.length; i++) bytes.setUint8(at + i, value.charCodeAt(i)); }}
  text(0, "RIFF"); bytes.setUint32(4, 36 + frames * channels * 2, true); text(8, "WAVE"); text(12, "fmt ");
  bytes.setUint32(16, 16, true); bytes.setUint16(20, 1, true); bytes.setUint16(22, channels, true);
  bytes.setUint32(24, rate, true); bytes.setUint32(28, rate * channels * 2, true);
  bytes.setUint16(32, channels * 2, true); bytes.setUint16(34, 16, true); text(36, "data");
  bytes.setUint32(40, frames * channels * 2, true);
  var data = [];
  for (var c = 0; c < channels; c++) data.push(buffer.getChannelData(c));
  var at = 44;
  for (var f = 0; f < frames; f++) {{
    for (var k = 0; k < channels; k++) {{
      var sample = Math.max(-1, Math.min(1, data[k][f]));
      bytes.setInt16(at, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
      at += 2;
    }}
  }}
  return new Blob([bytes], {{ type: "audio/wav" }});
}}
async function sound(file, seconds) {{
  try {{
    var context = new OfflineAudioContext(2, Math.ceil(seconds * 44100), 44100);
    var buffer = await context.decodeAudioData(await file.arrayBuffer());
    var source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    source.start();
    return wav(await context.startRendering());
  }} catch (error) {{
    return null;    // no sound track, or none the browser can read
  }}
}}
// The TV cannot play video files: frames and sound go up instead.
async function sendVideo(file) {{
  show(texts.prepare + " " + file.name);
  var video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.preload = "auto";
  video.src = URL.createObjectURL(file);
  await wait(video, "loadeddata");
  var seconds = Math.min(video.duration || 0, SOURCE / 1000);
  var count = Math.max(1, Math.floor(seconds * FPS));
  var track = await sound(file, seconds);
  var scale = Math.min(1280 / video.videoWidth, 720 / video.videoHeight, 1);
  var canvas = document.createElement("canvas");
  canvas.width = Math.round(video.videoWidth * scale);
  canvas.height = Math.round(video.videoHeight * scale);
  var paint = canvas.getContext("2d");
  var begun = await put("/video?name=" + encodeURIComponent(file.name) + "&frames=" + count + "&full=" +
                        Math.round(seconds * 1000) + "&sound=" + (track ? 1 : 0));
  var batch = [];
  for (var n = 0; n < count; n++) {{
    video.currentTime = Math.max(0.001, n / FPS);
    await wait(video, "seeked");
    paint.drawImage(video, 0, 0, canvas.width, canvas.height);
    batch.push(await new Promise(function (done) {{ canvas.toBlob(done, "image/jpeg", 0.8); }}));
    if (batch.length === FPS || n === count - 1) {{
      await put("/frames?id=" + begun.id + "&from=" + (n + 1 - batch.length), new Blob(batch),
                {{ "X-Sizes": batch.map(function (blob) {{ return blob.size; }}).join(",") }});
      batch = [];
      show(texts.busy + " " + file.name + " " + Math.round(100 * (n + 1) / count) + " %");
    }}
  }}
  if (track) await put("/sound?id=" + begun.id, track);
  await put("/finish?id=" + begun.id);
}}
document.getElementById("send").onclick = async function () {{
  var files = document.getElementById("files").files;
  if (!files.length) {{ show(texts.choose); return; }}
  for (var i = 0; i < files.length; i++) {{
    var file = files[i];
    try {{
      if (file.size > LIMIT) throw texts.size;
      if (/^video\\//.test(file.type) || /\\.(mp4|m4v|mov|webm)$/i.test(file.name)) {{
        await sendVideo(file);
      }} else if (/^image\\/(jpeg|png)$/.test(file.type) || /\\.(jpe?g|png)$/i.test(file.name)) {{
        await put("/image?name=" + encodeURIComponent(file.name), file);
      }} else {{
        throw texts.type;
      }}
      show(texts.done + ": " + file.name);
    }} catch (error) {{
      show(texts.error + ": " + file.name + " " + error);
      return;
    }}
  }}
}};
</script>
</html>
"""


def language(header):
    for part in (header or "").split(","):
        code = part.strip()[:2].lower()
        if code in TEXTS:
            return code
    return "en"


# ---- The service ----------------------------------------------------------------------

class Refused(Exception):
    def __init__(self, status, message):
        Exception.__init__(self, message)
        self.status = status
        self.message = message


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
        self.opened = False          # the page is open; delete and edit alone end the service
        self.phase = "waiting"
        self.upload = {}
        self.added = []
        self.error = ""
        self.written = 0.0
        self.revision = 0            # counts the changes of index.json in this run
        self.receiving = {}          # id -> the entry of a video whose frames come in
        self.server = None

    # State for the TV, at most a few times a second while bytes arrive.
    def publish(self, force=True):
        if not force and time.time() - self.written < 0.25:
            return
        self.written = time.time()
        write_json(self.folder + "/state.json", {
            "serving": self.opened, "pid": os.getpid(), "id": self.serial, "phase": self.phase,
            "url": self.url, "qr": self.qr, "expires": int(self.expires), "upload": self.upload,
            "added": self.added, "revision": self.revision, "error": self.error})

    # ---- The index ----

    def stored(self):
        index = read_json(self.media + "/index.json", {"entries": []})
        if not isinstance(index.get("entries"), list):
            index = {"entries": []}
        return index

    def store(self, index):
        write_json(self.media + "/index.json", index)
        self.revision += 1

    def used(self):
        total = 0
        for top, _, names in os.walk(self.media):
            for name in names:
                try:
                    total += os.path.getsize(os.path.join(top, name))
                except OSError:
                    pass
        return total

    def room_for(self, length, lang):
        os.makedirs(self.media, exist_ok=True)
        stat = os.statvfs(self.media)
        if self.used() + length > MEDIA_LIMIT or stat.f_bavail * stat.f_frsize - length < KEEP_FREE:
            raise Refused(507, ERRORS[lang]["space"])

    def new_id(self):
        time.sleep(0.002)
        return "u%x" % int(time.time() * 1000)

    # ---- Commands of the settings ----

    def open(self, serial):
        with self.lock:
            self.serial = serial
            self.opened = True
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

    def delete(self, serial, target):
        with self.lock:
            index = self.stored()
            entry = next((item for item in index["entries"] if item.get("id") == target), None)
            if entry is not None:
                index["entries"] = [item for item in index["entries"] if item.get("id") != target]
                self.store(index)
                remove_entry_files(self.media, entry)
            self.serial = serial
            self.phase = "done"
            self.publish()

    def edit(self, serial, target, params):
        with self.lock:
            self.serial = serial
            index = self.stored()
            entry = next((item for item in index["entries"] if item.get("id") == target), None)
            if entry is None:
                self.phase = "error"
                self.error = "unknown"
                self.publish()
                return
            number = lambda name, fallback: float(params.get(name, fallback)) if params.get(name) is not None else fallback
            entry["zoom"] = round(min(ZOOM_LIMIT, max(1.0, number("zoom", entry.get("zoom", 1)))), 3)
            entry["x"] = round(min(1.0, max(-1.0, number("x", entry.get("x", 0)))), 3)
            entry["y"] = round(min(1.0, max(-1.0, number("y", entry.get("y", 0)))), 3)
            entry["fade"] = number("fade", 1 if entry.get("fade", True) else 0) != 0
            if entry.get("kind") == "video":
                full = int(entry.get("full") or 0)
                length = int(min(PLAY_LIMIT, full, max(PLAY_SHORTEST, number("length", entry.get("length", PLAY_LIMIT)))))
                start = int(min(max(0, full - length), max(0, number("start", entry.get("start", 0)))))
                entry["start"], entry["length"] = start, length
                folder = os.path.join(self.media, entry["folder"])
                if entry.get("sound") and os.path.exists(os.path.join(folder, "full.wav")):
                    try:
                        wav_part(os.path.join(folder, "full.wav"), os.path.join(folder, "play.wav"), start, length)
                    except (OSError, ValueError, struct.error):
                        entry["sound"] = False
            self.store(index)
            self.phase = "done"
            self.error = ""
            self.publish()

    # ---- What the page sends ----

    def receive_image(self, handler, name, length, lang):
        extension = os.path.splitext(name)[1].lower()
        if extension not in IMAGE_TYPES:
            raise Refused(415, TEXTS[lang]["type"])
        if length <= 0 or length > FILE_LIMIT:
            raise Refused(413, TEXTS[lang]["size"])
        self.room_for(length, lang)
        entry_id = self.new_id()
        target = os.path.join(self.media, entry_id + extension)
        self.started(name, length)
        self.save_body(handler, target, length, lang, counted=True)
        entry = {"id": entry_id, "kind": "image", "name": title_of(name, entry_id), "file": os.path.basename(target),
                 "length": PICTURE_LENGTH, "fade": True, "zoom": 1, "x": 0, "y": 0, "added": int(time.time())}
        self.finished(entry)
        return {"id": entry_id, "kind": "image"}

    def begin_video(self, name, frames, full, sound, lang):
        frames = max(1, min(int(frames), SOURCE_LIMIT * FPS // 1000))
        full = max(1, min(int(full), SOURCE_LIMIT))
        # About 120 kB a frame and the sound track: room is checked before anything comes.
        self.room_for(frames * 120 * 1024 + (full * 44100 * 4 // 1000 if sound else 0), lang)
        entry_id = self.new_id()
        os.makedirs(os.path.join(self.media, entry_id), exist_ok=True)
        with self.lock:
            self.receiving[entry_id] = {"id": entry_id, "kind": "video", "name": title_of(name, entry_id),
                                        "folder": entry_id, "frames": frames, "fps": FPS, "full": full,
                                        "sound": bool(sound), "start": 0, "length": min(PLAY_LIMIT, full),
                                        "fade": True, "zoom": 1, "x": 0, "y": 0, "added": int(time.time())}
            self.phase = "receiving"
            self.error = ""
            self.upload = {"name": os.path.basename(name)[:60], "frames": frames, "done": 0}
            self.expires = max(self.expires, time.time() + 300)
            self.publish()
        return {"id": entry_id}

    def receive_frames(self, handler, entry_id, first, sizes, length, lang):
        entry = self.receiving.get(entry_id)
        if entry is None or sum(sizes) != length or first < 0 or first + len(sizes) > entry["frames"]:
            raise Refused(400, ERRORS[lang]["broken"])
        folder = os.path.join(self.media, entry["folder"])
        for offset, size in enumerate(sizes):
            data = handler.rfile.read(size)
            if len(data) < size or not data.startswith(b"\xff\xd8"):
                raise Refused(400, ERRORS[lang]["broken"])
            write_bytes(os.path.join(folder, "%04d.jpg" % (first + offset)), data)
        with self.lock:
            self.upload["done"] = max(self.upload.get("done", 0), first + len(sizes))
            self.expires = max(self.expires, time.time() + 120)
            self.publish(force=False)
        return {"id": entry_id}

    def receive_sound(self, handler, entry_id, length, lang):
        entry = self.receiving.get(entry_id)
        if entry is None or length <= 0 or length > 16 * 1024 * 1024:
            raise Refused(400, ERRORS[lang]["broken"])
        folder = os.path.join(self.media, entry["folder"])
        self.save_body(handler, os.path.join(folder, "full.wav"), length, lang, counted=False)
        try:
            wav_part(os.path.join(folder, "full.wav"), os.path.join(folder, "play.wav"), 0, entry["length"])
        except (OSError, ValueError, struct.error):
            entry["sound"] = False
        return {"id": entry_id}

    def finish_video(self, entry_id, lang):
        entry = self.receiving.pop(entry_id, None)
        if entry is None:
            raise Refused(400, ERRORS[lang]["broken"])
        folder = os.path.join(self.media, entry["folder"])
        present = len([name for name in os.listdir(folder) if name.endswith(".jpg")])
        if present < entry["frames"]:
            shutil.rmtree(folder, ignore_errors=True)
            with self.lock:
                self.phase, self.error = "error", "broken"
                self.publish()
            raise Refused(400, ERRORS[lang]["broken"])
        if entry["sound"] and not os.path.exists(os.path.join(folder, "play.wav")):
            entry["sound"] = False
        self.finished(entry)
        return {"id": entry_id, "kind": "video"}

    def started(self, name, length):
        with self.lock:
            self.phase = "receiving"
            self.error = ""
            self.upload = {"name": os.path.basename(name)[:60], "size": length, "received": 0}
            self.expires = max(self.expires, time.time() + 120)
            self.publish()

    def save_body(self, handler, target, length, lang, counted):
        partial = target + ".partial"
        received = 0
        try:
            with open(partial, "wb") as file:
                while received < length:
                    block = handler.rfile.read(min(256 * 1024, length - received))
                    if not block:
                        break
                    file.write(block)
                    received += len(block)
                    if counted:
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
                self.phase, self.error = "error", "broken"
                self.publish()
            raise Refused(400, ERRORS[lang]["broken"])
        os.replace(partial, target)

    def finished(self, entry):
        with self.lock:
            index = self.stored()
            index["entries"].append(entry)
            self.store(index)
            self.added.append(entry["id"])
            self.phase = "done"
            self.publish()

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
                if (not service.opened or not service.token or parts[0].lower() != service.token
                        or time.time() > service.expires):
                    self.answer(404, "text/plain", b"")
                    return None
                return parts[1:], {key: values[0] for key, values in urllib.parse.parse_qs(path.query).items()}

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
                page = PAGE.format(lang=lang, title=html.escape(words["title"]), intro=html.escape(words["intro"]),
                                   upload=html.escape(words["upload"]), texts=json.dumps(words),
                                   base="/" + service.token, fps=FPS, source=SOURCE_LIMIT, limit=FILE_LIMIT)
                self.answer(200, "text/html; charset=utf-8", page.encode("utf-8"))

            def do_PUT(self):
                found = self.valid()
                if found is None:
                    return
                parts, query = found
                lang = language(self.headers.get("Accept-Language"))
                try:
                    length = int(self.headers.get("Content-Length") or 0)
                except ValueError:
                    length = 0
                try:
                    if parts == ["image"]:
                        result = service.receive_image(self, query.get("name", "image"), length, lang)
                    elif parts == ["video"]:
                        result = service.begin_video(query.get("name", "video"), int(query.get("frames", 0)),
                                                     int(query.get("full", 0)), query.get("sound") == "1", lang)
                    elif parts == ["frames"]:
                        sizes = [int(size) for size in (self.headers.get("X-Sizes") or "").split(",") if size]
                        result = service.receive_frames(self, query.get("id", ""), int(query.get("from", -1)),
                                                        sizes, length, lang)
                    elif parts == ["sound"]:
                        result = service.receive_sound(self, query.get("id", ""), length, lang)
                    elif parts == ["finish"]:
                        result = service.finish_video(query.get("id", ""), lang)
                    else:
                        raise Refused(404, "")
                except Refused as refused:
                    self.close_connection = True
                    self.answer(refused.status, "text/plain; charset=utf-8", refused.message.encode("utf-8"))
                    return
                except (ValueError, OSError):
                    self.close_connection = True
                    self.answer(400, "text/plain; charset=utf-8", ERRORS[lang]["broken"].encode("utf-8"))
                    return
                self.answer(200, "application/json", json.dumps(result).encode("utf-8"))

        return Handler

    def run(self):
        os.makedirs(self.folder, exist_ok=True)
        os.makedirs(self.media, exist_ok=True)
        self.server = ThreadingHTTPServer(("0.0.0.0", self.port), self.handler())
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        handled = ""
        idle_since = time.time()
        try:
            while True:
                command = read_ini(self.folder + "/command.ini")
                serial = command.get("serial", "")
                if serial and serial != handled:
                    handled = serial
                    idle_since = time.time()
                    name = command.get("command")
                    if name == "close":
                        self.phase = "closed"
                        break
                    if name == "open":
                        self.open(serial)
                    elif name == "delete":
                        self.delete(serial, command.get("target", ""))
                    elif name == "edit":
                        self.edit(serial, command.get("target", ""), edit_params(command.get("params", "")))
                    if not self.opened and name in ("delete", "edit"):
                        return              # answered; the state stays as published
                if self.opened and time.time() > self.expires and self.phase != "receiving":
                    self.phase = "expired"
                    break
                if not self.opened and time.time() - idle_since > 30:
                    break
                time.sleep(0.3)
        finally:
            self.server.shutdown()
            if self.qr:
                remove(self.qr)
            for entry in self.receiving.values():
                shutil.rmtree(os.path.join(self.media, entry["folder"]), ignore_errors=True)
            if self.opened or self.phase not in ("done", "error"):
                self.opened = False
                write_json(self.folder + "/state.json", {
                    "serving": False, "id": self.serial, "phase": self.phase, "added": self.added,
                    "revision": self.revision})


def edit_params(text):
    """"start:6000 length:8000 fade:1" -> {"start": "6000", ...}; anything else is left out."""
    params = {}
    for part in str(text).split():
        name, _, value = part.partition(":")
        if name in ("start", "length", "fade", "zoom", "x", "y"):
            try:
                float(value)
                params[name] = value
            except ValueError:
                pass
    return params


def title_of(name, fallback):
    return os.path.splitext(os.path.basename(name))[0][:40] or fallback


def remove_entry_files(media, entry):
    if entry.get("kind") == "video" and entry.get("folder"):
        shutil.rmtree(os.path.join(media, os.path.basename(entry["folder"])), ignore_errors=True)
    elif entry.get("file"):
        remove(os.path.join(media, os.path.basename(entry["file"])))


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
