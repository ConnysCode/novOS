#!/usr/bin/env python3
"""Renders the Wi-Fi setup icons to PNG with headless Chrome.

The setup shows up to 30 list rows. Canvas icons would repaint on the UI thread
for each of them, so these are plain images that share one texture per icon.
"""
import html
import pathlib
import subprocess
import tempfile

from PIL import Image

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUTPUT = pathlib.Path(__file__).parent / "icons"
CELL = 96
COLUMNS = 8

LIGHT = "#ffffff"
DARK = "#0b0c10"
LOCK_LIGHT = "rgba(255,255,255,0.70)"
LOCK_DARK = "#5b5e66"
ERROR = "#ff9a90"

WIFI = ["M3.5 9.5a12 12 0 0 1 17 0", "M6.5 12.8a7.5 7.5 0 0 1 11 0",
        "M9.5 16a3 3 0 0 1 5 0", "M12 19.2v0.1"]
WIFI_OFF = WIFI + ["M4 4l16 16"]
LAN = ["M5 6.5h14v9h-3.5v3h-7v-3H5z", "M9 10.5v2M12 10.5v2M15 10.5v2"]
PLUS = ["M12 5v14M5 12h14"]
REFRESH = ["M20 12a8 8 0 1 1-2.4-5.7", "M20 4v4.5h-4.5"]
BACK = ["M15 6l-6 6 6 6"]
CHEVRON = ["M9 6l6 6-6 6"]
CHECK = ["M5 12.5l4.5 4.5L19 7.5"]
SHIFT = ["M12 4.5l7.5 7.5h-4.5v6.5H9V12H4.5z"]
# Keyboard modes and T9 keys (K3-Tastatur-T9).
KEYBOARD = ('<rect x="2.5" y="6" width="19" height="12" rx="2.5"/>' +
            '<path d="M6 10h.01M9.3 10h.01M12.6 10h.01M15.9 10h.01M18 10h.01M6 13.5h.01M18 13.5h.01M9 14.5h6"/>')
T9_GRID = "".join(f'<circle cx="{x}" cy="{y}" r="1.6" fill="currentColor"/>' for y in (6, 12, 18) for x in (6, 12, 18))
SPACE = ["M4 10v4h16v-4"]
DELETE = ["M8.5 5.5H20a1.5 1.5 0 0 1 1.5 1.5v10a1.5 1.5 0 0 1-1.5 1.5H8.5L2.5 12z", "M11.5 9.5l5 5M16.5 9.5l-5 5"]
ALERT = ["M12 7.8v5", "M12 16.2v0.1"]


def path(data, opacity=1):
    return f'<path d="{data}" opacity="{opacity}"/>'


def signal(level):
    return (path("M2.6 9.6a13.2 13.2 0 0 1 18.8 0", 1 if level >= 3 else 0.28) +
            path("M5.6 12.8a9 9 0 0 1 12.8 0", 1 if level >= 2 else 0.28) +
            path("M8.6 16a4.8 4.8 0 0 1 6.8 0") + path("M12 19.4v0.1"))


def gear(teeth=8, inner=6.9, outer=9.4, half_base=15, half_tip=9):
    """Outline of a cog around (12, 12): teeth with sloped flanks, arcs between them."""
    import math
    def point(radius, degrees):
        angle = math.radians(degrees - 90)
        return f"{12 + radius * math.cos(angle):.2f} {12 + radius * math.sin(angle):.2f}"
    step = 360 / teeth
    data = "M" + point(inner, -half_base)
    for tooth in range(teeth):
        centre = tooth * step
        data += (f"L{point(outer, centre - half_tip)}A{outer} {outer} 0 0 1 {point(outer, centre + half_tip)}"
                 f"L{point(inner, centre + half_base)}A{inner} {inner} 0 0 1 {point(inner, centre + step - half_base)}")
    return path(data + "z")


SCREEN_OFF = '<rect x="3" y="4.5" width="18" height="12" rx="2.5"/>' + path("M9 20h6") + path("M3.5 3l17 17")
GAMEPAD = (path("M7.2 7.5h9.6a4.2 4.2 0 0 1 4.05 3.08l1.05 3.85a2.7 2.7 0 0 1-4.6 2.55L15.6 15H8.4l-1.7 2a2.7 2.7 0 0 1-4.6-2.55l1.05-3.85A4.2 4.2 0 0 1 7.2 7.5z") +
           path("M7.5 10v3.2M5.9 11.6h3.2") +
           '<circle cx="15.9" cy="10.9" r="0.95" fill="currentColor" stroke="none"/>'
           '<circle cx="17.7" cy="12.6" r="0.95" fill="currentColor" stroke="none"/>')
BOX = '<rect x="3" y="10" width="18" height="8.5" rx="2.6"/>' + path("M8.6 6.6a4.8 4.8 0 0 1 6.8 0")
PC = ('<rect x="2.5" y="5" width="13" height="9.5" rx="1.8"/>' + path("M6.5 19h5M9 14.5V19") +
      '<rect x="17.5" y="5" width="4" height="14" rx="1.2"/>')
HDMI = path("M3.5 8.5h17v4.4l-2.8 3.1H6.3l-2.8-3.1z") + path("M7.5 11.2h9")
DISC = '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.4"/>' + path("M12 6.4a5.6 5.6 0 0 1 5.6 5.6")
AUDIO = ('<rect x="6.5" y="3" width="11" height="18" rx="2.4"/><circle cx="12" cy="14.6" r="3.3"/>' +
         '<circle cx="12" cy="7.2" r="1.1"/>')
SATELLITE = (path("M4.2 9.2a10.6 10.6 0 0 0 10.6 10.6z") + path("M9.5 14.5l4-4") +
             path("M14.2 5.4a4.4 4.4 0 0 1 4.4 4.4") + '<circle cx="14" cy="10" r="0.9"/>')
CAMERA = (path("M4.6 8h2.9l1.6-2.5h5.8L16.5 8h2.9A1.6 1.6 0 0 1 21 9.6v8.2a1.7 1.7 0 0 1-1.7 1.7H4.7A1.7 1.7 0 0 1 3 17.8V9.6A1.6 1.6 0 0 1 4.6 8z") +
          '<circle cx="12" cy="13.4" r="3.4"/>')
MOBILE = '<rect x="7" y="2.8" width="10" height="18.4" rx="2.3"/>' + path("M11 18.2h2")
TV = '<rect x="3" y="8" width="18" height="11.5" rx="2.5"/>' + path("M8.5 4L12 8l3.5-4")
LIBRARY = ('<rect x="3.5" y="7.5" width="17" height="12" rx="2.5"/>' + path("M6.5 4.5h11") +
           path("M10.4 11.1v4.8l4.1-2.4z"))
CAST = ('<rect x="2.5" y="5" width="13.5" height="10" rx="1.8"/>' +
        '<rect x="17" y="9.5" width="5" height="9.5" rx="1.3"/>' + path("M6 19h6"))
MANAGE = (path("M4 7h10M18 7h2M4 17h4M12 17h8") + '<circle cx="16" cy="7" r="2"/>' +
          '<circle cx="10" cy="17" r="2"/>')
ROW_BACKLIGHT = ('<circle cx="12" cy="12" r="4"/>' +
                 path("M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6L7 7M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4"))
ROW_EYE = (path("M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12z") +
           '<circle cx="12" cy="12" r="2.6"/>')
ROW_PICTURE = '<rect x="3" y="4.5" width="18" height="12" rx="2.5"/>' + path("M9 20h6")
ROW_SOUND = "".join(path(d) for d in ["M4 9.5h3.5L12 6v12l-4.5-3.5H4z", "M16 9a4 4 0 0 1 0 6", "M18.5 6.5a7.5 7.5 0 0 1 0 11"])
ROW_SOURCES = ROW_PICTURE + path("M12 7.5v5.5M9.5 10.5L12 13l2.5-2.5")
ROW_ACCOUNTS = '<circle cx="12" cy="8.5" r="3.5"/>' + path("M5 19.5a7 7 0 0 1 14 0")
ROW_APPS = "".join(f'<rect x="{x}" y="{y}" width="6.5" height="6.5" rx="1.8"/>'
                   for x in (4, 13.5) for y in (4, 13.5))
ROW_ACCESS = ('<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="7.8" r="1.1"/>' +
              path("M8 10.5h8M12 10.5v3.5l-2 3.5M12 14l2 3.5"))
ROW_SYSTEM = ('<rect x="6.5" y="6.5" width="11" height="11" rx="2"/>' +
              path("M9.5 3.5v3M14.5 3.5v3M9.5 17.5v3M14.5 17.5v3M3.5 9.5h3M3.5 14.5h3M17.5 9.5h3M17.5 14.5h3"))
LOCK = '<rect x="5" y="11" width="14" height="9" rx="2"/>' + path("M8 11V8a4 4 0 0 1 8 0v3")
ALERT_BODY = '<circle cx="12" cy="12" r="9"/>' + "".join(path(d) for d in ALERT)
ALERT_LARGE = '<circle cx="12" cy="12" r="8.5"/>' + "".join(path(d) for d in ALERT)


SPEAKER = path("M4 9.5h3.5L12 6v12l-4.5-3.5H4z")
WAVE_NEAR = path("M15.5 9.5a3.5 3.5 0 0 1 0 5")
WAVE_FAR = path("M18 7a7 7 0 0 1 0 10")
MUTED = SPEAKER + path("M16 9.5l5 5M21 9.5l-5 5")
SOUNDBAR = '<rect x="2.5" y="9.5" width="19" height="6" rx="2"/>' + path("M6.5 12.5h0.01M17.5 12.5h0.01")
HEADPHONES = path("M4.5 15v-3a7.5 7.5 0 0 1 15 0v3") + '<rect x="4" y="14" width="4" height="6" rx="1.5"/><rect x="16" y="14" width="4" height="6" rx="1.5"/>'


def strokes(paths):
    return "".join(path(d) for d in paths)


# Smart home: devices on the hub's tiles (K3-Home-A). Light, lamp, thermostat and blind
# follow the hand-off; the others are drawn in the same 24 px grid and weight.
HOME = strokes(["M4 11l8-6.5 8 6.5", "M6 9.8V20h12V9.8", "M10 20v-5h4v5"])
DEVICE_LIGHT = strokes(["M9 18h6M10 21h4",
                        "M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2V16h5v-.1c0-.8.4-1.5 1-2A6 6 0 0 0 12 3z"])
DEVICE_LAMP = strokes(["M8 4h8l2 6H6z", "M12 10v10M8 20h8"])
DEVICE_THERMOSTAT = strokes(["M14 14.5V5a2 2 0 0 0-4 0v9.5a4 4 0 1 0 4 0z", "M12 9v7"])
DEVICE_BLIND = '<rect x="4" y="3.5" width="16" height="17" rx="1.5"/>' + path("M4 8h16M4 12h16M4 16h16")
DEVICE_PLUG = strokes(["M9 3.5v4M15 3.5v4", "M6.5 7.5h11V11a5.5 5.5 0 0 1-11 0z", "M12 16.5v4"])
DEVICE_WASHER = ('<rect x="4" y="3" width="16" height="18" rx="2.5"/><circle cx="12" cy="13" r="4.5"/>' +
                 path("M7 6.3h2.5M15.5 6.3h1"))
DEVICE_DRYER = (DEVICE_WASHER.replace(path("M7 6.3h2.5M15.5 6.3h1"), "") +
                path("M7 6.3h2.5M15.5 6.3h1") + path("M10 12.2c1.3-1 2.7 1 4 0"))
DEVICE_FRIDGE = '<rect x="5.5" y="2.5" width="13" height="19" rx="2.5"/>' + path("M5.5 10h13M8.5 5.5v2M8.5 12.5v3")
DEVICE_AC = ('<rect x="2.5" y="5" width="19" height="8" rx="2"/>' + path("M5.5 10.5h13") +
             path("M8 16.5c0 1.5-1 2-1 3.5M12 16.5c0 1.5-1 2-1 3.5M16 16.5c0 1.5-1 2-1 3.5"))
DEVICE_PURIFIER = ('<rect x="6" y="3" width="12" height="18" rx="3"/>' +
                   '<circle cx="12" cy="9.5" r="3"/>' + path("M9 16h6M9 18.5h6"))
DEVICE_FAN = ('<circle cx="12" cy="12" r="1.6"/>' +
              path("M12 10.4c0-3 1-6 3.5-6 2 0 2 3-3.5 6z") + path("M13.6 12c3 0 6 1 6 3.5 0 2-3 2-6-3.5z") +
              path("M12 13.6c0 3-1 6-3.5 6-2 0-2-3 3.5-6z") + path("M10.4 12c-3 0-6-1-6-3.5 0-2 3-2 6 3.5z"))
DEVICE_LOCK = '<rect x="5" y="10.5" width="14" height="10" rx="2"/>' + path("M8 10.5V7.5a4 4 0 0 1 8 0v3M12 14.5v2")
DEVICE_SENSOR = ('<circle cx="12" cy="12" r="2.2"/>' + path("M8.2 8.2a5.4 5.4 0 0 0 0 7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6") +
                 path("M5.4 5.4a9.3 9.3 0 0 0 0 13.2M18.6 5.4a9.3 9.3 0 0 1 0 13.2"))
DEVICE_ROBOT = '<circle cx="12" cy="12.5" r="8.5"/><circle cx="12" cy="12.5" r="2.5"/>' + path("M6.5 8.5h11")
DEVICE_GENERIC = '<rect x="4.5" y="4.5" width="15" height="15" rx="3"/><circle cx="12" cy="12" r="2.5"/>'
DEVICES = [("light", DEVICE_LIGHT), ("lamp", DEVICE_LAMP), ("thermostat", DEVICE_THERMOSTAT),
           ("blind", DEVICE_BLIND), ("plug", DEVICE_PLUG), ("washer", DEVICE_WASHER),
           ("dryer", DEVICE_DRYER), ("fridge", DEVICE_FRIDGE), ("ac", DEVICE_AC),
           ("purifier", DEVICE_PURIFIER), ("fan", DEVICE_FAN), ("lock", DEVICE_LOCK),
           ("sensor", DEVICE_SENSOR), ("robot", DEVICE_ROBOT), ("device", DEVICE_GENERIC)]


# Side bar of the settings modal (K3-Struktur), 28 px with 1.7 like the hand-off.
SETTINGS_AREAS = [
    ("search", '<circle cx="10.5" cy="10.5" r="6"/>' + path("M15 15l5 5")),
    ("picture", '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/>' + path("M3.5 16l5-5 4 4 2.5-2.5 5.5 5.5") +
                '<circle cx="15.5" cy="9" r="1.5"/>'),
    ("sound", SPEAKER + WAVE_NEAR + WAVE_FAR),
    ("sources", path("M4 8h16v5l-2 3H6l-2-3z") + path("M8 11h8")),
    ("games", GAMEPAD),
    ("network", strokes(WIFI)),
    ("interface", '<rect x="3" y="4" width="18" height="13" rx="2.5"/>' + path("M3 13.5h18") + path("M7 20h10") +
                  path("M7 7.5h4")),
    ("energy", path("M19.5 14.2A8 8 0 1 1 9.8 4.5a6.4 6.4 0 0 0 9.7 9.7z")),
    ("accessibility", '<circle cx="12" cy="4.8" r="1.8"/>' + path("M5 8.5l7 1.5 7-1.5") +
                      path("M12 10v4.5l-3 5.5M12 14.5l3 5.5")),
    ("parental", path("M12 3.5l7 3v5c0 4.4-3 7.6-7 9-4-1.4-7-4.6-7-9v-5z") + path("M9 12l2 2 4-4")),
    ("privacy", LOCK),
    # A cog, not rays: with rays it read as the sun of the brightness shortcut beside it.
    ("system", gear() + '<circle cx="12" cy="12" r="3"/>'),
    ("info", '<circle cx="12" cy="12" r="8.5"/>' + path("M12 11v5.2") + path("M12 7.8v0.1")),
]
EXTERNAL = ["M9 6h9v9", "M18 6L7 17"]


# name, size, stroke width, body, [(suffix, colour)]
BOTH = [("", LIGHT), ("-dark", DARK)]
LIGHT_ONLY = [("", LIGHT)]
ICONS = [
    ("wifi-32", 32, 1.7, strokes(WIFI), LIGHT_ONLY),
    ("wifi-off-32", 32, 1.7, strokes(WIFI_OFF), LIGHT_ONLY),
    ("lan-32", 32, 1.7, strokes(LAN), LIGHT_ONLY),
    ("wifi-36", 36, 1.6, strokes(WIFI), LIGHT_ONLY),
    ("wifi-off-36", 36, 1.6, strokes(WIFI_OFF), LIGHT_ONLY),
    ("wifi-44", 44, 1.5, strokes(WIFI), LIGHT_ONLY),
    ("wifi-off-44", 44, 1.5, strokes(WIFI_OFF), LIGHT_ONLY),
    ("check-44", 44, 1.5, strokes(CHECK), LIGHT_ONLY),
    ("back-26", 26, 2.4, strokes(BACK), LIGHT_ONLY),
    # Back link of a page header, in the colour of secondary text (GlassStyle.textSecondary).
    ("back-18", 18, 2.4, strokes(BACK), [("", "rgba(255,255,255,0.72)")]),
    ("plus-22", 22, 2, strokes(PLUS), BOTH),
    ("refresh-22", 22, 2, strokes(REFRESH), BOTH),
    ("check-18", 18, 2.6, strokes(CHECK), LIGHT_ONLY),
    ("check-24", 24, 2.4, strokes(CHECK), BOTH),
    ("shift-24", 24, 1.9, strokes(SHIFT), BOTH),
    ("keyboard-24", 24, 1.9, KEYBOARD, BOTH),
    ("t9-22", 22, 1.9, T9_GRID, BOTH),
    ("delete-24", 24, 1.9, strokes(DELETE), BOTH),
    ("space-22", 22, 1.9, strokes(SPACE), [("", "rgba(255,255,255,0.72)"), ("-dark", LOCK_DARK)]),
    ("lock-24", 24, 1.8, LOCK, [("", LOCK_LIGHT), ("-dark", LOCK_DARK)]),
    ("signal-1-30", 30, 2, signal(1), BOTH),
    ("signal-2-30", 30, 2, signal(2), BOTH),
    ("signal-3-30", 30, 2, signal(3), BOTH),
    ("chevron-18", 18, 2.4, strokes(CHEVRON), [("", "rgba(255,255,255,0.50)"), ("-dark", LOCK_DARK)]),
    ("choice-18", 18, 2.4, strokes(CHECK), [("", "rgba(255,255,255,0.50)"), ("-dark", LOCK_DARK)]),
    ("alert-20", 20, 2, ALERT_BODY, [("", ERROR)]),
    ("row-backlight", 30, 1.6, ROW_BACKLIGHT, BOTH),
    ("row-eyeComfort", 30, 1.6, ROW_EYE, BOTH),
    ("row-picture", 30, 1.6, ROW_PICTURE, BOTH),
    ("row-sound", 30, 1.6, ROW_SOUND, BOTH),
    ("row-sources", 30, 1.6, ROW_SOURCES, BOTH),
    ("row-network", 30, 1.6, strokes(WIFI), BOTH),
    ("row-accounts", 30, 1.6, ROW_ACCOUNTS, BOTH),
    ("row-apps", 30, 1.6, ROW_APPS, BOTH),
    ("row-accessibility", 30, 1.6, ROW_ACCESS, BOTH),
    ("row-energy", 30, 1.6, strokes(["M12 4v7", "M7.5 7a7 7 0 1 0 9 0"]), BOTH),
    ("row-system", 30, 1.6, ROW_SYSTEM, BOTH),
    ("row-debug", 30, 1.6, MANAGE, BOTH),
    ("row-source-gamepad", 30, 1.6, GAMEPAD, BOTH),
    ("row-source-box", 30, 1.6, BOX, BOTH),
    ("row-source-pc", 30, 1.6, PC, BOTH),
    ("row-source-hdmi", 30, 1.6, HDMI, BOTH),
    ("row-source-disc", 30, 1.6, DISC, BOTH),
    ("row-source-audio", 30, 1.6, AUDIO, BOTH),
    ("row-source-satellite", 30, 1.6, SATELLITE, BOTH),
    ("row-source-camera", 30, 1.6, CAMERA, BOTH),
    ("row-source-mobile", 30, 1.6, MOBILE, BOTH),
    # Home in the panel's list of inputs.
    ("row-source-home", 30, 1.6, path("M4 11.5L12 5l8 6.5") + path("M6.5 10v9h11v-9"), BOTH),
    ("alert-44", 44, 1.5, ALERT_LARGE, LIGHT_ONLY),
    ("screen-off-44", 44, 1.5, SCREEN_OFF, LIGHT_ONLY),
    ("refresh-44", 44, 1.5, strokes(REFRESH), LIGHT_ONLY),
    ("spinner-44", 44, 2.18, path("M4.3 4.3a10.9 10.9 0 0 1 15.4 0"), BOTH),
    ("source-gamepad", 40, 1.5, GAMEPAD, BOTH),
    ("source-box", 40, 1.5, BOX, BOTH),
    ("source-pc", 40, 1.5, PC, BOTH),
    ("source-hdmi", 40, 1.5, HDMI, BOTH),
    ("source-disc", 40, 1.5, DISC, BOTH),
    ("source-audio", 40, 1.5, AUDIO, BOTH),
    ("source-satellite", 40, 1.5, SATELLITE, BOTH),
    ("source-camera", 40, 1.5, CAMERA, BOTH),
    ("source-mobile", 40, 1.5, MOBILE, BOTH),
    ("source-tv", 40, 1.5, TV, BOTH),
    ("source-library", 40, 1.5, LIBRARY, BOTH),
    ("source-cast", 40, 1.5, CAST, BOTH),
    ("source-manage", 40, 1.5, MANAGE, BOTH),
    # Large icon in the head of a device's detail page.
    ("detail-source-gamepad", 56, 1.3, GAMEPAD, LIGHT_ONLY),
    ("detail-source-box", 56, 1.3, BOX, LIGHT_ONLY),
    ("detail-source-pc", 56, 1.3, PC, LIGHT_ONLY),
    ("detail-source-hdmi", 56, 1.3, HDMI, LIGHT_ONLY),
    ("detail-source-disc", 56, 1.3, DISC, LIGHT_ONLY),
    ("detail-source-audio", 56, 1.3, AUDIO, LIGHT_ONLY),
    ("detail-source-satellite", 56, 1.3, SATELLITE, LIGHT_ONLY),
    ("detail-source-camera", 56, 1.3, CAMERA, LIGHT_ONLY),
    ("detail-source-mobile", 56, 1.3, MOBILE, LIGHT_ONLY),
    ("notice-info", 34, 1.5, '<circle cx="12" cy="12" r="8.5"/>' + path("M12 16.2v-5M12 7.8v0.1"), LIGHT_ONLY),
    ("notice-headphones", 34, 1.5, path("M4.5 15v-3a7.5 7.5 0 0 1 15 0v3") + '<rect x="4" y="14" width="4" height="6" rx="1.5"/><rect x="16" y="14" width="4" height="6" rx="1.5"/>', LIGHT_ONLY),
    ("notice-usb", 34, 1.5, path("M9 3.5h6v5H9z") + path("M7 8.5h10v7a5 5 0 0 1-10 0z") + path("M11 5.5v1M13 5.5v1"), LIGHT_ONLY),
    ("notice-device", 34, 1.5, PC, LIGHT_ONLY),
    ("notice-update", 34, 1.5, strokes(REFRESH), LIGHT_ONLY),
    ("notice-moon", 34, 1.5, path("M19.5 14.2A8 8 0 1 1 9.8 4.5a6.4 6.4 0 0 0 9.7 9.7z"), LIGHT_ONLY),
    ("source-alert", 40, 1.5, '<circle cx="12" cy="12" r="8.5"/>' + path("M12 7.8v5M12 16.2v0.1"), BOTH),
    ("row-smartHome", 30, 1.6, HOME, BOTH),
    ("hub-home", 44, 1.5, HOME, LIGHT_ONLY),
    ("minus-28", 28, 2, strokes(["M5 12h14"]), BOTH),
    ("plus-28", 28, 2, strokes(PLUS), BOTH),
    ("volume-0-30", 30, 1.7, SPEAKER, LIGHT_ONLY),
    ("volume-1-30", 30, 1.7, SPEAKER + WAVE_NEAR, LIGHT_ONLY),
    ("volume-2-30", 30, 1.7, SPEAKER + WAVE_NEAR + WAVE_FAR, LIGHT_ONLY),
    ("volume-muted-30", 30, 1.7, MUTED, LIGHT_ONLY),
    ("volume-muted-26", 26, 1.7, MUTED, LIGHT_ONLY),
    ("volume-soundbar-30", 30, 1.7, SOUNDBAR, LIGHT_ONLY),
    ("volume-headphones-30", 30, 1.7, HEADPHONES, LIGHT_ONLY),
    ("external-18", 18, 2.4, strokes(EXTERNAL), [("", "rgba(255,255,255,0.50)"), ("-dark", LOCK_DARK)]),
    ("row-allSettings", 30, 1.6, dict(SETTINGS_AREAS)["system"], BOTH),
] + [(f"settings-{name}", 28, 1.7, body, BOTH) for name, body in SETTINGS_AREAS] + [
    (f"device-{name}", 36, 1.5, body, BOTH) for name, body in DEVICES] + [
    (f"device-{name}-48", 48, 1.5, body, LIGHT_ONLY) for name, body in DEVICES]


# Edge light of the smaller glass controls, as the hand-off's inset shadows. Drawn
# as nine-patches, so that 50 keys stay one batched texture instead of 50 shaders.
GLASS_EDGE = "inset 0 1px 0 rgba(170,178,196,0.40), inset 0 0 0 1px rgba(170,178,196,0.10)"
FIELD_EDGE = "inset 0 1px 2px rgba(0,0,0,0.25), inset 0 0 0 1px rgba(255,255,255,0.16)"
EDGES = [(f"edge-{radius}", radius, GLASS_EDGE) for radius in (16, 17, 20, 22, 26, 28, 32, 34, 36, 44)]
EDGES.append(("edge-field-26", 26, FIELD_EDGE))


# Soft outer shadows as nine-patches. The CSS shadow only exists outside the box, and a
# texture costs a fraction of the per-pixel erf shader on this GPU.
SHADOW_BOX = 400
SHADOW_MARGIN = 180
SHADOWS = [("shadow-panel", 30, 80, 0.35), ("shadow-modal", 40, 100, 0.45)]


def render_shadows():
    side = SHADOW_BOX + 2 * SHADOW_MARGIN
    for name, offset, blur, alpha in SHADOWS:
        page = ('<!doctype html><body style="margin:0;background:transparent">'
                f'<div style="position:absolute;left:{SHADOW_MARGIN}px;top:{SHADOW_MARGIN}px;'
                f'width:{SHADOW_BOX}px;height:{SHADOW_BOX}px;border-radius:48px;'
                f'box-shadow:0 {offset}px {blur}px rgba(0,0,0,{alpha})"></div></body>')
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "shadow.html"
            sheet = pathlib.Path(folder) / "shadow.png"
            source.write_text(page)
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            "--force-device-scale-factor=1", "--default-background-color=00000000",
                            f"--user-data-dir={folder}/profile", f"--window-size={side},{side}",
                            f"--screenshot={sheet}", source.as_uri()],
                           check=True, capture_output=True)
            Image.open(sheet).convert("RGBA").save(OUTPUT / f"{name}.png", optimize=True)


def main(prefixes=()):
    """Without arguments every file is written anew; with name prefixes only those."""
    def wanted(name):
        return not prefixes or any(name.startswith(prefix) for prefix in prefixes)

    entries = [(name + suffix, size, width, body, colour)
               for name, size, width, body, variants in ICONS
               for suffix, colour in variants]
    icon_count = len(entries)
    rows = (icon_count + len(EDGES) + COLUMNS - 1) // COLUMNS
    cells = []
    for index, (_, size, width, body, colour) in enumerate(entries):
        left = (index % COLUMNS) * CELL
        top = (index // COLUMNS) * CELL
        cells.append(
            f'<svg style="position:absolute;left:{left}px;top:{top}px;color:{html.escape(colour)}" '
            f'width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">{body}</svg>')
    for index, (_, radius, shadow) in enumerate(EDGES, icon_count):
        left = (index % COLUMNS) * CELL
        top = (index // COLUMNS) * CELL
        side = 2 * radius + 3
        cells.append(f'<div style="position:absolute;left:{left}px;top:{top}px;width:{side}px;'
                     f'height:{side}px;border-radius:{radius}px;box-shadow:{shadow}"></div>')
    page = ('<!doctype html><body style="margin:0;background:transparent">' +
            "".join(cells) + "</body>")

    OUTPUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        source = pathlib.Path(folder) / "icons.html"
        sheet = pathlib.Path(folder) / "icons.png"
        source.write_text(page)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--default-background-color=00000000",
                        f"--user-data-dir={folder}/profile",
                        f"--window-size={COLUMNS * CELL},{rows * CELL}",
                        f"--screenshot={sheet}", source.as_uri()],
                       check=True, capture_output=True)
        image = Image.open(sheet).convert("RGBA")
        for index, (name, size, *_rest) in enumerate(entries):
            left = (index % COLUMNS) * CELL
            top = (index // COLUMNS) * CELL
            if wanted(name):
                image.crop((left, top, left + size, top + size)).save(OUTPUT / f"{name}.png", optimize=True)
        for index, (name, radius, _) in enumerate(EDGES, icon_count):
            left = (index % COLUMNS) * CELL
            top = (index // COLUMNS) * CELL
            side = 2 * radius + 3
            if wanted(name):
                image.crop((left, top, left + side, top + side)).save(OUTPUT / f"{name}.png", optimize=True)
    if not prefixes:
        render_shadows()
    print(f"{len(entries)} icons, {len(EDGES)} edges and {len(SHADOWS)} shadows in {OUTPUT}")


if __name__ == "__main__":
    import sys
    main(tuple(sys.argv[1:]))
