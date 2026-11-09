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

# Every language of the interface: Basic Latin, Latin-1 Supplement and Latin Extended-A
# (German, English, Spanish, French and their neighbours), plus typographic quotes,
# dashes, bullet, ellipsis, angle quotes, euro, trademark, arrows and minus.
# check() fails the build if a text in an i18n file or the release notes needs a character
# beyond these.
UNICODES = list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) + [
    0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E, 0x2022, 0x2026,
    0x2039, 0x203A, 0x20AC, 0x2122, 0x2190, 0x2191, 0x2192, 0x2193, 0x2212,
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


def check() -> None:
    """Every character of every text novOS ships must be in the fonts."""
    core = HERE.parents[2]
    covered = set(map(chr, UNICODES)) | {"\n", "\t"}
    # The release notes too: novOS shows them in its update pages.
    for path in sorted(core.glob("**/i18n/**/*.json")) + sorted(core.glob("apps/*/release-notes.json")):
        missing = sorted(set(path.read_text(encoding="utf-8")) - covered)
        if missing:
            raise SystemExit("%s needs %s" % (path.relative_to(core), " ".join("U+%04X" % ord(c) for c in missing)))


def main() -> None:
    check()
    OUTPUT.mkdir(exist_ok=True)
    for _role, family, filename, optical_size, weight in CUTS:
        print(build(family, filename, optical_size, weight))


if __name__ == "__main__":
    main()
