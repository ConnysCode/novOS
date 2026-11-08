#!/usr/bin/env python3
"""Fetches the launcher's and the hub's backgrounds from Wikimedia Commons.

The pictures were chosen by hand from Commons' featured pictures of landscapes, mountains,
lakes and forests: originals of at least 3840 px width, licensed CC0, public domain or
CC BY, never CC BY-SA. CC BY asks for the author and the licence, so every picture carries
its credit line, shown on screen, and CREDITS.md names title, source, licence and the
change: scaled and cropped to 1920 x 1080, the pixels of the TV's interface plane.

The licence is read again from Commons on every run; a picture whose licence is no
longer one of the allowed ones stops the run.

Usage: fetch-commons-backgrounds.py <output-directory>
"""

import io
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image, ImageFilter

API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "novos-launcher-backgrounds/1.0 (personal project)"
TARGET = (1920, 1080)
ALLOWED = re.compile(r"^(CC0|Public domain|CC BY [234]\.0)$")
Image.MAX_IMAGE_PIXELS = None

# Commons file title, author as the credit names them.
PICKS = [
    ("Himalayas, Nepal.jpg", "Vyacheslav Argenberg"),
    ("Le Ngauruhoe et le Ruapehu vus du sommet du Tongariro.jpg", "Eusebius"),
    ("Glacier de Mont-de-Lans - France - 2020.jpg", "Radek Kucharski"),
    ("Winter in Tatry Mountains - Poland.jpg", "Radek Kucharski"),
    ("Himalayas, Cholatse, Nepal.jpg", "Vyacheslav Argenberg"),
    ("Gokyo Ri summit, Gokyo Lake, Nepal, Himalayas.jpg", "Vyacheslav Argenberg"),
    ("Matanuska-Susitna Borough, Alaska.jpg", "Ross Fowler"),
    ("Kirkjufell, Iceland, 20240714 1631 0713.jpg", "Jakub Hałun"),
    ("Fjallsárlón glacier lake, Iceland, 20240719 1720 2774.jpg", "Jakub Hałun"),
    ("Stuor Dáhtá lake along the Kungsleden trail during golden hour in Kvikkjokk-Kabla fjällurskog (DSCF2557).jpg",
     "Benoit Brummer"),
    ("Lake Tahoe at morning - 7-2023.jpg", "John D."),
    ("Lac Bersau (3).jpg", "Tournasol7"),
    ("Lac du Salagou - October 2020.jpg", "Christian Ferrer"),
    ("Komargorod pond 2013 G3.jpg", "George Chernilevsky"),
    ("The village of Pampaneira viewed from Plaza Vieja in Capileira (DSCF5824).jpg", "Benoit Brummer"),
    ("Caucasus, Ingushetia, Ингушские боевые и смотровые башни на закате, горы Кавказа.jpg", "Vyacheslav Argenberg"),
    ("Serranía de Hornocal up close near Humahuaca.jpg", "Havardtl"),
    ("Sunset on the Aresquiers beach.jpg", "Christian Ferrer"),
    ("Bois Raquet, in the High Fens – Eifel Nature Park (DSCF6655).jpg", "Benoit Brummer"),
    ("Snowy trees on the GR-16 between Membre and Vresse-sur-Semois (DSCF4800).jpg", "Benoit Brummer"),
]


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(int(error.headers.get("Retry-After") or 0) or 10 * (attempt + 1))
    raise SystemExit("Commons keeps refusing: " + url)


def info(title):
    params = {"action": "query", "format": "json", "prop": "imageinfo", "titles": "File:" + title,
              "iiprop": "url|size|extmetadata", "iiextmetadatafilter": "LicenseShortName|LicenseUrl"}
    page = next(iter(json.loads(get(API + "?" + urllib.parse.urlencode(params)))["query"]["pages"].values()))
    entry = page["imageinfo"][0]
    meta = entry.get("extmetadata", {})
    return {"url": entry["url"], "page": entry["descriptionurl"], "width": entry["width"],
            "height": entry["height"], "license": meta.get("LicenseShortName", {}).get("value", ""),
            "license_url": meta.get("LicenseUrl", {}).get("value", "")}


def file_name(title):
    stem = re.sub(r"[^a-z0-9]+", "-", title.rsplit(".", 1)[0].lower().encode("ascii", "ignore").decode()).strip("-")
    return stem[:60].rstrip("-") + ".jpg"


def save(picture, target):
    scale = max(TARGET[0] / picture.width, TARGET[1] / picture.height)
    resized = picture.resize((round(picture.width * scale), round(picture.height * scale)), Image.LANCZOS)
    left = (resized.width - TARGET[0]) // 2
    top = (resized.height - TARGET[1]) // 2
    cropped = resized.crop((left, top, left + TARGET[0], top + TARGET[1]))
    cropped = cropped.filter(ImageFilter.UnsharpMask(radius=0.8, percent=45, threshold=2))
    cropped.save(target, quality=92, optimize=True, subsampling=0)


def main():
    output = pathlib.Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    index = []
    credits = ["# Hintergründe", "",
               "Alle Bilder stammen von Wikimedia Commons. Für den TV wurden sie verkleinert und auf 1920×1080",
               "zugeschnitten (Bildmitte), sonst unverändert. Erzeugt von `lib/backgrounds/fetch-commons-backgrounds.py`.", ""]
    for title, author in PICKS:
        data = info(title)
        if not ALLOWED.match(data["license"]):
            raise SystemExit(f"{title}: licence is now {data['license']!r}")
        if data["width"] < 3840:
            raise SystemExit(f"{title}: only {data['width']} px wide")
        name = file_name(title)
        target = output / name
        if not target.exists():
            save(Image.open(io.BytesIO(get(data["url"]))).convert("RGB"), target)
            time.sleep(2)
        licence = "Public Domain" if data["license"] == "Public domain" else data["license"]
        index.append({"file": name, "credit": f"{author}, {licence}"})
        link = f" ({data['license_url']})" if data["license_url"] else ""
        credits.append(f"- `{name}`: „{title.rsplit('.', 1)[0]}“ von {author}, {licence}{link}, {data['page']}")
        print(name, data["width"], data["height"], data["license"], flush=True)
    (output / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1) + "\n")
    (output / "CREDITS.md").write_text("\n".join(credits) + "\n")
    print(len(index), "pictures")


if __name__ == "__main__":
    main()
