#!/usr/bin/env python3
"""Checks apps/novos/release-notes.json against what the release ships.

Every release names its date, its level (patch: only the notice after the update; minor
or major: the "Neu in novOS" modal) and its items, each a feature or a fix in the four
languages. A feature may name an icon (module/icons/feature-<icon>-28.png), where OK
leads ("settings:<area>[:<page>]") and a motif; a release may name its own title
picture. Pictures lie in release-art/<version>/ and go into the signed archive, so a
release whose pictures are missing must not be built.

    python3 apps/novos/install/check-notes.py [<version>]    (exit 1 on a problem)
"""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = ("de", "en", "es", "fr")
LEVELS = ("patch", "minor", "major")
OPEN = re.compile(r"^settings:[a-z]+(:[A-Za-z]+)?$")


def problems(notes, only=None):
    found = []
    for version, entry in notes.items():
        if only and version != only:
            continue
        where = "release-notes.json " + version
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", entry.get("date", "")):
            found.append(where + ": date is not YYYY-MM-DD")
        if entry.get("level", "patch") not in LEVELS:
            found.append(where + ": level is one of " + ", ".join(LEVELS))
        art = HERE / "release-art" / version
        if entry.get("image") and not (art / entry["image"]).is_file():
            found.append(where + ": release-art/%s/%s is missing" % (version, entry["image"]))
        for index, item in enumerate(entry.get("items", [])):
            name = "%s item %d" % (where, index + 1)
            if item.get("kind", "feature") not in ("feature", "fix"):
                found.append(name + ": kind is feature or fix")
            for field in ("title", "text"):
                missing = [lang for lang in LANGUAGES if not (item.get(field) or {}).get(lang)]
                if missing:
                    found.append(name + ": %s lacks %s" % (field, " ".join(missing)))
            if item.get("icon") and not (HERE / "module" / "icons" / ("feature-%s-28.png" % item["icon"])).is_file():
                found.append(name + ": icon feature-%s-28.png is missing" % item["icon"])
            if item.get("open") and not OPEN.match(item["open"]):
                found.append(name + ": open is settings:<area>[:<page>]")
            if item.get("image") and not (art / item["image"]).is_file():
                found.append(name + ": release-art/%s/%s is missing" % (version, item["image"]))
    return found


def main(argv):
    notes = json.loads((HERE / "release-notes.json").read_text(encoding="utf-8"))
    found = problems(notes, argv[1] if len(argv) > 1 else None)
    for line in found:
        print(line, file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
