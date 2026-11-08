#!/usr/bin/env python3
"""Merges lib/ui and an app's module folder into one folder, the way an app ships them.

    python3 -I lib/ui/stage.py <app-module-dir> <out-dir>

QML and JS files, icons/ and the folders under i18n/ are copied side by side; a file
both have stops the run. qmldir gets the app's lines first, then the lib's, without
comments. i18n/<language>.json is merged by namespace, the lib's namespaces first; a
namespace both have stops the run. The app must bring UiConfig.js. Anything else in
the app's folder (the plugin, scripts, sources) is left to the app's build.
"""

import json
import pathlib
import shutil
import sys

LIB = pathlib.Path(__file__).resolve().parent


def fail(message):
    sys.exit(f"stage.py: {message}")


def copy_new(source, target):
    if target.exists():
        fail(f"{target.relative_to(OUT)} comes from both lib/ui and the app")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def copy_files(folder):
    for source in sorted(folder.iterdir()):
        if source.is_file() and source.suffix in (".qml", ".js"):
            copy_new(source, OUT / source.name)
    icons = folder / "icons"
    if icons.is_dir():
        for source in sorted(icons.glob("*.png")):
            copy_new(source, OUT / "icons" / source.name)
    texts = folder / "i18n"
    if texts.is_dir():
        for source in sorted(texts.rglob("*.json")):
            if source.parent != texts:
                copy_new(source, OUT / "i18n" / source.relative_to(texts))


def qmldir_lines(folder):
    path = folder / "qmldir"
    if not path.is_file():
        return []
    return [line for line in path.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def merge_texts(folders):
    languages = sorted({path.name for folder in folders for path in (folder / "i18n").glob("*.json")})
    for name in languages:
        merged = {}
        for folder in folders:
            path = folder / "i18n" / name
            if not path.is_file():
                continue
            for namespace, texts in json.loads(path.read_text(encoding="utf-8")).items():
                if namespace in merged:
                    fail(f"i18n namespace {namespace!r} in {name} comes from both lib/ui and the app")
                merged[namespace] = texts
        target = OUT / "i18n" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if len(sys.argv) != 3:
    fail("usage: stage.py <app-module-dir> <out-dir>")
APP = pathlib.Path(sys.argv[1]).resolve()
OUT = pathlib.Path(sys.argv[2]).resolve()
if not (APP / "UiConfig.js").is_file():
    fail(f"{APP} has no UiConfig.js, which lib/ui needs")
if OUT.exists() and any(OUT.iterdir()):
    fail(f"{OUT} is not empty")
OUT.mkdir(parents=True, exist_ok=True)

copy_files(LIB)
copy_files(APP)
(OUT / "qmldir").write_text("".join(line + "\n" for line in qmldir_lines(APP) + qmldir_lines(LIB)))
merge_texts([LIB, APP])
