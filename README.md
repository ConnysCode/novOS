# novOS

novOS is an ad-free replacement for the system interface of an LG 55QNED816RE
(webOS 25, firmware 10.3.2). It brings a quick settings panel with live glass
over the running picture, a source picker, a launcher, a volume pill and a
settings modal that writes LG's own settings.

This is a proof of concept for one TV model. It needs a rooted TV with the
Homebrew Channel and is not a product.

## How it works

novOS never writes LG's system partition. Every LG file it replaces is covered
by a bind mount from `/var/lib/novos`, checked against the SHA-256 listed in
[`install/lg-targets.txt`](apps/novos/install/lg-targets.txt) before and after. A start
hook sets the mounts on every boot, with a self check, a supervisor and an
emergency switch. Each mount disappears with the next restart, and the
uninstaller brings LG's interface back completely.

## Requirements

- An SSH host alias `lg-tv` that reaches the TV as `root`.
- Docker, to build the video plugin for the TV's ARM userland.
- Python 3 on the TV (part of webOS).

## Repository

| Path | Content |
| --- | --- |
| [`apps/novos/`](apps/novos) | novOS itself: the interface, the video plugin, the release build and everything that runs on the TV |

`apps/` holds the deployable apps, `lib/` will hold components they share.

## Usage

All commands run from `apps/novos/`.

```sh
module/build.sh                 # builds module/output/libnovos-video-backdrop.so
./novos-on-tv.sh install        # uploads a release, no autostart
./novos-on-tv.sh start 1800     # starts it by hand, stops again after 30 min
./novos-on-tv.sh status
./novos-on-tv.sh autostart on   # start on every boot
./novos-on-tv.sh uninstall      # removes hook, mounts and files
```

`./novos-on-tv.sh` without arguments lists all commands. On the TV itself,
after `ssh lg-tv`: `sh novos-uninstall.sh`.

Releases are named after the commit of this repository. `install` refuses
uncommitted changes.

## Layout of `apps/novos/`

| Path | Content |
| --- | --- |
| `quick-settings-glass.qml`, `source-picker.qml`, `launcher.qml`, `volume-view.qml` | The four entry files, mounted over LG's QML |
| `module/` | Shared QML components, settings catalogs, icons, texts and the C++ video plugin |
| `launcher/` | Launcher backgrounds and the script that fetches them |
| `fonts/` | Static Inter cuts for Qt 5.12, the script that builds them, and the font licence |
| `*.inc`, `banner-relay.py` | Pieces patched into LG's files and a helper process |
| `install/` | Release build, list of LG targets, and everything that runs on the TV |
| `preview-on-tv.sh`, `gear-test-on-tv.sh`, `volume-preview.qml` | Previews from `/tmp` and temporary test mounts |
| `settings-check.js`, `settings-fetch.sh` | Builds every settings page in Node against values read from the TV |

Comments that cite `docs/…` refer to the documentation of the separate
research repository, which is not part of this one.

## Credits

The interface font is Inter, under the SIL Open Font License
([`fonts/OFL.txt`](apps/novos/fonts/OFL.txt)). The launcher backgrounds come from
Wikimedia Commons, credited in
[`launcher/backgrounds/CREDITS.md`](apps/novos/launcher/backgrounds/CREDITS.md).
