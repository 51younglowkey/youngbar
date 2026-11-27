# YoungBar 0.2.2 更新日志

## 修复

- 有官方签名的应用不再被固定在收纳条里

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 有用户反馈：从 GitHub 下载的 Tendedero（有 Developer ID 签名、经过公证）设为显示，却出现在「系统不显示：固定在收纳条里」那一段，回不到菜单栏。这一段本来只该放没有 Apple 签发签名的应用（比如自己编译的），隐藏生效时 macOS 不显示它们的图标
- 现在 YoungBar 只在签名明确不是 Apple 签发时才把应用放进这一段；查不准时按有签名处理。有签名的应用的图标不在菜单栏上时，先把它放回菜单栏（会像新开应用时一样闪一下），同一个应用 10 分钟内最多 3 次
- 作者的机器上没有复现那位用户遇到的情况，这次是按两条可能的原因一起修的。还遇到的话，请右键 ••• →「复制诊断信息」发给我
- 自己编译的应用（自签或 ad hoc 签名）在有图标隐藏时仍然只能放在收纳条里，这是 macOS 的限制

# English

## Fixed

- Apps with an official signature are no longer fixed in the strip

## Requirements

- macOS 27 or later on an Apple silicon Mac; earlier systems (macOS 26 and before) can't open it
- Device Control and Data Access (Accessibility) permission; no screen recording

## Notes

- A user reported that Tendedero from GitHub (Developer ID signed and notarized), set to Show, was listed under "Kept off by macOS: fixed in the strip" and never came back to the menu bar. That section is meant only for apps without an Apple-issued signature (ones you built yourself, say), whose icons macOS doesn't show while anything is hidden
- YoungBar now puts an app there only when its signature is known not to be Apple-issued; when the check can't tell, it counts as signed. When a signed app's icon is off the bar, YoungBar puts it back (with the same brief flash as when an app opens), at most 3 times in 10 minutes per app
- The user's case wasn't reproduced on the author's Mac; both likely causes are fixed. If it still happens, right-click ••• → Copy Diagnostics and send it over
- Apps you build yourself (self-signed or ad hoc) still stay in the strip while icons are hidden: that's a macOS limit

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.2.2.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.2.2`）的源码归档 / this tag's source archive.
