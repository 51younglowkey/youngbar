# AGENTS.md — YoungBar（羊霸霸）

> YoungBar 的操作须知。2026-10-23 起这是**独立仓库**（从 Leorea 的 `youngbar/` 拆出，保留了历史），不要把 Leorea 的 Windows 外设内容带进来。

## 1. 项目边界

- 只做 macOS 27 的菜单栏收纳工具：隐藏 / 展开 / 排序 / 原地打开 / 快捷键 / 外观。
- 代码在 `Sources/YoungBar/`，依赖在 `Vendor/`（Dimble 的 PelmetCore / PelmetEngine，GPLv3）。
- 记录在 `docs/STATUS.md`（只写当前验证状态；历史在 `docs/JOURNAL.md`）与 `docs/IBAR-FEATURES.md`（iBar 对照表）。独立之前的轮次记在 Leorea 的 `docs/JOURNAL.md`。
- 不要依赖仓库外的路径（例如原来的 `../../app`、`../../projects`）。

## 2. 构建与运行

```sh
sh Scripts/build.sh                    # release → build/YoungBar.app（不含测试钩子）
TESTHOOKS=1 sh Scripts/build.sh        # 带真机自检的测试版
swift test --disable-sandbox           # YoungBarCore 单元测试
open build/YoungBar.app
```

- 只需要命令行工具（Swift 6.4），不需要 Xcode。**不要用 `@State` 等 SwiftUI 宏**：它们的编译插件只随 Xcode 提供，CLT 上会编不过；视图状态放进 `SettingsModel` / `GuideModel`（`@Observable` 可以用，Observation 宏插件在 CLT 里）。

- `Scripts/build.sh` 带 `--disable-sandbox`：SwiftPM 的 manifest 沙箱无法嵌套在宿主沙箱里。
- 产物是 ad-hoc 签名；**重建后系统权限可能需要重新授权**（辅助功能）。
- 改代码后先构建，再启动 `build/YoungBar.app`；不要直接跑 `.build/release/YoungBar`（会丢 bundle 权限身份）。

## 3. 权限

| 权限 | 用途 | 没有时 |
|---|---|---|
| 设备控制与数据访问（辅助功能） | 枚举、隐藏、展开、排序菜单栏项 | 收纳条为空，只有设置页 |

macOS 27 的界面叫「设备控制与数据访问」，不是旧的「辅助功能」。

## 4. 架构

```
Sources/YoungBar/
  main.swift            AppDelegate、刷新节奏、控制条、收纳条、菜单、排序（~1400 行）
  ShelfKeyboard.swift   收纳条键盘导航与搜索（ShelfPanel，非激活面板也能拿键盘焦点）
  HotKey.swift          可自定义的 Carbon 全局快捷键
  NotchOverflow.swift   被 macOS « 收走 / 被刘海挡住的图标；显示器变化时重装控件
  ConfigTransfer.swift  配置导入导出
  Guide.swift           首次启动引导
  Preferences.swift     `Option`：barOptions 的键（磁盘上仍是 [String: Int]）
  BarSettings.swift     设置窗口的 AppKit 外壳，把 SettingsAction 转给 BarApp
  SettingsView.swift    设置窗口内容（SwiftUI）：侧栏、通用 / 菜单栏 / 外观三页，Form .grouped
  Theme.swift           配色、主题图（缓存）、控件图标
  Diagnostics.swift     运行态 JSON（YOUNGBAR_DIAGNOSTICS=1）
  TestHooks.swift       真机自检，只在 TESTHOOKS=1 构建时编译
Sources/YoungBarCore/   纯逻辑（排序、溢出判断、快捷键组合、配置文件），有单元测试
Tests/YoungBarCoreTests/
Vendor/
  PelmetCore            菜单栏模型、策略、ItemID、搜索排序（SearchRanker）
  PelmetEngine          隐藏/展开/排序、MenuBarClientCore 评估接口
```

- 刷新：每次刷新是一次完整 AX 遍历，耗 CPU。收纳条/设置打开或有定时展开时 1 秒一次，空闲 4 秒一次；应用启动退出、唤醒、显示器变化立即刷新。设置窗口不可见时不要重建它的模型。
- 溢出：macOS 27 菜单栏满时在左端（刘海右侧）放一个 «，放不下的项 AX 位置互相重叠地堆在那里。判断规则在 `YoungBarCore/Overflow.swift`（与 Pelmet `PlacementGeometry.overflowTrapped` 相同）。

- 收纳条显示**应用图标**（系统项用 SF Symbol），打开时不临时 reveal 任何东西。截图方案（缓存菜单栏像素、显示拍摄时间、AX 实时文字）试过并被用户否决：分辨率低、发糊；会变的数值应该留在菜单栏常显区。
- 点收纳条里的第三方项：对隐藏状态下的 AXMenuBarItem 直接 AXPress（不 reveal、不动鼠标、••• 不漂移）；系统项没有 AXPress，才 reveal + 点击，点击时隐藏光标。
- 日期与控制中心位置由 macOS 固定，不能拖；**可以隐藏**。

## 5. 验证纪律

- 每条结论必须有证据：`~/Library/Application Support/YoungBar/*.json`、截图、或命令输出。
- **所有自检都要先 `TESTHOOKS=1 sh Scripts/build.sh`**；正式版忽略这些环境变量。
- 自检开关（环境变量）：`YOUNGBAR_SELFTEST`、`YOUNGBAR_INTERACTIONTEST`、`YOUNGBAR_ORDERTEST`、`YOUNGBAR_MENUTEST`、`YOUNGBAR_HOTKEYTEST`、`YOUNGBAR_PINNEDTEST`、`YOUNGBAR_GEARTEST`、`YOUNGBAR_SHELFOPENTEST`、`YOUNGBAR_ABOUTTEST`、`YOUNGBAR_CONCEALTEST`。
- 0.1.1 新增：`YOUNGBAR_KEYBOARDTEST`（快捷键打开、方向键、搜索、Esc、自定义快捷键并恢复）、`YOUNGBAR_HOTKEYPROBE`（多组快捷键各按一次）、`YOUNGBAR_OVERFLOWTEST`（临时显示全部隐藏项制造拥挤，记录被 « 收走的项，恢复模式和顺序；`YOUNGBAR_OVERFLOW_HOLD=秒` 保持拥挤状态以便截图）、`YOUNGBAR_CONFIGTEST`（导出→改→导入）、`YOUNGBAR_SHOWGUIDE` / `YOUNGBAR_SHOWSETTINGS=general|layout|appearance`（打开窗口并把 windowNumber 写进 JSON，配合 `screencapture -l <id>` 截真实窗口）。
- 本机 shell 可以直接 `screencapture -x -R 700,0,1100,38` 截菜单栏；`cacheDisplay` 的离屏渲染没有窗口背景，深色模式下文字会看不见，不能当外观证据。
- 设置窗口交互：`open --env YOUNGBAR_SETTINGSUITEST=1 build/YoungBar.app`。用真实鼠标/键盘事件测试逐项模式菜单、拖动排序、右键移动、切换语言，结束后复原；结果在 `settingsuitest.json`。测试期间不要碰鼠标键盘。`YOUNGBAR_EXPECT_ORDER`（逗号分隔）可指定要恢复到的顺序。
- 构建时可以不退出正在运行的 YoungBar：`build.sh` 会整包替换，不再原地覆盖可执行文件。
- 设置窗口截图：`open -n --env YOUNGBAR_SETTINGS_PREVIEW=zh build/YoungBar.app`（或 `=en`）。只开设置窗口、**不碰菜单栏**，可以和正在运行的 YoungBar 并存；深浅两套截图写到 `~/Library/Application Support/YoungBar/preview-*.png`，然后自动退出。
- 自检会动真实菜单栏：点击、隐藏、拖动。**结束后必须恢复原状态**；测试打开的面板/菜单要关闭。
- 改状态数字时同步更新 `docs/STATUS.md`；结论变了追加「更正第 N 轮」，不改历史条目。
- 提交前：`sh Scripts/build.sh` 通过；`git status` 只包含预期文件。

## 6. UI 与设计

- **混合结构**：设置窗口内容用 SwiftUI（`Form` + `.formStyle(.grouped)`，对齐 System Settings 的间距、对齐和控件），菜单栏控件、收纳条、右键菜单和所有改菜单栏的逻辑保持 AppKit。
- 设置页里不要再手写坐标；新选项就是 `Section` 里加一行：名称在左、控件在右、说明用第二个 `Text`。布尔值用开关。
- **少一步点击**：两到四个选项一律用分段按钮（`.pickerStyle(.segmented)`），一下就选中；弹出菜单只留给选项多的场合（目前只有语言）。
- **保留个性**：窗口是带主题色的玻璃（`NSGlassEffectView`，染色 10%，内容区遮罩深色 46% / 浅色 58%），侧栏是系统侧栏毛玻璃 + 8% 主题色，顶部是主题角色大图；选中色、开关、分段按钮都跟随主题色。
- **配色规则**：蓝 / 粉 / 黄在 OKLCH 里取同一亮度和彩度，只换色相（强调色 L 0.70 C 0.13，收纳条色 L 0.55 C 0.12）。新增配色也按这个规则算，不要单独调某个颜色更亮。收纳条 = 系统毛玻璃 + 主题色 × 不透明度（`stripOpacity`，30–100）。
- 深色 / 浅色都要可用；收纳条用材质而不是死黑。
- 计划中的皮肤系统：颜色主题、透明样式、深浅模式；实现时把颜色收进一个 `Theme` 模型，不要散落硬编码。
- **不要像素级复制 iBar Pro**，也不要复制它的图片、图标、文案。行为参考可以，视觉要有自己的语言（奶油白 / 墨绿 / 粉色来自 app 图标）。
- 新控件要有 accessibility label 与 tooltip；尊重“减少动态效果”。

## 7. 许可与开源

- 本 app 是 **GPLv3**（因为 `Vendor/PelmetCore` / `Vendor/PelmetEngine`）。
- 保留 `LICENSE` 与来源说明：Dimble `23a5412`（0.3.2 / build 71），原 Pelmet。
- 开源时**新建干净仓库**，只带 `youngbar/`，不要带 Leorea 的 Windows 研究资产、厂商二进制或 iBar 资源。
- 发布前检查：没有个人绝对路径、没有 `.build/`/`build/`、没有 iBar 提取物。

## 8. 不要做

- 不要在没有恢复逻辑的情况下改用户的真实菜单栏顺序/可见性。
- 不要把测试钩子暴露成普通用户功能；新的自检写进 `TestHooks.swift`（`#if YOUNGBAR_TESTHOOKS`），不要放回 `main.swift`。
- 不要在收纳条打开路径里重新引入“临时显示全部图标”的抓图流程（用户明确讨厌闪烁），也不要再回到截图显示。
- 不要提交 `build/`、`.build/`、诊断 JSON。
