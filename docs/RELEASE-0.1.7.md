# YoungBar 0.1.7 更新日志

## 新增

- 诊断信息带上最近的事件记录
- 诊断信息会检查 ••• 的位置
- 诊断弹窗可以打开日志文件
- GitHub 上有了反馈问题的表单

## 要求

- macOS 27 或更新，Apple 芯片的 Mac；更早的系统（macOS 26 及以前）打不开
- 设备控制与数据访问（辅助功能）权限；不需要屏幕录制

## 说明

- 遇到问题时，右键 ••• →「复制诊断信息」，再贴到群里、评论区或 GitHub
- 事件记录包括 ••• 的位置变化、屏幕和桌面变化、权限变化和图标名称，不含窗口内容；完整记录在 `~/Library/Application Support/YoungBar/events.log`

# English

## New

- Diagnostics include recent events
- Diagnostics check where the ••• is
- The diagnostics alert can show the log file
- A form for reporting bugs on GitHub

## Requirements

- macOS 27 or later on an Apple silicon Mac; it won't open on earlier versions (macOS 26 and before)
- Device Control and Data Access (Accessibility) permission; no Screen Recording

## Notes

- If something looks wrong, right-click ••• → Copy Diagnostics, then paste it into a chat, a comment or GitHub
- Events cover moves of the •••, display and desktop changes, permission changes and icon names, nothing from your windows; the full log is `~/Library/Application Support/YoungBar/events.log`

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.1.7.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.1.7`）的源码归档 / this tag's source archive.
