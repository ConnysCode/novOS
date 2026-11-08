#!/usr/bin/env python3
"""Create the static Inter cuts for the Quick Settings panel.

Qt 5.12 on the TV draws a variable font only at its default instance, so the
spec's weights 500 and 700 never reach the screen. Each role therefore gets its
own static file, cut at the optical size CSS would pick for that font size.

Requires fonttools: python3 -m pip install fonttools
"""

from __future__ import annotations

from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "inter-variable.ttf"
OUTPUT = HERE

# Role, family name, file, optical size (px), weight.
CUTS = (
    ("title", "novOS Inter Title", "novos-inter-title.ttf", 32, 700),
    ("row", "novOS Inter Row", "novos-inter-row.ttf", 22, 500),
    ("value", "novOS Inter Value", "novos-inter-value.ttf", 18, 400),
)

# German UI text plus the punctuation the panel can show.
UNICODES = list(range(0x20, 0x7F)) + [
    0xA0, 0xB7, 0xC4, 0xD6, 0xDC, 0xDF, 0xE4, 0xF6, 0xFC,
    0x2013, 0x2014, 0x2026, 0x2212,
]


def rename(font: TTFont, family: str) -> None:
    postscript = family.replace(" ", "")
    values = {
        1: family,
        2: "Regular",
        3: f"{postscript}-novos",
        4: family,
        6: postscript,
        16: family,
        17: "Regular",
    }
    names = font["name"]
    for record in list(names.names):
        if record.nameID in values:
            names.setName(
                values[record.nameID],
                record.nameID,
                record.platformID,
                record.platEncID,
                record.langID,
            )


def build(family: str, filename: str, optical_size: int, weight: int) -> Path:
    font = TTFont(SOURCE)
    font = instancer.instantiateVariableFont(
        font, {"opsz": optical_size, "wght": weight}
    )

    options = subset.Options()
    options.layout_features = ["kern", "calt", "ccmp", "locl", "mark", "mkmk", "tnum"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=UNICODES)
    subsetter.subset(font)

    # Keep the regular style bits: each file is its own family and Qt must not
    # embolden it a second time.
    font["OS/2"].usWeightClass = 400
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0x21) | 0x40
    font["head"].macStyle = 0
    rename(font, family)

    target = OUTPUT / filename
    font.save(target)
    return target


def main() -> None:
    OUTPUT.mkdir(exist_ok=True)
    for _role, family, filename, optical_size, weight in CUTS:
        print(build(family, filename, optical_size, weight))


if __name__ == "__main__":
    main()
