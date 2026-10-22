# Licensing and source compliance

YoungBar is **GPL-3.0-only**. The full text is in [../LICENSE](../LICENSE);
third-party components are listed in [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Why GPLv3

`Vendor/PelmetCore` and `Vendor/PelmetEngine` come from Dimble and are
GPLv3. Linking them into the same application and distributing that binary
means the combined work is distributed under GPLv3.

This is unrelated to whether YoungBar is free or paid. GPLv3 permits selling
copies; it requires that recipients receive the same freedoms and the
corresponding source.

## What recipients may do

Under GPLv3, recipients may:

- run the app for any purpose
- study and modify the source
- redistribute the original or modified version
- charge for copies or support

If they distribute a modified version or a binary, they must:

- keep the GPLv3 license and copyright notices
- mark their changes
- provide the complete corresponding source
- not add restrictions beyond GPLv3

## What “corresponding source” means here

For a YoungBar binary, that is:

- all `Sources/YoungBar` Swift files
- `Package.swift`, `Info.plist`, `Scripts/build.sh`, and any script needed to
  rebuild the app
- the vendored `Vendor/PelmetCore` and `Vendor/PelmetEngine` sources
- the `LICENSE` and `THIRD_PARTY_NOTICES.md` files

It does **not** require personal data, signing certificates, or private
infrastructure.

## Release checklist

For every public binary release:

1. Tag the exact source commit.
2. Put `LICENSE` and `THIRD_PARTY_NOTICES.md` in the app bundle's
   `Contents/Resources/` (the build script does this).
3. In the release notes, link to the source tag and state:
   “Corresponding source for this binary: <source archive URL>.”
4. Include the GPLv3 license text and keep upstream notices.
5. Do not add terms that forbid redistribution, commercial use, or
   modification.
6. Keep the build scripts and vendored sources in the public repository.
7. If you modify vendored files, record what changed in
   `THIRD_PARTY_NOTICES.md`.

## Can the project be relicensed to MIT?

Not while it contains the GPLv3 Pelmet components. Options:

1. Keep GPLv3 (current).
2. Replace the hiding engine with an original implementation, then choose a
   new license for the resulting code.
3. Obtain a separate license from the Dimble authors.

## Source availability

The public source repository is the source offer. If a binary is distributed
without a public repository, include a written offer valid for at least three
years, or ship the source alongside the binary.

## Artwork and character IP

GPLv3 covers code; it does not grant rights to third-party characters or
artwork. The theme artwork and names must be cleared or replaced before a
public release. See [FAQ.md](FAQ.md).
