#!/usr/bin/env python3
"""Renders novOS' own icons to PNG with headless Chrome, with lib/ui's helpers.

The shared icons, edge lights and shadows come from lib/ui/build-icons.py. Both
scripts write different names; stage.py merges the two icons/ folders.

    python3 apps/novos/module/build-icons.py [name-prefix ...]
"""
import importlib.util
import pathlib

_SPEC = importlib.util.spec_from_file_location(
    "ui_icons", pathlib.Path(__file__).resolve().parents[3] / "lib/ui/build-icons.py")
ui = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(ui)
path, strokes, render = ui.path, ui.strokes, ui.render
LIGHT, BOTH, LIGHT_ONLY, LOCK = ui.LIGHT, ui.BOTH, ui.LIGHT_ONLY, ui.LOCK

OUTPUT = pathlib.Path(__file__).parent / "icons"

WIFI = ["M3.5 9.5a12 12 0 0 1 17 0", "M6.5 12.8a7.5 7.5 0 0 1 11 0",
        "M9.5 16a3 3 0 0 1 5 0", "M12 19.2v0.1"]
WIFI_OFF = WIFI + ["M4 4l16 16"]
PLAY = '<path d="M8 5.5l11 6.5-11 6.5z" fill="currentColor"/>'
LAN = ["M5 6.5h14v9h-3.5v3h-7v-3H5z", "M9 10.5v2M12 10.5v2M15 10.5v2"]

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


SPEAKER = path("M4 9.5h3.5L12 6v12l-4.5-3.5H4z")
WAVE_NEAR = path("M15.5 9.5a3.5 3.5 0 0 1 0 5")
WAVE_FAR = path("M18 7a7 7 0 0 1 0 10")
MUTED = SPEAKER + path("M16 9.5l5 5M21 9.5l-5 5")
SOUNDBAR = '<rect x="2.5" y="9.5" width="19" height="6" rx="2"/>' + path("M6.5 12.5h0.01M17.5 12.5h0.01")
HEADPHONES = path("M4.5 15v-3a7.5 7.5 0 0 1 15 0v3") + '<rect x="4" y="14" width="4" height="6" rx="1.5"/><rect x="16" y="14" width="4" height="6" rx="1.5"/>'
# Devices of the Bluetooth lists, as the boards draw them.
BT_SPEAKER = '<rect x="6" y="3.5" width="12" height="17" rx="3"/><circle cx="12" cy="14" r="3.2"/>' + path("M12 7.5v0.1")
KEYBOARD = ('<rect x="2.5" y="6.5" width="19" height="11" rx="2.5"/>' +
            path("M6 10h0.1M9 10h0.1M12 10h0.1M15 10h0.1M18 10h0.1M6 13.8h0.1M18 13.8h0.1M8.5 13.8h7"))
MOUSE = '<rect x="6.5" y="3.5" width="11" height="17" rx="5.5"/>' + path("M12 7v3")
BLUETOOTH = path("M7 7.5l10 9-5 4.5v-18l5 4.5-10 9")



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


# name, size, stroke width, body, [(suffix, colour)]
ICONS = [
    ("wifi-32", 32, 1.7, strokes(WIFI), LIGHT_ONLY),
    ("wifi-off-32", 32, 1.7, strokes(WIFI_OFF), LIGHT_ONLY),
    ("lan-32", 32, 1.7, strokes(LAN), LIGHT_ONLY),
    ("wifi-36", 36, 1.6, strokes(WIFI), LIGHT_ONLY),
    ("wifi-off-36", 36, 1.6, strokes(WIFI_OFF), LIGHT_ONLY),
    ("wifi-44", 44, 1.5, strokes(WIFI), LIGHT_ONLY),
    ("wifi-off-44", 44, 1.5, strokes(WIFI_OFF), LIGHT_ONLY),
    ("signal-1-30", 30, 2, signal(1), BOTH),
    ("signal-2-30", 30, 2, signal(2), BOTH),
    ("signal-3-30", 30, 2, signal(3), BOTH),
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
    ("screen-off-44", 44, 1.5, SCREEN_OFF, LIGHT_ONLY),
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
    ("notice-headphones", 34, 1.5, path("M4.5 15v-3a7.5 7.5 0 0 1 15 0v3") + '<rect x="4" y="14" width="4" height="6" rx="1.5"/><rect x="16" y="14" width="4" height="6" rx="1.5"/>', LIGHT_ONLY),
    ("notice-usb", 34, 1.5, path("M9 3.5h6v5H9z") + path("M7 8.5h10v7a5 5 0 0 1-10 0z") + path("M11 5.5v1M13 5.5v1"), LIGHT_ONLY),
    ("notice-device", 34, 1.5, PC, LIGHT_ONLY),
    ("notice-moon", 34, 1.5, path("M19.5 14.2A8 8 0 1 1 9.8 4.5a6.4 6.4 0 0 0 9.7 9.7z"), LIGHT_ONLY),
    ("source-alert", 40, 1.5, '<circle cx="12" cy="12" r="8.5"/>' + path("M12 7.8v5M12 16.2v0.1"), BOTH),
    ("row-smartHome", 30, 1.6, HOME, BOTH),
    ("hub-home", 44, 1.5, HOME, LIGHT_ONLY),
    ("volume-0-30", 30, 1.7, SPEAKER, LIGHT_ONLY),
    ("volume-1-30", 30, 1.7, SPEAKER + WAVE_NEAR, LIGHT_ONLY),
    ("volume-2-30", 30, 1.7, SPEAKER + WAVE_NEAR + WAVE_FAR, LIGHT_ONLY),
    ("volume-muted-30", 30, 1.7, MUTED, LIGHT_ONLY),
    ("volume-muted-26", 26, 1.7, MUTED, LIGHT_ONLY),
    ("volume-soundbar-30", 30, 1.7, SOUNDBAR, LIGHT_ONLY),
    ("volume-headphones-30", 30, 1.7, HEADPHONES, LIGHT_ONLY),
    ("row-allSettings", 30, 1.6, dict(SETTINGS_AREAS)["system"], BOTH),
    # Profiles: "Profil hinzufügen" in lists, the area "Profile" of the settings modal.
    ("row-add", 30, 1.6, strokes(["M12 5v14M5 12h14"]), BOTH),
    ("settings-profile", 28, 1.7, '<circle cx="12" cy="8.5" r="3.5"/>' + path("M5 19.5a7 7 0 0 1 14 0"), BOTH),
    # The equalizer rows of the settings modal (K3-Einst-Equalizer): three sliders.
    ("row-equalizer", 30, 1.6, strokes(["M6 4v16M12 4v16M18 4v16"]) +
     '<circle cx="6" cy="14" r="2" fill="currentColor"/><circle cx="12" cy="8" r="2" fill="currentColor"/>'
     '<circle cx="18" cy="15" r="2" fill="currentColor"/>', BOTH),
    # The device lists of the settings (K3-Einst-Geraeteliste, K3-Einst-Bluetooth-Audio,
    # K3-Einst-BT-Eingabegeraete): a symbol per kind of device, the search row, the Bluetooth
    # sign in the head block and the empty hint, the counters of input devices.
    ("row-headphones", 30, 1.7, HEADPHONES, BOTH),
    ("row-speaker", 30, 1.7, BT_SPEAKER, BOTH),
    ("row-soundbar", 30, 1.7, SOUNDBAR, BOTH),
    ("row-keyboard", 30, 1.7, KEYBOARD, BOTH),
    ("row-mouse", 30, 1.7, MOUSE, BOTH),
    ("row-bluetooth", 30, 1.7, BLUETOOTH, BOTH),
    ("row-search", 30, 1.7, '<circle cx="10.5" cy="10.5" r="6"/>' + path("M15 15l5 5"), BOTH),
    ("bluetooth-26", 26, 1.7, BLUETOOTH, LIGHT_ONLY),
    ("bluetooth-32", 32, 1.6, BLUETOOTH, LIGHT_ONLY),
    ("bluetooth-off-32", 32, 1.6, BLUETOOTH + path("M4 4l16 16"), LIGHT_ONLY),
    ("counter-gamepad", 26, 1.7, GAMEPAD, LIGHT_ONLY),
    ("counter-keyboard", 26, 1.7, KEYBOARD, LIGHT_ONLY),
    ("counter-mouse", 26, 1.7, MOUSE, LIGHT_ONLY),
    ("notice-speaker", 34, 1.5, BT_SPEAKER, LIGHT_ONLY),
    ("notice-bluetooth", 34, 1.5, BLUETOOTH, LIGHT_ONLY),
    ("volume-speaker-30", 30, 1.7, BT_SPEAKER, LIGHT_ONLY),
    # Bluetooth und Fernsehlautsprecher, WiSA and WOWCAST (K3-Einst-BT-und-TV, -WiSA-WOWCAST): the
    # head block, the head of a device dialog and the empty hints, the setup with the remote's
    # microphone, the test tone of a speaker.
    ("speaker-26", 26, 1.7, BT_SPEAKER, LIGHT_ONLY),
    ("speaker-32", 32, 1.6, BT_SPEAKER, LIGHT_ONLY),
    ("soundbar-32", 32, 1.6, SOUNDBAR, LIGHT_ONLY),
    ("row-microphone", 30, 1.7, '<rect x="9" y="3.5" width="6" height="11" rx="3"/>' +
     path("M5.5 11a6.5 6.5 0 0 0 13 0") + path("M12 17.5v3"), BOTH),
    ("row-test-tone", 30, 1.7, SPEAKER + WAVE_NEAR + WAVE_FAR, BOTH),
    # The arrows above the level list of the white balance (K3-Einst-Weissabgleich).
    ("chevron-up-20", 20, 2.4, strokes(["M6 15l6-6 6 6"]), [("", LIGHT), ("-dark", "#5b5e66")]),
    ("chevron-down-20", 20, 2.4, strokes(["M6 9l6 6 6-6"]), [("", LIGHT), ("-dark", "#5b5e66")]),
    # The questions of "Hörgerät gleichzeitig" (K3-Einst-Hoergeraet-04 … 08, -17): an ear for
    # the hearing aid, a TV with a signal for the sender on HDMI (ARC).
    ("hearing-44", 44, 1.5, strokes(["M8 15.5c0 2 1.5 3.5 3.5 3.5s3-1.2 3.5-3c.4-1.4 1.2-2.2 2-3a5.5 5.5 0 1 0-9-4.2",
                                     "M10.5 9.5a2 2 0 0 1 4 0c0 1.2-1 1.7-1.6 2.3"]), LIGHT_ONLY),
    ("transmitter-44", 44, 1.5, '<rect x="3" y="4.5" width="13" height="10" rx="2"/>' +
     strokes(["M7 18.5h5", "M18.5 8v8M21 10.5v3"]), LIGHT_ONLY),
    # "Fernbedienung erlernen" (K3-Einst-Fernbedienung): the keys at 80 px, the start icon,
    # the Back key in the legend and the hint.
    ("remote-gear-80", 80, 1.6, '<circle cx="12" cy="12" r="3"/>' +
     strokes(["M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"]),
     LIGHT_ONLY),
    ("remote-home-80", 80, 1.6, strokes(["M4 11l8-6.5 8 6.5", "M6.5 9.5V19h11V9.5"]), LIGHT_ONLY),
    ("remote-input-80", 80, 1.6, '<rect x="3" y="5" width="18" height="14" rx="2.5"/>' +
     strokes(["M8 12h8M13 9l3 3-3 3"]), LIGHT_ONLY),
    ("remote-back-80", 80, 1.6, strokes(["M9 7L4.5 11.5 9 16", "M4.5 11.5H15a4.5 4.5 0 0 1 0 9h-3"]), LIGHT_ONLY),
    ("remote-mute-80", 80, 1.6, strokes(["M4 9.5h3.5L12 5.5v13l-4.5-4H4z", "M16 9.5l5 5M21 9.5l-5 5"]), LIGHT_ONLY),
    ("remote-up-80", 80, 1.6, strokes(["M6 15l6-6 6 6"]), LIGHT_ONLY),
    ("remote-down-80", 80, 1.6, strokes(["M6 9l6 6 6-6"]), LIGHT_ONLY),
    ("remote-left-80", 80, 1.6, strokes(["M15 6l-6 6 6 6"]), LIGHT_ONLY),
    ("remote-right-80", 80, 1.6, strokes(["M9 6l6 6-6 6"]), LIGHT_ONLY),
    ("remote-80", 80, 1.6, '<rect x="7.5" y="2.5" width="9" height="19" rx="3"/>' +
     strokes(["M12 6.5v0.1", "M10 10.5h4M10 13.5h4"]), LIGHT_ONLY),
    ("remote-guide-48", 48, 1.6, strokes(["M4 7h9M17 7h3M4 17h3M11 17h9"]) +
     '<circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>', LIGHT_ONLY),
    ("return-22", 22, 2, strokes(["M9 7L4.5 11.5 9 16", "M4.5 11.5H15a4.5 4.5 0 0 1 0 9h-3"]),
     [("", "rgba(255,255,255,0.82)")]),
    ("return-24", 24, 2, strokes(["M9 7L4.5 11.5 9 16", "M4.5 11.5H15a4.5 4.5 0 0 1 0 9h-3"]), [("-dark", "#0b0c10")]),
    # The preview pill of the shutdown videos.
    ("play-18", 18, 1.8, PLAY, LIGHT_ONLY),
    # Novelties in "Neu in novOS" (K3-Neu-*), 28 px in a 56 px circle; -dark on the focus.
    ("feature-film-28", 28, 1.7, '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/>' +
     path("M7 4.5v15M17 4.5v15M3 9h4M3 15h4M17 9h4M17 15h4"), BOTH),
    ("feature-games-28", 28, 1.7, path("M7.2 7.5h9.6a4.2 4.2 0 0 1 4.05 3.08l1.05 3.85a2.7 2.7 0 0 1-4.6 2.55"
     "L15.6 15H8.4l-1.7 2a2.7 2.7 0 0 1-4.6-2.55l1.05-3.85A4.2 4.2 0 0 1 7.2 7.5z") + path("M7.5 10v3.2M5.9 11.6h3.2") +
     '<circle cx="15.9" cy="10.9" r="0.95" fill="currentColor" stroke="none"/>'
     '<circle cx="17.7" cy="12.6" r="0.95" fill="currentColor" stroke="none"/>', BOTH),
    ("feature-panel-28", 28, 1.7, '<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>' + path("M13 3.5v8h7.5"), BOTH),
    ("feature-sparkle-28", 28, 1.7, path("M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9-1.9 5.1-1.9-5.1-5.1-1.9 5.1-1.9z") +
     path("M18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"), BOTH),
    ("feature-update-28", 28, 1.7, path("M20 12a8 8 0 1 1-2.4-5.7") + path("M20 4v4.5h-4.5"), BOTH),
    # The game bar (K3-Spiel-A-HUD): the genre chip, then the four actions.
    ("game-genre", 30, 1.8, '<circle cx="12" cy="12" r="7"/>' + path("M12 2.5v5M12 16.5v5M2.5 12h5M16.5 12h5"), BOTH),
    ("game-dark-room", 24, 1.8, path("M19.5 14.2A8 8 0 1 1 9.8 4.5a6.4 6.4 0 0 0 9.7 9.7z"), BOTH),
    ("game-multi-view", 24, 1.8, '<rect x="3" y="5" width="8.5" height="14" rx="2"/>'
     '<rect x="12.5" y="5" width="8.5" height="14" rx="2"/>', BOTH),
    ("game-games", 24, 1.8, '<circle cx="12" cy="12" r="3"/>' +
     path("M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"), BOTH),
    ("game-quick", 24, 1.8, MANAGE, BOTH),
] + [(f"settings-{name}", 28, 1.7, body, BOTH) for name, body in SETTINGS_AREAS] + [
    (f"device-{name}", 36, 1.5, body, BOTH) for name, body in DEVICES] + [
    (f"device-{name}-48", 48, 1.5, body, LIGHT_ONLY) for name, body in DEVICES]


# Edge light of the smaller glass controls, as the hand-off's inset shadows. Drawn
# as nine-patches, so that 50 keys stay one batched texture instead of 50 shaders.


if __name__ == "__main__":
    import sys
    render(ICONS, OUTPUT, tuple(sys.argv[1:]))
