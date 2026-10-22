# Third-party notices

YoungBar is distributed under **GNU GPL version 3 (GPL-3.0-only)**. The full
license text is in [LICENSE](LICENSE). This file lists the third-party
components and the provenance of assets.

## Pelmet / Dimble

- Components: `Vendor/PelmetCore`, `Vendor/PelmetEngine`
- Upstream: <https://github.com/fif7y/dimble>
- Commit: `23a5412` (Dimble 0.3.2, build 71; originally named Pelmet)
- License: GNU GPL version 3
- Copyright: Dimble contributors
- Local changes: the vendored package manifests drop the upstream probe
  executable and test targets; implementation sources are retained. The
  private `MenuBarClientCore` assessment interface is used as provided by
  the upstream project.

These components are **not** MIT-licensed. They are included under GPLv3;
the combined YoungBar binary is therefore distributed under GPLv3.

## Assets

- Menu bar glyphs use **SF Symbols**, provided by Apple and subject to
  Apple's SF Symbols license terms.
- Theme artwork and the app icon are user-supplied. Their rights status is
  **not cleared for public distribution**; confirm permission or replace them
  with original artwork before publishing a public release.

## iBar Pro

YoungBar's interaction model was informed by iBar Pro 1.4.6. No iBar Pro
code, assets, icons, or other files are included. YoungBar's UI and
implementation are original.

## No warranty

The software is provided “as is”, without warranty of any kind, to the extent
permitted by applicable law. See LICENSE.
