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

The install script and the in-app updater both use the latest release, so
the newest release must not be a pre-release or draft. The updater also needs:

- the asset names exactly `YoungBar-<version>.zip` and `.zip.sha256`, and the
  tag `v<version>` matching `CFBundleShortVersionString` inside the zip;
- the app signed with the same **YoungBar Local Signing** certificate as
  every earlier release. A release signed with anything else is refused by
  the updaters already out there (by design), so keep that certificate.

Release notes must include:

> Corresponding source for this binary: <link to the same tag's source>.

## 3.1 Test versions (betas)

Only when a change touches the core and can't be fully checked on one Mac; a
plain fix goes straight to a final version.

- Version `0.1.8-beta.1` in `Info.plist`, changelog `docs/RELEASE-0.1.8-beta.1.md`,
  tag `v0.1.8-beta.1` on the public repository (GPLv3: every published build
  has its source there).
- Publish it marked **pre-release**. `releases/latest` skips pre-releases, so
  nobody is offered it: the updater and the one-line install keep the last final
  version, and `ReleaseInfo.parse` refuses one anyway.
- People install it by hand, on purpose:
  `curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | YOUNGBAR_VERSION=0.1.8-beta.1 sh`
- A beta sorts before its version (`0.1.8-beta.2` < `0.1.8`), so someone on it
  is offered the final version. One beta isn't offered the next: they install
  that by hand too.
- Versions before 0.1.8 can't read a beta's number. It doesn't matter: they only
  ever see the latest final version.

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
