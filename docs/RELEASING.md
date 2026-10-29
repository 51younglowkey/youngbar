# Releasing YoungBar

## 1. Before tagging

- [ ] Update `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist`
- [ ] Run `make verify` and `swift test --disable-sandbox`
- [ ] Build the test variant (`TESTHOOKS=1 sh Scripts/build.sh`) and run the
      live checks on a real Mac (`YOUNGBAR_SELFTEST=1`, `YOUNGBAR_KEYBOARDTEST=1`,
      `YOUNGBAR_OVERFLOWTEST=1`, `YOUNGBAR_CONFIGTEST=1`, …); back up
      `defaults export studio.wuyiyang.youngbar` first and compare after
- [ ] `make package` (always builds without test hooks); check
      `strings build/YoungBar.app/Contents/MacOS/YoungBar | grep YOUNGBAR_` shows
      no `*TEST` names
- [ ] Confirm `LICENSE`, `THIRD_PARTY_NOTICES.md`, and `docs/LICENSING.md`
      are current
- [ ] Confirm theme artwork is cleared for public distribution (currently
      **not** cleared; see `docs/FAQ.md`)

## 2. Build and bundle

```sh
sh Scripts/build.sh
```

The script copies `LICENSE` and `THIRD_PARTY_NOTICES.md` into
`YoungBar.app/Contents/Resources/` and ad-hoc signs the bundle.

## 3. Tag and source

```sh
git tag -a v<version> -m "YoungBar <version>"
git push origin v<version>
```

Create a GitHub release from the tag. Attach:

- `YoungBar-<version>.zip` (the app)
- `YoungBar-<version>.zip.sha256` (the install script checks it)
- GitHub's source archive link for the same tag

The install script resolves `/releases/latest`, so the newest release must
not be marked as a pre-release.

Release notes must include:

> Corresponding source for this binary: <link to the same tag's source>.

## 4. Distribution channels

- GitHub Releases: direct download
- Homebrew Cask: `brew install --cask youngbar` (after notarization)
- Install script: optional; document Gatekeeper and permission steps

## 5. Notarization (future)

Ad-hoc signatures change on every build and can reset TCC permissions.
A Developer ID Application certificate plus notarization is required for a
frictionless public build. Keep the same bundle identifier and signing
identity across releases.

## 6. What not to do

- Do not relicense the combined app to MIT while Pelmet is vendored.
- Do not ship Chiikawa artwork/names publicly without permission.
- Do not omit the source link or the GPLv3 text from a binary release.
