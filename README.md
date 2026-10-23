**声明：本项目非官方授权，角色素材版权归原权利人所有。**

# YoungBar · 羊霸霸

A keyboard-first menu bar organizer for **macOS 27**. Hide the icons you do not need, open them from one compact strip, and click through to their native menus — without the menu bar flashing or reflowing.

> YoungBar is a standalone repository, split out of the Leorea workspace with its history.

![收纳条](docs/images/shelf-expanded.png)

## Features

- **Three states per item**: Visible, Hidden, Always Hidden (⌥-click to include Always Hidden in the strip).
- **Instant strip**: each hidden item is shown by its app's own icon (system items by their SF Symbol); opening the strip never reveals anything.
- **Open in place**: clicking a third-party item in the strip presses it through Accessibility while it stays hidden, so its menu or panel opens beside the strip without the bar shifting or the pointer moving. System items are revealed and clicked with the pointer hidden.
- **Click-through**: a synthetic HID click delivers the press to the owning app; menus and panels open natively.
- **Reorder**: ⌘-drag in the real menu bar (verified with a swap-and-restore test) and drag rows in the layout table.
- **Global hotkey**: ⌃⌥B toggles the strip without the mouse.
- **Menu Bar page**: every item in menu-bar order with a Shown / Hidden / Always Hidden menu; drag a row or right-click it to reorder. Date and Control Center keep their macOS-fixed position but can be hidden.
- **Settings window**: System Settings-style sidebar and grouped forms (SwiftUI inside an AppKit window); the menu-bar logic stays in AppKit.
- **Appearance**: system / light / dark; three palettes (blue, pink, yellow) with matched lightness and saturation, plus a neutral clear one that follows the system; a theme-tinted glass settings window with the theme character in the sidebar; a three-way scope (interface + strip / interface only / strip only); and one strip opacity slider (30–100%, 100% is solid).
- **Custom menu-bar button**: ellipsis, heart, star, sparkles, grid, or your own 36×36 PNG.
- **Settings entry from the strip**: a pinned gear at the right edge.
- **Crash-safe**: a normal quit reveals every concealed item first; if the previous session died, the next launch reveals everything before re-applying rules. `--reveal-all` is a rescue flag.
- **Bilingual**: Chinese and English, switchable in General settings; theme names are localised (`怎怎瓦岗蓝` / Hachiware Blue, `羊霸霸粉` / Chiikawa Pink, `乌拉黄` / Usagi Yellow).
- **Local only**: no telemetry, no network, no screen capture.

See [docs/FAQ.md](docs/FAQ.md) for the IP/licence/private-API/distribution questions.

## Build and run

Requirements: macOS 27, Xcode Command Line Tools (Swift 6.3).

```sh
cd YoungBar
sh Scripts/build.sh
open build/YoungBar.app
```

`Scripts/build.sh` builds a release executable, assembles `build/YoungBar.app`, installs the icon and signs ad-hoc (or with `YOUNGBAR_SIGN_IDENTITY`). See [docs/SIGNING.md](docs/SIGNING.md) for a stable local certificate and [docs/INSTALL.md](docs/INSTALL.md) for the GitHub download flow. The `--disable-sandbox` flag lets SwiftPM build inside a host sandbox; the package has no build plugins.

## Permissions

| Permission | Why | Without it |
|---|---|---|
| **Device Control and Data Access** (Accessibility on macOS 27) | enumerate, hide, reveal and reorder menu-bar items | the strip is empty; only settings work |

Ad-hoc builds are re-signed on every build. If macOS stops recognizing the app, remove it from the permission list and add it again. A notarized Developer ID build removes this friction.

## How it works (and the trade-offs)

- Hiding uses the private `MenuBarClientCore` assessment interface. It works on macOS 27 but is not a public API and may break on future releases. This app cannot be shipped on the App Store.
- The strip shows app icons, not the items' live menu-bar content: a concealed item is not drawn by macOS 27, so there is nothing current to show, and a screenshot would be stale and blurry. Items whose value you watch belong in the visible part of the bar.
- No menu-bar screenshot is captured or cached; the strip uses app icons, so no Screen Recording permission is involved.

## Status

The current verification matrix — including what is implemented, what is verified live, and what is blocked — lives in [docs/STATUS.md](docs/STATUS.md). The iBar Pro 1.4.6 feature comparison and evidence are in [docs/IBAR-FEATURES.md](docs/IBAR-FEATURES.md).

Known gaps: multi-display, configurable hotkey, drag-reordering inside the strip, and a real-trackpad pass on the new SwiftUI settings. The old screenshot/cache pipeline is gone; the strip uses app icons and no longer needs Screen Recording.

## Roadmap

- Themes: color skins, transparent strip, polished light and dark.
- Configurable hotkey, keyboard navigation (arrows / Enter / Esc), layout search.
- Profiles with export/import, per-app rules.
- Multi-display.
- Localization (Chinese / English), notarized releases.

## License and credits

YoungBar is licensed under **GPL-3.0-only**. The full text is in [LICENSE](LICENSE); third-party components and asset provenance are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Distribution rules, the corresponding-source checklist, and the MIT question are covered in [docs/LICENSING.md](docs/LICENSING.md); release steps are in [docs/RELEASING.md](docs/RELEASING.md).

`Vendor/PelmetCore` and `Vendor/PelmetEngine` come from the [Dimble source repository](https://github.com/fif7y/dimble), commit `23a5412` (0.3.2, build 71), originally named Pelmet, under GPLv3. The vendored manifests drop the upstream probe executable and tests; implementation files are retained. A copy of the license sits in `Vendor/LICENSE`.

YoungBar's own UI and app code are original. The interaction model is informed by iBar Pro 1.4.6; no iBar assets, icons, or code are included. Theme artwork is user-supplied and is **not yet cleared for public distribution**; see [docs/FAQ.md](docs/FAQ.md).

## Contact

Rights-holder and removal requests: **wuyiyang.studio@gmail.com**
