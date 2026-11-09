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
| [`apps/setup/`](apps/setup) | The setup that installs, updates and removes novOS. For now a visual debug build: every screen as a slide, without function |
| [`lib/ui/`](lib/ui) | The glass components every app shares: style tokens, glass cards, focus surface, rows, switches, sliders, buttons, notices, popovers, progress, status lists, the on-screen keyboard, texts, icons and fonts |
| [`lib/backgrounds/`](lib/backgrounds) | The pictures behind the launcher, the hub and the setup, with their credits |
| [`lib/release/`](lib/release) | Signed releases: Ed25519 in plain Python, manifests, channel files, checked downloads |

`apps/` holds the deployable apps, `lib/` the code they share. An app's build merges
`lib/ui/` into its own `module/` folder with [`lib/ui/stage.py`](lib/ui/stage.py), so both
import as one directory; the app brings a `UiConfig.js` with its settings file and app id.

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

### Releases

A tag `novos-v<version>` builds, signs and publishes a release with
[`.github/workflows/release-novos.yml`](.github/workflows/release-novos.yml): `novos-v1.0.0` goes to the
stable and the beta channel, `novos-v1.1.0-beta.1` to beta only. Each release has an archive,
a manifest with the archive's SHA-256 and the LG files it overlays, and an Ed25519 signature of
the manifest. Channel files on GitHub Pages (`novos/stable.json`, `novos/beta.json`) point to the
current manifest. Nothing is installed unless the signature matches a key in
[`lib/release/trusted-keys.json`](lib/release/trusted-keys.json) and the archive matches the manifest.

```sh
apps/novos/novos-on-tv.sh install --from beta     # or stable, or a manifest URL
```

### The setup's debug slides

```sh
apps/setup/preview-on-tv.sh <build-name> all     # shows every slide from /tmp, captures each
```

Left and right (or the channel keys) step through the slides on the TV.

## Layout of `apps/novos/`

| Path | Content |
| --- | --- |
| `quick-settings-glass.qml`, `source-picker.qml`, `launcher.qml`, `volume-view.qml` | The four entry files, mounted over LG's QML |
| `module/` | novOS' own QML components, settings catalogs, icons, texts and the C++ video plugin |
| `*.inc`, `banner-relay.py` | Pieces patched into LG's files and a helper process |
| `install/` | Release build, list of LG targets, and everything that runs on the TV |
| `preview-on-tv.sh`, `gear-test-on-tv.sh`, `volume-preview.qml` | Previews from `/tmp` and temporary test mounts |
| `settings-check.js`, `settings-fetch.sh` | Builds every settings page in Node against values read from the TV |

Comments that cite `docs/…` refer to the documentation of the separate
research repository, which is not part of this one.

## License

novOS is free software under the GNU General Public License, version 3
([`LICENSE`](LICENSE)). The Inter font and the background pictures keep their own
licences, named below.

novOS is an independent project and not a product of LG Electronics. LG and webOS are
trademarks of their owners.

## Credits

The interface font is Inter, under the SIL Open Font License
([`lib/ui/fonts/OFL.txt`](lib/ui/fonts/OFL.txt)). The launcher backgrounds come from
Wikimedia Commons, credited in
[`lib/backgrounds/CREDITS.md`](lib/backgrounds/CREDITS.md).
