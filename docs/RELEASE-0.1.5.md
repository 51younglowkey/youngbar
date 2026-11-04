# YoungBar 0.1.5 更新日志

## 新增

- 收纳条空着时，点图标就能收进来
- 设置里标出菜单栏放不下的图标

## 优化

- 收纳条打开时轻轻淡入
- 新安装跟随系统语言
- 自定义按钮图片不再变形
- 登录项要批准时会提示
- 检查更新失败后一小时重试
- 锁屏时不再读取菜单栏
- 安装更新更稳妥，失败会留着旧版

## 修复

- ••• 跟随菜单栏颜色，不再看不清
- 新打开的应用图标不再消失
- 排过序的图标也能再隐藏
- 点开图标后改设置，图标会收回
- 「全部隐藏」只藏应用图标，并放进收纳条
- 退出的应用不再留在收纳条
- 导入配置不会再导致闪退
- ••• 不再抢键盘焦点
- ••• 不再掉到菜单栏下面

## 说明

- 菜单栏上的 ••• 现在跟着菜单栏本身的颜色，和 YoungBar 设置里的「外观」无关
- 隐藏生效时新打开一个带菜单栏图标的应用，隐藏的图标会闪一下：这是让 macOS 把它的图标放回菜单栏

# English

## New

- Tuck icons in from an empty strip
- Settings marks icons that didn't fit

## Improved

- The strip fades in as it opens
- New installs start in your Mac's language
- Custom button pictures keep their shape
- Login item approval is explained
- A failed update check retries in an hour
- No menu-bar reads while the screen is locked
- Safer updates: a failed install keeps the old app

## Fixed

- ••• follows the menu bar's colour
- Icons of apps opened later no longer vanish
- Icons you reordered can be hidden again
- Icons opened from the strip go back after a change
- "Hide all" hides app icons only, into the strip
- Apps that quit no longer linger in the strip
- Importing a layout can no longer crash YoungBar
- ••• no longer takes keyboard focus
- ••• no longer drops below the menu bar

## Notes

- The ••• on the menu bar now follows the bar itself, whatever Appearance you choose in YoungBar
- Opening an app with a menu-bar icon while icons are hidden makes them flash once: that is macOS putting the new icon on the bar

## 校验 / Checksum

```sh
shasum -a 256 -c YoungBar-0.1.5.zip.sha256
```

对应源码 / Corresponding source：本 tag（`v0.1.5`）的源码归档 / this tag's source archive.
