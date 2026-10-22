# Releasing YoungBar

## 1. Before tagging

- [ ] Update `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist`
- [ ] Run `make verify`
- [ ] Run the local permission smoke tests (`YOUNGBAR_SELFTEST=1`,
      `YOUNGBAR_INTERACTIONTEST=1`, `YOUNGBAR_RECOVERY...`) on a real Mac
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
git tag -s v0.3.0 -m "YoungBar 0.3.0"
git push origin v0.3.0
```

Create a GitHub release from the tag. Attach:

- `YoungBar-0.3.0.zip` (the app)
- `YoungBar-0.3.0-source.zip` (or GitHub's source archive link)
- `SHA256SUMS`

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
