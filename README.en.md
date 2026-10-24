**Disclaimer: This is an unofficial project; character artwork remains the property of its rights holders.**

# YoungBar · 羊霸霸

[中文](README.md) | **English**

A keyboard-first menu bar organizer for **macOS 27**. Hide the icons you do not need, open them from one compact strip, and click through to their native menus — without the menu bar flashing or reflowing.

![YoungBar settings](docs/images/readme-general.png)

<p align="center">
  <img src="docs/images/readme-menu-bar.png" width="32%" alt="Menu bar">
  <img src="docs/images/readme-appearance-yellow.png" width="32%" alt="Appearance — yellow">
  <img src="docs/images/readme-appearance-clear.png" width="32%" alt="Appearance — clear">
</p>

## Install

1. Download `YoungBar-0.1.0.zip` from [Releases](../../releases).
2. Unzip it and move `YoungBar.app` into `/Applications`.
3. First launch: right-click the app → **Open**.
4. Allow Accessibility when prompted. Enable *Open at login* in Settings if you want it at login.

YoungBar lives in the menu bar (•••); it has no Dock icon.

### Install with an agent

Send this to ChatGPT, Doubao, Claude, DeepSeek (DSH), or any other agent:

> Install YoungBar for me: run `curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh`

Or run the command directly:

```sh
curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
```

## Features

- **Three states per item**: Visible, Hidden, Always Hidden (⌥-click to include Always Hidden in the strip).
- **Instant strip**: each hidden item is shown by its app's own icon (system items by their SF Symbol); opening the strip never reveals anything.
- **Open in place**: clicking a third-party item in the strip presses it through Accessibility while it stays hidden, so its menu or panel opens beside the strip without the bar shifting or the pointer moving. System items are revealed and clicked with the pointer hidden.
- **Reorder**: ⌘-drag in the real menu bar and drag a row in the Menu Bar page; right-click a row for left/right moves.
- **Global hotkey**: ⌃⌥B toggles the strip without the mouse.
- **Menu Bar page**: every item in menu-bar order with Shown / Hidden / Always Hidden segmented choices; Date and Control Center keep their macOS-fixed position but can be hidden.
- **Settings window**: System Settings-style sidebar and grouped forms (SwiftUI inside an AppKit window); the menu-bar logic stays in AppKit.
- **Appearance**: system / light / dark; blue, pink and yellow palettes with matched OKLCH lightness/saturation, plus a neutral clear one; a theme-tinted glass window with the theme character in the sidebar; three-way scope and one strip opacity slider (30–100%).
- **Custom menu-bar button**: ellipsis, heart, star, sparkles, grid, or a 36×36 PNG.
- **Settings entry from the strip**: a pinned gear at the right edge.
- **Crash-safe**: a normal quit reveals every concealed item first; after a crash the next launch reveals everything before re-applying rules. `--reveal-all` is a rescue flag.
- **Bilingual**: Chinese and English, switchable in General.
- **Local only**: no telemetry, no network, no screen capture.

See [docs/FAQ.md](docs/FAQ.md) for the IP/licence/private-API/distribution questions.

## Build from source

Building from source needs macOS 27 and the Swift 6.3 toolchain.

```sh
sh Scripts/build.sh
open build/YoungBar.app
```

`Scripts/build.sh` builds a release executable, assembles `build/YoungBar.app`, installs the icon, and signs with a stable local certificate if one is configured (otherwise ad-hoc). See [docs/SIGNING.md](docs/SIGNING.md), [docs/INSTALL.md](docs/INSTALL.md) and [docs/RELEASING.md](docs/RELEASING.md).

To produce a release zip and SHA256:

```sh
make package
```

## Permissions

| Permission | Why | Without it |
|---|---|---|
| **Device Control and Data Access** (Accessibility on macOS 27) | enumerate, hide, reveal and reorder menu-bar items | the strip is empty; only settings work |

YoungBar does **not** capture the screen and does **not** need Screen & System Audio Recording. If macOS stops recognizing the app after a rebuild, remove the old YoungBar entry and grant Accessibility again. A notarized Developer ID build removes that friction.

## How it works (and the trade-offs)

- Hiding uses the private `MenuBarClientCore` assessment interface. It works on macOS 27 but is not a public API and may break on future releases. This app cannot be shipped on the App Store.
- The strip shows app icons, not the items' live menu-bar content: a concealed item is not drawn by macOS 27, so there is nothing current to show. Items whose value you watch belong in the visible part of the bar.
- There is no menu-bar screenshot capture or cache.

## Status and gaps

The current verification matrix is in [docs/STATUS.md](docs/STATUS.md); the iBar Pro 1.4.6 comparison is in [docs/IBAR-FEATURES.md](docs/IBAR-FEATURES.md).

Known gaps: multi-display, configurable hotkey, keyboard navigation, drag-reordering inside the strip, and a real-trackpad pass on the SwiftUI settings. Launch-at-login has been registered but still needs a true logout/login test.

## Roadmap

- Configurable hotkey, keyboard navigation (arrows / Enter / Esc), layout search.
- Profiles with export/import, per-app rules.
- Multi-display.
- Notarized releases, auto-update.

## License and credits

YoungBar is licensed under **GPL-3.0-only**. The full text is in [LICENSE](LICENSE); third-party components and asset provenance are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Distribution rules, the corresponding-source checklist, and the MIT question are covered in [docs/LICENSING.md](docs/LICENSING.md); release steps are in [docs/RELEASING.md](docs/RELEASING.md).

`Vendor/PelmetCore` and `Vendor/PelmetEngine` come from the [Dimble source repository](https://github.com/fif7y/dimble), commit `23a5412` (0.3.2, build 71), originally named Pelmet, under GPLv3. The vendored manifests drop the upstream probe executable and tests; implementation files are retained. A copy of the license sits in `Vendor/LICENSE`.

YoungBar's own UI and app code are original. The interaction model is informed by iBar Pro 1.4.6; no iBar assets, icons, or code are included. Theme artwork is user-supplied and is **not yet cleared for public distribution**; see [docs/FAQ.md](docs/FAQ.md).

## Contact

Rights-holder and removal requests: **wuyiyang.studio@gmail.com**
