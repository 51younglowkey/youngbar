# YoungBar 0.1.4 更新日志

昨天在曼彻斯特现场看了英超，曼城 0:1 输给布莱顿，有点伤心。不过没关系，我已经更新好新的版本啦！

## 新增

- 连按两下 ⌘ 打开收纳条
- 图标快捷键（1–9）
- 收纳条里拖动排序
- 右键图标改显示方式
- 新图标自动收纳（可选）
- 有新版本时右键菜单会提示
- 更新后显示更新内容和新功能引导
- 复制诊断信息：遇到 bug 时复制发到群里给我，感谢大家的支持！

## 优化

- 设置项精简，分类更清楚
- 设置打开先显示「菜单栏」页
- 图标下方数字可以关掉
- 点击 ••• 只打开收纳条

## 移除

- 收纳条打字搜索
- 「在菜单栏中展开」：和新系统兼容不好，功能不完善，先取消

## 修复

- 多出一个 •••（占位项被系统画出，已改为空白）
- 刚启动时 ••• 位置不对，点不到
- 悬停打开后点击会关掉收纳条

## 说明

- 默认快捷键从 ⌃⌥B 改为连按两下 ⌘，自己改过的不变
- 以后有新版本，右键 ••• 菜单会提示更新

# English

I was in Manchester yesterday watching Man City lose 0–1 to Brighton. A bit gutted — but no worries, the new version is ready!

## New

- Press ⌘ twice to open the strip
- Number keys 1–9 open icons
- Drag to reorder in the strip
- Right-click an icon to change it
- Auto-hide new icons (optional)
- Updates show in the right-click menu
- What's new and a short tour after updating
- Copy Diagnostics: paste it to me when something breaks. Thanks for the support!

## Improved

- Fewer, clearer settings
- Settings opens on Menu Bar
- Icon numbers can be turned off
- Clicking ••• only opens the strip

## Removed

- Typing to search in the strip
- "Show in bar": not reliable on the new macOS, so it's gone for now

## Fixed

- An extra ••• (a placeholder macOS drew; now blank)
- ••• in the wrong place just after launch
- Hover-open followed by a click closed the strip

## Notes

- The default shortcut is now ⌘ pressed twice instead of ⌃⌥B; a shortcut you changed stays
- New versions now show in the ••• right-click menu

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.1.4.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.1.4`）的源码归档 / this tag's source archive.
