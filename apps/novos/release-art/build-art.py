#!/usr/bin/env python3
"""Renders the pictures of "Neu in novOS" (K3-Neu-*) to PNG with headless Chrome.

Every picture is 1012 × 300 with 34 px corners and stands on the horizon of the website:
    release-art/hero.png              the horizon alone; the window draws the version and
                                      the slowly pulsing sun (release-art/sun.png) on it
    release-art/<version>/<name>.png  a motif of one novelty of that release, sun included,
                                      from src/<version>/<name>.inc

A release names its pictures in apps/novos/release-notes.json ("image" of the release or of
an item); build-release.sh refuses a release whose pictures are missing. The PNGs go into the
signed archive, so the TV shows them without a download.

    python3 apps/novos/release-art/build-art.py
"""
import importlib.util
import pathlib
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SOURCES = HERE / "src"
_SPEC = importlib.util.spec_from_file_location("ui_icons", HERE.parents[2] / "lib" / "ui" / "build-icons.py")
ui = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(ui)

WIDTH, HEIGHT = 1012, 300
FONTS = HERE.parents[2] / "lib" / "ui" / "fonts"
# The word mark in a motif uses novOS' own cuts of Inter, as on the TV.
PAGE = ('<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent}'
        '@font-face{font-family:NovTitle;src:url(%s)}@font-face{font-family:NovValue;src:url(%s)}'
        '</style></head><body><div style="position:relative;width:1012px;height:300px">%%s</div></body></html>'
        % ((FONTS / "novos-inter-title.ttf").as_uri(), (FONTS / "novos-inter-value.ttf").as_uri()))


def frame(sun, motif):
    text = (SOURCES / "frame.inc").read_text()
    return text.replace("@SUN@", sun).replace("@MOTIF@", motif)


def render(html, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        image = ui.screenshot(PAGE % html, WIDTH, HEIGHT, folder)
        image.crop((0, 0, WIDTH, HEIGHT)).save(target, optimize=True)
    print(target.relative_to(HERE))


def main():
    sun = (SOURCES / "sun.inc").read_text()
    render(frame("", ""), HERE / "hero.png")
    render(sun, HERE / "sun.png")
    for motif in sorted(SOURCES.glob("*/*.inc")):
        render(frame(sun, motif.read_text()), HERE / motif.parent.name / (motif.stem + ".png"))


if __name__ == "__main__":
    main()
