# YoungBar · 羊霸霸

A keyboard-first menu bar organizer for **macOS 27**. Hide the icons you do not need, open them from one compact strip, and click through to their native menus — without the menu bar flashing or reflowing.

> `youngbar/` is a self-contained subproject. It is intended to become its own clean repository; it does not depend on the rest of Leorea.

![收纳条](docs/images/shelf-expanded.png)

## Features

- **Three states per item**: Visible, Hidden, Always Hidden (⌥-click to include Always Hidden in the strip).
- **Instant strip**: opening reads a cached menu-bar crop; it never reveals items just to paint the strip (measured ~21 ms, 0 revealed items).
- **Original menu-bar pixels**: ScreenCaptureKit samples only the menu-bar band. Clock and battery always use a symbol fallback so a stale time/percentage is never shown.
- **Click-through**: a synthetic HID click delivers the press to the owning app; menus and panels open natively.
- **Reorder**: ⌘-drag in the real menu bar (verified with a swap-and-restore test) and drag rows in the layout table.
- **Global hotkey**: ⌃⌥B toggles the strip without the mouse.
- **Layout list**: one rounded card per item (name, icon, Hide, Always Hidden), draggable as a whole row, with system items included. Date and Control Center keep their macOS-fixed position but can be hidden.
- **Appearance**: liquid-glass settings window with integrated traffic lights (no separate titlebar), system / light / dark, four palettes (blue glass, pink, yellow, neutral clear that follows the system light/dark) with mini-strip swatches, theme-matched sidebar icons for blue/pink/yellow, a three-way scope (interface + strip / interface only / strip only), and solid / translucent / vibrant strip materials.
- **Custom menu-bar button**: ellipsis, heart, star, sparkles, grid, or your own 36×36 PNG.
- **Settings entry from the strip**: a pinned gear at the right edge.
- **Bilingual**: Chinese and English, switchable in General settings; theme names are localised (`怎怎瓦岗蓝` / Hachiware Blue, `羊霸霸粉` / Chiikawa Pink, `乌拉黄` / Usagi Yellow).
- **Local only**: no telemetry, no network. Menu-bar crops are cached in `~/Library/Application Support/YoungBar/pictures.json` and can be cleared from the menu.

## Build and run

Requirements: macOS 27, Xcode Command Line Tools (Swift 6.3).

```sh
cd youngbar
sh Scripts/build.sh
open build/YoungBar.app
```

`Scripts/build.sh` builds a release executable, assembles `build/YoungBar.app`, installs the icon and signs ad-hoc. The `--disable-sandbox` flag lets SwiftPM build inside a host sandbox; the package has no build plugins.

## Permissions

| Permission | Why | Without it |
|---|---|---|
| **Device Control and Data Access** (Accessibility on macOS 27) | enumerate, hide, reveal and reorder menu-bar items | the strip is empty; only settings work |
| **Screen & System Audio Recording** | sample original menu-bar pixels | app-icon fallback |

Ad-hoc builds are re-signed on every build. If macOS stops recognizing the app, remove it from the permission list and add it again. A notarized Developer ID build removes this friction.

## How it works (and the trade-offs)

- Hiding uses the private `MenuBarClientCore` assessment interface. It works on macOS 27 but is not a public API and may break on future releases. This app cannot be shipped on the App Store.
- The strip shows **cached** pixels. A fresh capture requires temporarily revealing concealed items, which makes the bar flash — that is why capture happens only on first run, after an explicit **刷新原始图标**, or when the cache is cleared.
- Dynamic items are never cached: clock and battery use SF Symbols; third-party dynamic content (fan RPM, percentages) shows the acquisition time in its tooltip.

## Status

The current verification matrix — including what is implemented, what is verified live, and what is blocked — lives in [docs/STATUS.md](docs/STATUS.md). The iBar Pro 1.4.6 feature comparison and evidence are in [docs/IBAR-FEATURES.md](docs/IBAR-FEATURES.md).

Known gaps: multi-display, live (non-cached) mode, configurable hotkey, drag-reordering inside the strip.

## Roadmap

- Themes: color skins, transparent strip, polished light and dark.
- Configurable hotkey, keyboard navigation (arrows / Enter / Esc), layout search.
- Profiles with export/import, per-app rules.
- Multi-display.
- Localization (Chinese / English), notarized releases.

## License and credits

GPLv3. `Vendor/PelmetCore` and `Vendor/PelmetEngine` come from the [Dimble source repository](https://github.com/fif7y/dimble), commit `23a5412` (0.3.2, build 71), originally named Pelmet. The vendored manifests drop the upstream probe executable and tests; implementation files are retained. See [LICENSE](LICENSE).

YoungBar's own UI and app code are original. The interaction model is informed by iBar Pro 1.4.6; no iBar assets, icons, or code are included.
