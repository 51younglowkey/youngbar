# Installing a GitHub build

YoungBar is distributed directly from GitHub. It is not notarized by Apple, so
macOS will warn on first launch. This is expected for a small open-source app.

## 1. Download

Download `YoungBar-<version>.zip` from the latest GitHub Release, unzip it,
and move `YoungBar.app` to `/Applications`. Or run the install script, which
always fetches the latest release:

```sh
curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
```

## 2. First launch

Because the build is ad-hoc or self-signed:

1. Right-click `YoungBar.app` → **Open** → **Open**.
2. If macOS says the app is damaged, run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/YoungBar.app
   open /Applications/YoungBar.app
   ```

## 3. Grant permissions

Open YoungBar → **设置** → **权限**, then:

- **Device Control and Data Access** (Accessibility on older macOS):
  enable YoungBar. Without it the strip is empty.
YoungBar does not use Screen Recording: the strip shows app icons, not menu-bar
screenshots. Only the Accessibility permission above is required.

The permission belongs to `YoungBar.app`, not to GitHub or to the terminal.
If YoungBar is already listed but still shows “not granted” after an update,
remove the old YoungBar row and add it again.

## 4. Updates

There is no auto-updater: YoungBar never goes online. *Check for Updates…* in
the ••• menu opens the Releases page. To update, run the install script again
(it quits the running copy normally first, so hidden icons are shown before
the swap) or replace the app by hand. Releases are signed with the same local
certificate, so the Accessibility grant normally survives; if it doesn't,
remove the old entry and re-add the new one.

## 5. Uninstall

1. Quit YoungBar.
2. Remove `/Applications/YoungBar.app`.
3. Remove the login item in System Settings → General → Login Items.
4. Optionally delete `~/Library/Application Support/YoungBar/`.
5. Remove YoungBar from the Accessibility pane.
