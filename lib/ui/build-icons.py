#!/usr/bin/env python3
"""Renders lib/ui's icons, edge lights and shadows to PNG with headless Chrome.

Lists of up to 30 rows show these icons. Canvas icons would repaint on the UI thread
for each of them, so these are plain images that share one texture per icon.

An app renders its own icons with the same helpers and render() from its own script,
see apps/novos/module/build-icons.py.

    python3 lib/ui/build-icons.py [name-prefix ...]
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
EXTERNAL = ["M9 6h9v9", "M18 6L7 17"]


def path(data, opacity=1):
    return f'<path d="{data}" opacity="{opacity}"/>'


def strokes(paths):
    return "".join(path(d) for d in paths)


LOCK = '<rect x="5" y="11" width="14" height="9" rx="2"/>' + path("M8 11V8a4 4 0 0 1 8 0v3")
ALERT_BODY = '<circle cx="12" cy="12" r="9"/>' + "".join(path(d) for d in ALERT)
ALERT_LARGE = '<circle cx="12" cy="12" r="8.5"/>' + "".join(path(d) for d in ALERT)


# name, size, stroke width, body, [(suffix, colour)]
BOTH = [("", LIGHT), ("-dark", DARK)]
LIGHT_ONLY = [("", LIGHT)]
ICONS = [
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
    ("chevron-18", 18, 2.4, strokes(CHEVRON), [("", "rgba(255,255,255,0.50)"), ("-dark", LOCK_DARK)]),
    ("choice-18", 18, 2.4, strokes(CHECK), [("", "rgba(255,255,255,0.50)"), ("-dark", LOCK_DARK)]),
    ("alert-20", 20, 2, ALERT_BODY, [("", ERROR)]),
    ("alert-44", 44, 1.5, ALERT_LARGE, LIGHT_ONLY),
    ("refresh-44", 44, 1.5, strokes(REFRESH), LIGHT_ONLY),
    ("spinner-44", 44, 2.18, path("M4.3 4.3a10.9 10.9 0 0 1 15.4 0"), BOTH),
    ("notice-info", 34, 1.5, '<circle cx="12" cy="12" r="8.5"/>' + path("M12 16.2v-5M12 7.8v0.1"), LIGHT_ONLY),
    ("notice-update", 34, 1.5, strokes(REFRESH), LIGHT_ONLY),
    ("minus-28", 28, 2, strokes(["M5 12h14"]), BOTH),
    ("plus-28", 28, 2, strokes(PLUS), BOTH),
    ("external-18", 18, 2.4, strokes(EXTERNAL), [("", "rgba(255,255,255,0.50)"), ("-dark", LOCK_DARK)]),
    # Status marks of check and progress lists (StatusMark) and the badge of OptionCard.
    ("refresh-18", 18, 2.2, strokes(REFRESH), LIGHT_ONLY),
    ("check-20", 20, 2.6, strokes(CHECK), BOTH),
    # Symbols of StatusCard, 32 px in a 64 px circle (K3-NovUpdate-*).
    ("status-check-32", 32, 2.6, strokes(["M6.5 12.5l3.5 3.5 7.5-8"]), LIGHT_ONLY),
    ("status-download-32", 32, 2.2, strokes(["M12 4v11", "M7.5 10.5L12 15l4.5-4.5", "M5 19.5h14"]), LIGHT_ONLY),
    ("status-alert-32", 32, 2.2, '<circle cx="12" cy="12" r="9"/>' + strokes(["M12 8v5", "M12 16.5v0.1"]),
     [("", ERROR)]),
    ("status-history-32", 32, 2, strokes(["M4.5 12a7.5 7.5 0 1 0 2.2-5.3", "M4.5 4.5v3.5H8", "M12 8v4.2l2.8 1.8"]),
     LIGHT_ONLY),
]


GLASS_EDGE = "inset 0 1px 0 rgba(170,178,196,0.40), inset 0 0 0 1px rgba(170,178,196,0.10)"
FIELD_EDGE = "inset 0 1px 2px rgba(0,0,0,0.25), inset 0 0 0 1px rgba(255,255,255,0.16)"
EDGES = [(f"edge-{radius}", radius, GLASS_EDGE) for radius in (16, 17, 18, 20, 22, 26, 28, 30, 32, 34, 36, 44, 48)]
EDGES.append(("edge-field-26", 26, FIELD_EDGE))


SHADOW_BOX = 400
SHADOW_MARGIN = 180
SHADOWS = [("shadow-panel", 30, 80, 0.35), ("shadow-modal", 40, 100, 0.45)]


def screenshot(page, width, height, folder):
    source = pathlib.Path(folder) / "sheet.html"
    sheet = pathlib.Path(folder) / "sheet.png"
    source.write_text(page)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--default-background-color=00000000",
                    f"--user-data-dir={folder}/profile", f"--window-size={width},{height}",
                    f"--screenshot={sheet}", source.as_uri()],
                   check=True, capture_output=True)
    return Image.open(sheet).convert("RGBA")


def render_shadows(shadows, output):
    side = SHADOW_BOX + 2 * SHADOW_MARGIN
    for name, offset, blur, alpha in shadows:
        page = ('<!doctype html><body style="margin:0;background:transparent">'
                f'<div style="position:absolute;left:{SHADOW_MARGIN}px;top:{SHADOW_MARGIN}px;'
                f'width:{SHADOW_BOX}px;height:{SHADOW_BOX}px;border-radius:48px;'
                f'box-shadow:0 {offset}px {blur}px rgba(0,0,0,{alpha})"></div></body>')
        with tempfile.TemporaryDirectory() as folder:
            screenshot(page, side, side, folder).save(output / f"{name}.png", optimize=True)


def render(icons, output, prefixes=(), edges=(), shadows=()):
    """Writes every icon, edge and shadow to output; with name prefixes only those."""
    def wanted(name):
        return not prefixes or any(name.startswith(prefix) for prefix in prefixes)

    entries = [(name + suffix, size, width, body, colour)
               for name, size, width, body, variants in icons
               for suffix, colour in variants]
    icon_count = len(entries)
    rows = (icon_count + len(edges) + COLUMNS - 1) // COLUMNS
    cells = []
    for index, (_, size, width, body, colour) in enumerate(entries):
        left = (index % COLUMNS) * CELL
        top = (index // COLUMNS) * CELL
        cells.append(
            f'<svg style="position:absolute;left:{left}px;top:{top}px;color:{html.escape(colour)}" '
            f'width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">{body}</svg>')
    for index, (_, radius, shadow) in enumerate(edges, icon_count):
        left = (index % COLUMNS) * CELL
        top = (index // COLUMNS) * CELL
        side = 2 * radius + 3
        cells.append(f'<div style="position:absolute;left:{left}px;top:{top}px;width:{side}px;'
                     f'height:{side}px;border-radius:{radius}px;box-shadow:{shadow}"></div>')
    page = ('<!doctype html><body style="margin:0;background:transparent">' +
            "".join(cells) + "</body>")

    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        image = screenshot(page, COLUMNS * CELL, rows * CELL, folder)
        for index, (name, size, *_rest) in enumerate(entries):
            left = (index % COLUMNS) * CELL
            top = (index // COLUMNS) * CELL
            if wanted(name):
                image.crop((left, top, left + size, top + size)).save(output / f"{name}.png", optimize=True)
        for index, (name, radius, _) in enumerate(edges, icon_count):
            left = (index % COLUMNS) * CELL
            top = (index // COLUMNS) * CELL
            side = 2 * radius + 3
            if wanted(name):
                image.crop((left, top, left + side, top + side)).save(output / f"{name}.png", optimize=True)
    if not prefixes and shadows:
        render_shadows(shadows, output)
    print(f"{len(entries)} icons, {len(edges)} edges and {len(shadows)} shadows in {output}")


if __name__ == "__main__":
    import sys
    render(ICONS, OUTPUT, tuple(sys.argv[1:]), EDGES, SHADOWS)
