# iBar Pro feature reconstruction — 21 October 2026

Target: installed `/Applications/iBar Pro.app`, version 1.4.6. No update or modification of the original application. YoungBar uses Dimble's GPLv3 PelmetCore/PelmetEngine and an original AppKit interface.

Last updated: 2026-10-22, YoungBar 0.3.0.

## Evidence and its boundary

Earlier work inspected executable metadata and parts of the preferences UI. That was not a full behavioral reverse engineering of iBar Pro.

The installed bundle was opened through REA's resource-only route and its compiled Interface Builder resources were decoded. The selected modern MainMenu document contains 559 recognized objects and 68 connections. Evidence: `ev_857890ec927c6429c59da412cec184d0bc9de48155e85ced4fdcc874645904f8`; selected document `Contents/Resources/Base.lproj/MainMenu.nib/keyedobjects-110000.nib`. The decode shows declared UI and connections, not successful execution on macOS 27 or the contents of handler implementations.

On 2026-10-21 the preferences geometry was re-read from the same decoded document (new run, same archive SHA-256 `62c6261e16b28eaf8738a8e21c5da085230915b4bd1de7671090179cd8c41c58`). Key facts used by the reconstruction:

| Object | Decoded fact |
| --- | --- |
| `PreferenceWindow` | 860 × 660, style mask 32775, identifier `PreferenceWindow` |
| Sidebar | 200 pt visual-effect column; app icon 70 × 70 at (65, 491), version label at y = 467 |
| Content | 660 × 660 tab view; first tab is 通用设置 (title at y = 585) |
| 通用设置 form | 开机自启动 (y = 473), 普通模式/聚合模式 (y = 410), 延迟 slider (y = 189) with the value and `s` beside it, 菜单栏图标间隙 popup (y = 55) |
| 菜单栏布局 table | 610 × 531 scroll view, columns `Name` 328, `Icon` 100, `Hide` 50, `AlwaysHide` 80 |

Directly read sources:

- `Contents/Resources/zh-Hans.lproj/MainMenu.strings` (localized labels and the feature names used below)
- `Contents/Resources/zh-Hans.lproj/Localizable.strings`
- Existing iBar Pro preferences: `advancedMode`, `arrOfAlwaysDisplay`, `arrOfNormalHidden`, `arrOfForEverHidden`, `showPanelWhenClick`, and the cached `dataOfAllMenuBarIcon` declaration. Preference values are evidence of saved configuration, not proof of runtime behavior. Private bookmarks and cached image data were not copied into this repository.
- `Contents/MacOS/iBar Pro` command strings (see 图标间隙 below).

## Feature map

| iBar feature / evidence | YoungBar implementation | Validation |
| --- | --- | --- |
| Visible / Hidden / Forever Hidden: localized table headers and saved arrays | Three per-item policies; layout table has separate 隐藏 / 始终隐藏 checkboxes; ⌥ click accesses Always Hidden | Build passed; live test pending |
| Original menu-bar images: screen-recording explanatory label `F1x-ks-PRb`; `buttonOfScreenRecordingAuthorize` connection | ScreenCaptureKit captures only the menu-bar band, preserves each item's width and appearance, and caches the crops on disk and covers both Hidden and Always Hidden items | Live: with Screen Recording granted, the strip shows Claude's and iFan's own menu-bar pixels; an Always Hidden item is cached too (`alwayshiddentest.json`). Opening the strip takes 21 ms and reveals nothing (`shelfopen.json`); refresh is manual or first-run |
| Compact aggregate panel: `advancedMode` / 聚合模式, `MenuBarWindow`, `StatusBarMenuWindow` | Single black rounded strip, no button bezels or app labels | Build passed; live test pending |
| Rehide delay: `sliderOfDelayTimesHideAgain`, text outlets 1–4, `再次自动隐藏菜单栏图标` | Each clicked item stays native and live; 5–60 second slider (iBar's `NSSliderCell` decodes to min 5 / max 60), 20 seconds by default, independent expiries | Live: both a 2 s simulated expiry and the real 20 s default auto-hidden and reconcealed (`autoHidden: true`, `expirySeconds: 20`) |
| Drag sorting: `TI1-MO-5q3` / 拖动图标进行排序 | Native settings table row drag plus ◀ ▶ buttons, upstream shielded Command-drag, actual result checked before accepting order | Live: WeChat ↔ CodexBar swapped with a real ⌘-drag and then restored (`ordertest.json`, `passed: true`) |
| System-pinned items: localized prohibition on date / Control Center / Siri | Date and Control Center keep their macOS-fixed position (no drag), but their hide checkboxes are enabled; hover text explains the difference | Live: both concealed and restored (`pinnedtest.json`) |
| Hover display at 0.2 / 0.5 seconds: localized explanatory labels, `checkButtonOfShowPanelWhenCursorEnter` | Optional 0.5-second control hover | Build passed; live test pending |
| Keep aggregate toolbar visible and refresh status: localized text and `csh-tM-tLi` | Keep-visible preference implemented; original pictures refresh on open, not continuously while concealed | Build passed; continuous hidden refresh remains a gap |
| Click blank menu-bar area: `PTE-r5-UNI`, `4xs-aW-O16`, `LLx-tk-qun` | Optional blank-area click toggle, restricted to right half outside observed item frames | Build passed; live test pending |
| 全部隐藏 / 全部显示: localized `OSz-OA-Ybc` plus per-app menu | Right-click menu now hides or shows every non-pinned application item at once without rewriting their saved modes | Live: hid 9 items, showed all, restored 2, `modesUnchanged: true` |
| Settings entry from the strip | A gear pinned at the right edge, separated from the items | Live: a real HID click opened the settings window and closed the strip (`geartest.json`) |
| Clicking a concealed item from the strip | `pressShelfItem` reveals the item, settles on its frame, and posts one shielded HID click (iBar's table/panel path) | Live: a menu-type item (input source) opened an `AXMenuItem` menu and Escape closed it (`AXGroup`) with its mode restored; iFan, a panel-type item, also received the click; a controlled re-test concealed it while the panel was open (`concealtest.json`) |
| 开机自启动: localized `eRa-wa-hFF`; iBar uses a `LoginItemSetEnabled` helper app | `SMAppService.mainApp` register/unregister, state read back into the 通用设置 checkbox | Registered: `sfltool dumpbtm` shows YoungBar as an enabled/allowed app login item; a real logout/login is still pending |
| 菜单栏图标间隙: localized `hLT-dU-ZXV`, choices 默认 / 较小 / 小 / 无 | Writes iBar's own global defaults commands after confirmation; see the exact values below | Live: wrote 3/3, read both back as 3, then removed them. Visual menu-bar spacing still needs a reboot to verify |

### 图标间隙 evidence

The iBar Pro executable contains the exact commands it runs for the four choices:

```
defaults -currentHost remove -g NSStatusItemSelectionPadding;defaults -currentHost remove -g NSStatusItemSpacing
defaults -currentHost write -g NSStatusItemSelectionPadding 5;defaults -currentHost write -g NSStatusItemSpacing 5
defaults -currentHost write -g NSStatusItemSelectionPadding 3;defaults -currentHost write -g NSStatusItemSpacing 3
defaults -currentHost write -g NSStatusItemSelectionPadding 0;defaults -currentHost write -g NSStatusItemSpacing 0
```

YoungBar maps 默认 / 较小 / 小 / 无 to those four commands, in that order, and tells the user a reboot is required (the same message iBar shows in `Localizable.strings`: `For the setting to work, please restart the computer.`).

## Verified on this Mac (2026-10-21)

- `sh Scripts/build.sh` builds `build/YoungBar.app` and signs it ad-hoc.
- The app launches as `dev.leorea.youngbar`; the settings window is 860 × 692 on screen (title bar included) and the overlay control is installed at the menu bar.
- Settings from the previous `dev.leorea.bar` domain were migrated: the new domain contains the same `itemModes`, `itemOrder`, `barOptions` and `hiddenBundles`.
- The window renders both pages; snapshots are written by `YOUNGBAR_SNAPSHOT_DIR=...` (see `docs/images/`).
- Screen Recording is granted: the menu-bar-band capture produces original item pixels.
- Accessibility is granted. The engine enumerated 11 menu-bar items (10 visible + 2 concealed at the time of the check).
- `YOUNGBAR_SELFTEST=1` passed: a concealed app item was revealed with a real frame (`1179,0 121×39`), auto-hidden after a 2-second expiry, and was absent again 500 ms later.
- With Screen Recording granted, the strip rendered iFan's original menu-bar content (`2316 / 2510 rpm`, `38°C`) from a menu-bar-band-only capture (`docs/images/shelf.png`).
- A real shelf click was delivered: AX focus moved to iFan and its panel opened; the production path set a 20 s reveal window (19 s remaining when read back).
- Saved entries whose menu-bar item no longer exists (Codex) are now excluded from the layout table and strip; a failed reveal reconceals instead of leaving the item out.
- The login item is registered (`sfltool dumpbtm` → YoungBar, enabled/allowed).
- The visible UI uses the English name only; 羊霸霸 remains the Chinese name used in the repository records.

## Not verified yet

- Reordering was verified with one adjacent pair (WeChat ↔ CodexBar); the ◀ ▶ button path and multi-display are still untested.
- Icon-spacing values are written and read back, but the menu bar has not been observed after a reboot.
- Launch at login needs a logout/login cycle.
- The icon-spacing write needs a reboot; the defaults commands are copied from iBar but have not been observed affecting macOS 27 here.
- Multi-display behavior remains unverified; the reconstruction targets the main display.

## Original status freshness

A concealed item disappears from the AX item tree and ceases drawing in the available menu-bar surface. This implementation briefly reveals selected items, takes a fresh image, then reconceals only items not on a 60-second reveal. The strip uses that sampled image and exposes its acquisition time as a tooltip. It must not be described as a continuously live relocation of the native NSStatusItem. A native item revealed for 60 seconds remains live on the actual menu bar.

A complete behavior-for-behavior clone has not been achieved. The table above retains explicit gaps instead of promoting resource discovery or compilation to live verification.

A native-expand mode has also been implemented: clicking the control reveals all normally hidden items together, and the next click reconceals them. Always Hidden remains separate. It is compiled but not yet tested live.
