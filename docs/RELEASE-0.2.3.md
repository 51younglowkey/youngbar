# YoungBar 0.2.3 更新日志

## 修复

- 不在「应用程序」文件夹的应用不再反复闪回菜单栏
- 「应用程序」文件夹里自己编译的应用可以正常显示和隐藏

## 优化

- 「系统不显示」一段说明了怎么让图标回来

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 0.2.2 以为 macOS 按签名决定隐藏时显示谁的图标，这是错的。实际看的是应用装在哪里：有图标隐藏时，macOS 只显示装在「应用程序」文件夹（/Applications，含子文件夹）里的应用的图标，跟签名无关（issue #11）
- 从「下载」文件夹、磁盘映像（dmg）或 ~/Applications 直接打开的应用，即使有官方签名，图标也会被 macOS 拿掉。0.2.2 会反复把它放回菜单栏（每次闪一下），3 次后才放进收纳条；现在一开始就放在「系统不显示：固定在收纳条里」
- 想让它回到菜单栏：把应用拖进「应用程序」文件夹，从那里重新打开
- 反过来，装在「应用程序」文件夹里的自签应用（自己编译的）以前被错放进那一段，现在和其他图标一样可以设为显示或隐藏

# English

## Fixed

- Apps outside Applications no longer flash back onto the bar
- Self-built apps in Applications can be shown and hidden

## Improved

- The "Kept off by macOS" section says how to get icons back

## Requirements

- macOS 27 or later on an Apple silicon Mac; earlier systems (macOS 26 and before) can't open it
- Device Control and Data Access (Accessibility) permission; no screen recording

## Notes

- 0.2.2 assumed macOS decides by signature which icons stay while others are hidden. That was wrong: it goes by where the app is installed. While any icon is hidden, macOS only shows the icons of apps in the Applications folder (/Applications, subfolders included), whatever their signature (issue #11)
- An app opened straight from Downloads, a disk image (dmg) or ~/Applications loses its icon even with an official signature. 0.2.2 kept putting it back on the bar (a brief flash each time) and moved it to the strip after 3 tries; now it goes to "Kept off by macOS: fixed in the strip" from the start
- To get its icon back on the bar, move the app into the Applications folder and open it from there
- The other way round, self-signed apps (ones you built yourself) in the Applications folder were wrongly put in that section; now they can be set to Show or Hide like any other icon

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.2.3.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.2.3`）的源码归档 / this tag's source archive.
