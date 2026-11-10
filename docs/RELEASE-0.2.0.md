# YoungBar 0.2.0 更新日志

这是一次大版本更新。这段时间大家反馈最多的是 ••• 和图标重叠，这一版把目前找到的几种重叠都查清楚、修好了。

## 新增

- macOS 不显示的图标会进收纳条
- 设置里单独列出 macOS 不显示的图标

## 优化

- 设置里收纳条的图标排在最前
- 收纳条和菜单栏的图标分两段排
- 设置里整行都能拖动和右键

## 修复

- ••• 不再和自己的空白处分开
- 一个应用多个图标时不再重叠
- 菜单栏挤满时 ••• 不再盖住 «
- ••• 不再被误判成挤满而变窄

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 有好几个菜单栏图标的应用（比如 Stats 的各个模块），只能整个应用一起隐藏或显示：macOS 是按应用隐藏的。想分开的话，可以在那个应用自己的设置里合并或关掉模块
- **自己编译的应用，或从 GitHub 等地方下载、没有 Apple 开发者签名的应用**：只要有任何一个图标被隐藏，macOS 就不显示它们的菜单栏图标，设成「显示」也不行。这是 macOS 的规则：YoungBar 交给系统一份「允许留在菜单栏的应用」名单，系统只认有 Apple 签发签名的应用（实测得出，Apple 没有文档说明）。一个图标都不隐藏时不受影响。这个版本会把这类图标放进收纳条，从收纳条可以点开；设置里它们单独一段「系统不显示：固定在收纳条里」，不能单独设成显示或隐藏。想知道某个应用有没有签名：终端里运行 `codesign -dv /Applications/某应用.app`，看到 `Developer ID Application` 或 `Apple` 的就是有
- 遇到问题时，右键 ••• →「复制诊断信息」，再贴到群里、评论区或 GitHub

# English

This is a major update. The most common report lately was the ••• overlapping icons; this version tracks down every kind of overlap found so far and fixes it.

## New

- Icons macOS won't show go to the strip
- Settings lists icons macOS keeps off

## Improved

- Settings lists strip icons first
- Strip and menu bar icons sort separately
- Whole rows in Settings drag and right-click

## Fixed

- The ••• stays on YoungBar's own blank spot
- No overlap with apps that have several icons
- On a full bar the ••• no longer covers the «
- The ••• no longer shrinks for no reason

## Requirements

- macOS 27 or later on an Apple silicon Mac; earlier systems (macOS 26 and before) can't open it
- Device Control and Data Access (Accessibility) permission; no screen recording

## Notes

- An app with several menu bar icons (each Stats module, say) is hidden or shown as a whole: macOS hides per app. To split them, merge or turn off modules in that app's own settings
- **Apps you built yourself, or downloaded from GitHub and the like without an Apple developer signature**: while any icon is hidden, macOS doesn't show their menu bar icons, even set to Show. That's macOS's rule: YoungBar gives the system a list of apps allowed to stay on the menu bar, and the system only honours apps with an Apple-issued signature (found by testing; Apple doesn't document it). With nothing hidden they're unaffected. This version puts such icons in the strip, where you can open them; Settings lists them in a section of their own, "Kept off by macOS: fixed in the strip", with no Show or Hide of their own. To check an app: run `codesign -dv /Applications/SomeApp.app` in Terminal; `Developer ID Application` or `Apple` means it has one
- If something goes wrong, right-click ••• → Copy Diagnostics and paste it in the group, a comment or GitHub

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.2.0.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.2.0`）的源码归档 / this tag's source archive.
