**Disclaimer: This is an unofficial project; character artwork remains the property of its rights holders.**

# YoungBar · 羊霸霸

[中文](README.md) | **English**

A keyboard-first menu bar organizer for **macOS 27 and later only** (Apple silicon Macs). Hide the icons you do not need, open them from one compact strip, and click through to their native menus — without the menu bar flashing or reflowing.

![YoungBar settings](docs/images/readme-general.png)

<p align="center">
  <img src="docs/images/readme-menu-bar.png" width="32%" alt="Menu bar">
  <img src="docs/images/readme-appearance-yellow.png" width="32%" alt="Appearance — yellow">
  <img src="docs/images/readme-appearance-clear.png" width="32%" alt="Appearance — clear">
</p>

## Install

**Requirements**: macOS 27 or later on an Apple silicon Mac. macOS 26 and earlier (12, 13, 14, 15 and so on) are not supported: the app won't open there, and the install command stops with a message before changing anything. See [How it works](#how-it-works-and-the-trade-offs) for why.

1. Download the latest `YoungBar-<version>.zip` from [Releases](../../releases/latest).
2. Unzip it and move `YoungBar.app` into `/Applications`.
3. First launch: right-click the app → **Open**.
4. Follow the guide to allow Accessibility. Enable *Open at login* in Settings if you want it at login.

YoungBar lives in the menu bar (•••); it has no Dock icon.

**Updating**: YoungBar checks once a day; a newer version adds a line at the top of the ••• right-click menu, and one click updates it. The download's checksum and signature are verified, and nothing installs by itself.

### Install with an agent

Send this to an agent that can run commands on your Mac, such as Claude Code, Codex, or DeepSeek (DSH). ChatGPT or Doubao on the web can't run commands; with those, copy the command further down instead:

> Install YoungBar for me: run `curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh`

Or run the command directly (it installs to `/Applications`, or `~/Applications` if that isn't writable):

```sh
curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
```

## Features

- **Three states**: each icon can be Shown, Hidden, or Always Hidden (⌥-click the ••• to include Always Hidden in the strip).
- **Instant strip**: hidden icons live in the strip, and opening it never reveals anything on the bar. An empty strip lists the icons on your bar: click one to tuck it in.
- **Open in place**: click an icon in the strip and its menu or panel opens beside it, with the icon still hidden and the pointer unmoved. System icons are shown briefly and then clicked.
- **Reorder**: ⌘-drag in the menu bar, or drag on the Menu Bar page in Settings; icons in the strip can be dragged sideways too.
- **Keyboard first**: press ⌘ twice to open the strip (you can pick another shortcut), then 1–9 to open an icon, or ← → and Return; Esc closes.
- **New icons to the strip** (optional): an app's icon that appears for the first time goes straight to the strip; system icons are left alone.
- **Icons that don't fit**: when the bar is full, icons macOS moves into its « are listed in the strip too, and go back to the bar once there is room.
- **Appearance**: system / light / dark, blue, pink, yellow and clear themes, adjustable strip opacity; the menu-bar button can use another symbol or your own picture.
- **Layout file**: export every icon's state, the order and all options to one JSON file, and import it on another Mac.
- **Crash-safe**: a normal quit reveals every concealed item first; after a crash the next launch reveals everything before re-applying rules. `--reveal-all` is a rescue flag.
- **Bilingual**: Chinese and English, switchable in General.
- **Light**: about 0.3% CPU at rest.

If something looks wrong, *Copy Diagnostics* in the ••• menu gives a short report to paste to the author. See [docs/FAQ.md](docs/FAQ.md) for the IP, licence, private-API and distribution questions.

## Build from source

Building from source needs macOS 27 and the Command Line Tools (Swift 6.4); Xcode is not required.

```sh
sh Scripts/build.sh
open build/YoungBar.app
swift test --disable-sandbox   # unit tests
```

See [docs/SIGNING.md](docs/SIGNING.md) and [docs/INSTALL.md](docs/INSTALL.md) for signing and installation details.

## Permissions

YoungBar needs only **Device Control and Data Access** (Accessibility on macOS 27), to read, hide and reorder menu-bar icons; without it the strip is empty. It does **not** capture the screen and does **not** need Screen & System Audio Recording.

If macOS stops recognizing the app, remove the old YoungBar entry and grant the permission again.

## How it works (and the trade-offs)

- **macOS 27 and later only**: hiding and ordering both rest on macOS 27's menu bar. Earlier versions would need a different way to do them — it isn't a matter of changing a version number.
- Hiding icons and reading the menu bar's colour use private interfaces (such as `MenuBarClientCore`), not public APIs, and may break on future releases. This app cannot be shipped on the App Store.
- The strip shows app icons, not the items' live menu-bar content: a concealed item is not drawn by macOS 27, so there is nothing current to show. Items whose value you watch belong in the visible part of the bar.

## License and credits

YoungBar is licensed under **GPL-3.0-only**. The full text is in [LICENSE](LICENSE); third-party components and asset provenance are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Distribution rules, the corresponding-source checklist, and the MIT question are covered in [docs/LICENSING.md](docs/LICENSING.md).

`Vendor/PelmetCore` and `Vendor/PelmetEngine` come from the [Dimble source repository](https://github.com/fif7y/dimble), commit `23a5412` (0.3.2, build 71), originally named Pelmet, under GPLv3. The vendored manifests drop the upstream probe executable and tests; implementation files are retained. A copy of the license sits in `Vendor/LICENSE`.

YoungBar's own UI and app code are original. The interaction model is informed by iBar Pro 1.4.6; no iBar assets, icons, or code are included. Theme artwork is user-supplied and is **not yet cleared for public distribution**; see [docs/FAQ.md](docs/FAQ.md).

## Contact

Rights-holder and removal requests: **wuyiyang.studio@gmail.com**
