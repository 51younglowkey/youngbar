# Installing a GitHub build

YoungBar is distributed directly from GitHub. It is not notarized by Apple, so
macOS will warn on first launch. This is expected for a small open-source app.

## Requirements

macOS 27 or later, on an Apple silicon Mac (macOS 27 doesn't run on Intel Macs).
macOS 26 and earlier are not supported: macOS refuses to open the app there,
and the install script stops before downloading anything.

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

The first-launch guide asks for this. If you skipped it, open YoungBar's Settings: until the permission is granted, the **Menu Bar** page has an allow button, and so does the ••• right-click menu. Then:

- **Device Control and Data Access** (the pane called Accessibility before macOS 27):
  enable YoungBar. Without it the strip is empty.
YoungBar does not use Screen Recording: the strip shows app icons, not menu-bar
screenshots. Only the Accessibility permission above is required.

The permission belongs to `YoungBar.app`, not to GitHub or to the terminal.
If YoungBar is already listed but still shows “not granted” after an update,
remove the old YoungBar row and add it again.

## 4. Updates

YoungBar asks GitHub for the latest release once a day (from 0.1.4; 0.1.2 and
0.1.3 only when you click *Check for Updates…*). A newer version adds a line
at the top of the ••• right-click menu; choosing it, or
*Check for Updates…* (••• menu or Settings → General), offers *Install and
Relaunch*: it
downloads the zip, checks its SHA-256 and that the new app is signed with the
same certificate as the installed one, quits normally (hidden icons come back
first), swaps the bundle and reopens it. A log is written to
`~/Library/Application Support/YoungBar/update.log`. Nothing is installed
without that click. If YoungBar's folder isn't writable, or you built it yourself
(ad-hoc signed), it sends you to the Releases page instead. 0.1.1 and older
must be updated once by hand or with the install script. Releases are signed with the same local
certificate, so the Accessibility grant normally survives; if it doesn't,
remove the old entry and re-add the new one.

## 5. Uninstall

1. Quit YoungBar.
2. Remove `/Applications/YoungBar.app`.
3. Remove the login item in System Settings → General → Login Items.
4. Optionally delete `~/Library/Application Support/YoungBar/`.
5. Remove YoungBar from the Accessibility pane.
