# YoungBar 0.2.1 更新日志

这是 0.2.1 正式版，包含测试版的全部修复，并修好了测试版里 ••• 有时看不见的问题。

## 修复

- 测试版里 ••• 有时看不见
- 打开新版本时，旧的会先自己退出
- 全屏时 ••• 跟菜单栏一起收起
- 收纳条里取不到图标时不再留空
- 启动时 ••• 不再先压在图标上
- 系统不显示的图标不再打乱顺序

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 0.2.1 测试版 1 判断「全屏」只看系统给的一个值，有的 Mac 上会把普通桌面当成全屏，••• 就一直透明、点不到（issue #10）。现在还要前面的窗口自己确实是全屏，才收起 •••
- 全屏时把鼠标移到屏幕顶部，••• 会和菜单栏一起回来。只在内建屏上测过，外接屏、分屏全屏还没测；遇到问题请右键 ••• →「复制诊断信息」发给我，诊断里现在会写 ••• 的不透明度和全屏状态
- 「收纳条多了一个没有图标的占位」是按推断修的，没有在作者的机器上复现
- 「0.1.6 更新到 0.2.0 后无法打开 -47」还没有找到原因。遇到的话请把完整的提示截图，连同安装方式发给我
- 菜单栏设为「自动隐藏」时，••• 仍然会留在屏幕上

# English

This is the final 0.2.1. It has every fix from the test version, and fixes the test version's ••• sometimes not showing.

## Fixed

- The test version's ••• sometimes didn't show
- Opening a new version quits the old one first
- In full screen the ••• leaves with the menu bar
- No empty slot in the strip for a missing icon
- At launch the ••• no longer sits on an icon
- Icons macOS keeps off no longer reorder

## Requirements

- macOS 27 or later on an Apple silicon Mac; earlier systems (macOS 26 and before) can't open it
- Device Control and Data Access (Accessibility) permission; no screen recording

## Notes

- 0.2.1 test version 1 decided "full screen" from one value macOS gives, and on some Macs it took an ordinary desktop for full screen: the ••• then stayed transparent and couldn't be clicked (issue #10). Now the front window itself has to be in full screen before the ••• tucks away
- In full screen, move the pointer to the top of the screen and the ••• comes back with the menu bar. Tested on a built-in display only, not on external displays or split-view full screen; if something is off, right-click ••• → Copy Diagnostics and send it over, which now includes the •••'s opacity and full-screen state
- The "extra slot with no icon in the strip" fix is an inference; it wasn't reproduced on the author's Mac
- "Can't be opened, -47" after updating 0.1.6 to 0.2.0 has no known cause yet. If you see it, send a screenshot of the whole message and how you installed
- With the menu bar set to hide automatically, the ••• still stays on screen

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.2.1.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.2.1`）的源码归档 / this tag's source archive.
