# Local stable signing (no Apple Developer ID)

An **ad-hoc** signature (`codesign -s -`) has a designated requirement based on
the binary's `cdhash`. Every rebuild changes that hash, so macOS TCC stops
matching the old Accessibility grant. That is why the app can
show “granted” in System Settings while `AXIsProcessTrusted()` is still false.

A **self-signed code-signing certificate** gives the app a stable identity. If
the designated requirement becomes `certificate leaf = H"…"` instead of
`cdhash H"…"`, rebuilding with the same certificate usually keeps TCC grants.

This does **not** make Apple trust the app: Gatekeeper still warns on download,
and users still right-click Open. It only stabilizes the local identity.

## 1. Create the certificate (Keychain Access)

1. Open **Keychain Access** → **Certificate Assistant** →
   **Create a Certificate…**
2. Name: `YoungBar Local Signing`
3. Identity Type: **Self Signed Root**
4. Certificate Type: **Code Signing**
5. Create it in the **login** keychain.

Verify:

```sh
security find-identity -v -p codesigning | grep "YoungBar Local Signing"
```

## 2. Build with that identity

```sh
cd youngbar
sh Scripts/build.sh
```

`Scripts/sign.sh` now auto-detects `YoungBar Local Signing` in the login
keychain; `YOUNGBAR_SIGN_IDENTITY` overrides it. Without either, it falls back
to ad-hoc.

Check the designated requirement:

```sh
codesign -d -r- build/YoungBar.app
```

You want to see something like:

```text
designated => identifier "dev.leorea.youngbar" and certificate leaf = H"…"
```

If it still says `cdhash H"…"`, the identity was not used.

## 3. Re-grant once

Because the signature changed from ad-hoc to the certificate:

```sh
tccutil reset Accessibility dev.leorea.youngbar
```

Then launch the app and grant both permissions again. Future builds signed with
the same certificate should keep those grants.

## 4. Limits

- Gatekeeper: self-signed apps are not trusted by Apple. Users must right-click
  Open or remove the quarantine attribute. See [INSTALL.md](INSTALL.md).
- Notarization: impossible without an Apple Developer ID.
- If a macOS update tightens TCC to require an Apple-anchored certificate, only
  Developer ID will be stable.
- Do not distribute the certificate's private key. The public certificate is
  embedded in the signature automatically.
- Back up the identity from Keychain Access (export as `.p12`) and keep it
  offline. If the private key is lost, TCC treats the next build as a new app.
- On another Mac the self-signed certificate is not trusted. Gatekeeper still
  warns, and self-signed TCC matching should be tested there before relying on
  it for public releases. Developer ID is the only Apple-supported version.

## 5. GitHub-only workflow

1. Build and sign with your local certificate.
2. `sh Scripts/package.sh`
3. Upload `dist/YoungBar-<version>.zip` and `.sha256` to a GitHub Release.
4. Users follow [INSTALL.md](INSTALL.md).

No Developer ID, notarization, App Store, or auto-updater is required for this.
