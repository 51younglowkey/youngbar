# YoungBar 0.1.8 更新日志

这个版本主要解决多显示器和不同屏幕上 ••• 跑位的问题。

## 新增

- 每块屏的菜单栏都有自己的 •••
- 点哪块屏的 •••，收纳条就开在哪块屏
- 快捷键打开收纳条时，开在鼠标所在的屏

## 优化

- 外接屏上点开图标，菜单也开在外接屏
- 不活动屏幕上的 ••• 会和菜单栏一起变暗
- 诊断信息列出每块屏的 ••• 和图标

## 修复

- ••• 被挪出菜单栏时会立刻回来
- 接显示器或改排列时 ••• 不再乱跑
- 窄屏、图标多时 ••• 不再和图标重合

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 遇到问题时，右键 ••• →「复制诊断信息」，再贴到群里、评论区或 GitHub

# English

This version mainly deals with multiple displays and the ••• ending up in the wrong place.

## New

- Every display's menu bar has its own •••
- The strip opens on the display whose ••• you click
- The shortcut opens the strip on the display with the pointer

## Improved

- Icons opened on an external display show their menus there
- The ••• dims with the menu bar on the inactive display
- Diagnostics list each display's ••• and icons

## Fixed

- The ••• comes straight back if it gets moved off the menu bar
- The ••• no longer wanders when displays connect or move
- The ••• no longer overlaps icons on a narrow or crowded bar

## Requirements

- macOS 27 or later on an Apple silicon Mac; earlier systems (macOS 26 and before) can't open it
- Device Control and Data Access (Accessibility) permission; no screen recording

## Notes

- If something goes wrong, right-click ••• → Copy Diagnostics and paste it in the group, a comment or GitHub

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.1.8.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.1.8`）的源码归档 / this tag's source archive.
