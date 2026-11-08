#!/usr/bin/env python3
"""Renders the setup's own icons to PNG with headless Chrome, with lib/ui's helpers.

These are the pictures of the setup's cards and lists (K3-Install-*, K3-Update-*,
K3-Entfernen-*): 24 px drawings with a 1.7 px line, white, at the sizes the boards
use. The shared icons come from lib/ui/build-icons.py; stage.py merges both folders.

    python3 apps/setup/module/build-icons.py [name-prefix ...]
"""
import importlib.util
import pathlib

_SPEC = importlib.util.spec_from_file_location(
    "ui_icons", pathlib.Path(__file__).resolve().parents[3] / "lib/ui/build-icons.py")
ui = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(ui)
path, strokes, render = ui.path, ui.strokes, ui.render
LIGHT_ONLY, LOCK = ui.LIGHT_ONLY, ui.LOCK

OUTPUT = pathlib.Path(__file__).parent / "icons"

HOME = strokes(["M4 11l8-6.5 8 6.5", "M6 10v9.5h12V10"])
APPS = "".join(f'<rect x="{x}" y="{y}" width="6.5" height="6.5" rx="1.8"/>' for y in (4, 13.5) for x in (4, 13.5))
REFRESH = strokes(ui.REFRESH)
SLIDERS = (path("M4 7h10M18 7h2M4 17h4M12 17h8") + '<circle cx="16" cy="7" r="2"/>' +
           '<circle cx="10" cy="17" r="2"/>')
SUN = ('<circle cx="12" cy="12" r="3"/>' +
       path("M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7"
            "M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"))
BELL = path("M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 1.5h-15z") + path("M10 20.5h4")
INPUT = path("M4 8h16v5l-2 3H6l-2-3z") + path("M8 11h8")
MONITOR = '<rect x="3" y="4.5" width="18" height="12" rx="2.5"/>' + path("M9 20h6")
GAMEPAD = (path("M7.2 7.5h9.6a4.2 4.2 0 0 1 4.05 3.08l1.05 3.85a2.7 2.7 0 0 1-4.6 2.55L15.6 15H8.4l-1.7 2"
                "a2.7 2.7 0 0 1-4.6-2.55l1.05-3.85A4.2 4.2 0 0 1 7.2 7.5z") +
           path("M7.5 10v3.2M5.9 11.6h3.2") +
           '<circle cx="15.9" cy="10.9" r="0.95" fill="currentColor" stroke="none"/>'
           '<circle cx="17.7" cy="12.6" r="0.95" fill="currentColor" stroke="none"/>')
SEARCH = '<circle cx="10.5" cy="10.5" r="6"/>' + path("M15 15l5 5")
SPARKLE = path("M12 3.5l1.8 5.2 5.2 1.8-5.2 1.8L12 17.5l-1.8-5.2L5 10.5l5.2-1.8z")

# name, size, stroke width, body, [(suffix, colour)]
ICONS = [
    # Cards of the welcome screen (K3-Install-1).
    ("setup-home-36", 36, 1.7, HOME, LIGHT_ONLY),
    ("setup-apps-36", 36, 1.7, APPS, LIGHT_ONLY),
    ("setup-refresh-36", 36, 1.7, REFRESH, LIGHT_ONLY),
    # Lists of what changes and what stays (K3-Install-3, K3-Entfernen-2).
    ("setup-home-28", 28, 1.7, HOME, LIGHT_ONLY),
    ("setup-sliders-28", 28, 1.7, SLIDERS, LIGHT_ONLY),
    ("setup-sun-28", 28, 1.7, SUN, LIGHT_ONLY),
    ("setup-bell-28", 28, 1.7, BELL, LIGHT_ONLY),
    ("setup-apps-28", 28, 1.7, APPS, LIGHT_ONLY),
    ("setup-input-28", 28, 1.7, INPUT, LIGHT_ONLY),
    ("setup-monitor-28", 28, 1.7, MONITOR, LIGHT_ONLY),
    ("setup-lock-28", 28, 1.7, LOCK, LIGHT_ONLY),
    # What is new in an update (K3-Update-2).
    ("setup-gamepad-30", 30, 1.7, GAMEPAD, LIGHT_ONLY),
    ("setup-search-30", 30, 1.7, SEARCH, LIGHT_ONLY),
    ("setup-sparkle-30", 30, 1.7, SPARKLE, LIGHT_ONLY),
]


if __name__ == "__main__":
    import sys
    render(ICONS, OUTPUT, tuple(sys.argv[1:]))
