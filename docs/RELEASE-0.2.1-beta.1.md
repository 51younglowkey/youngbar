# YoungBar 0.2.1 测试版 1 更新日志

这是测试版，可以不更新。它只修了下面几个问题：遇到了再更新；没遇到的话点「稍后」，等正式版就行。

## 优化

- 打开新版本时，旧的会先自己退出

## 修复

- 全屏时 ••• 跟菜单栏一起收起
- 收纳条里取不到图标时不再留空
- 启动时 ••• 不再先压在图标上
- 系统不显示的图标不再打乱顺序

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 全屏时把鼠标移到屏幕顶部，••• 会和菜单栏一起回来；用快捷键打开收纳条时也会出现。只在内建屏上测过，外接屏和多显示器还没测，所以先发测试版
- 「收纳条多了一个没有图标的占位」是按推断修的，没有在作者的机器上复现。更新后还有的话，请右键 ••• →「复制诊断信息」发给我
- 「0.1.6 更新到 0.2.0 后无法打开 -47」**还没有找到原因，这一版没有修**。遇到的话请把完整的提示截图，连同你是怎么安装的（app 里更新、一键安装命令，还是下载后拖进「应用程序」）发给我
- 菜单栏设为「自动隐藏」时，••• 仍然会留在屏幕上，这一版没有处理
- 0.1.7 及更早的版本读不懂测试版的版本号，在 app 里检查更新会提示出错；可以等正式版，或者用 README 里的一键安装命令

# English

This is a test version, and you can skip it. It only fixes the problems below: update if you have one of them; otherwise click Later and wait for the final version.

## Improved

- Opening a new version quits the old one first

## Fixed

- In full screen the ••• leaves with the menu bar
- No empty slot in the strip for a missing icon
- At launch the ••• no longer sits on an icon
- Icons macOS keeps off no longer reorder

## Requirements

- macOS 27 or later on an Apple silicon Mac; earlier systems (macOS 26 and before) can't open it
- Device Control and Data Access (Accessibility) permission; no screen recording

## Notes

- In full screen, move the pointer to the top of the screen and the ••• comes back with the menu bar; it also shows when the shortcut opens the strip. Tested on a built-in display only, not on external or multiple displays, which is why this is a test version first
- The "extra slot with no icon in the strip" fix is an inference; it wasn't reproduced on the author's Mac. If it is still there after updating, right-click ••• → Copy Diagnostics and send it over
- "Can't be opened, -47" after updating 0.1.6 to 0.2.0 **has no known cause yet and is not fixed here**. If you see it, send a screenshot of the whole message and how you installed (in-app update, the one-line install, or a download dragged into Applications)
- With the menu bar set to hide automatically, the ••• still stays on screen; not handled in this version
- 0.1.7 and earlier can't read a test version's number, so checking for updates in the app reports an error; wait for the final version or use the one-line install from the README

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.2.1-beta.1.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.2.1-beta.1`）的源码归档 / this tag's source archive.
