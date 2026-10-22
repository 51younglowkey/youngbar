# AGENTS.md — YoungBar（羊霸霸）

> 这是 `youngbar/` 子项目的操作须知。**它最终会被拆成独立仓库开源**，不要把 Leorea 的 Windows 外设内容带进来。

## 1. 项目边界

- 只做 macOS 27 的菜单栏收纳工具：隐藏 / 展开 / 排序 / 原始图标 / 快捷键 / 外观。
- 代码在 `Sources/YoungBar/`，依赖在 `Vendor/`（Dimble 的 PelmetCore / PelmetEngine，GPLv3）。
- 记录在 `docs/STATUS.md`（验证状态）与 `docs/IBAR-FEATURES.md`（iBar 对照表）。跨项目轮次记到仓库根部的 `docs/JOURNAL.md`。
- 本目录可以整体复制成独立仓库；不要依赖 `../../app`、`../../projects`、`../../rea` 等外部路径。

## 2. 构建与运行

```sh
cd youngbar
sh Scripts/build.sh                    # release → build/YoungBar.app
open build/YoungBar.app
```

- `Scripts/build.sh` 带 `--disable-sandbox`：SwiftPM 的 manifest 沙箱无法嵌套在宿主沙箱里。
- 产物是 ad-hoc 签名；**重建后系统权限可能需要重新授权**（辅助功能 / 屏幕录制）。
- 改代码后先构建，再启动 `build/YoungBar.app`；不要直接跑 `.build/release/YoungBar`（会丢 bundle 权限身份）。

## 3. 权限

| 权限 | 用途 | 没有时 |
|---|---|---|
| 设备控制与数据访问（辅助功能） | 枚举、隐藏、展开、排序菜单栏项 | 收纳条为空，只有设置页 |
| 屏幕录制 | 抓原始菜单栏像素 | 回退为应用图标 |

macOS 27 的界面叫「设备控制与数据访问」，不是旧的「辅助功能」。

## 4. 架构

```
Sources/YoungBar/
  main.swift          AppDelegate、控制条、收纳条、菜单、测试钩子（~1600 行）
  BarSettings.swift   设置窗口（侧栏 + 通用设置 / 菜单栏布局）
  StatusPictures.swift 菜单栏条带抓图、磁盘缓存
  Diagnostics.swift   运行态 JSON（YOUNGBAR_DIAGNOSTICS=1）
Vendor/
  PelmetCore          菜单栏模型、策略、ItemID
  PelmetEngine        隐藏/展开/排序、MenuBarClientCore 评估接口
```

- 收纳条点击**只读缓存**，不临时 reveal；抓图只在首次缓存为空、手动刷新时发生。这是为了不闪图标。
- 时钟/电池不缓存（会显示旧值），统一走 SF Symbol。
- 日期与控制中心位置由 macOS 固定，不能拖；**可以隐藏**。

## 5. 验证纪律

- 每条结论必须有证据：`~/Library/Application Support/YoungBar/*.json`、截图、或命令输出。
- 自检开关（环境变量）：`YOUNGBAR_SELFTEST`、`YOUNGBAR_INTERACTIONTEST`、`YOUNGBAR_ORDERTEST`、`YOUNGBAR_MENUTEST`、`YOUNGBAR_CACHETEST`、`YOUNGBAR_HOTKEYTEST`、`YOUNGBAR_PINNEDTEST`、`YOUNGBAR_ALWAYSHIDDENTEST`、`YOUNGBAR_GEARTEST`、`YOUNGBAR_SHELFOPENTEST`、`YOUNGBAR_ABOUTTEST`、`YOUNGBAR_CONCEALTEST`。
- 自检会动真实菜单栏：点击、隐藏、拖动。**结束后必须恢复原状态**；测试打开的面板/菜单要关闭。
- 改状态数字时同步更新 `docs/STATUS.md`；结论变了追加「更正第 N 轮」，不改历史条目。
- 提交前：`sh Scripts/build.sh` 通过；`git status` 只包含预期文件。

## 6. UI 与设计

- AppKit，原生控件优先；统一 8pt 网格；正文 13、说明 11、标题 22。
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
- 不要把测试钩子暴露成普通用户功能；未来应移到独立 target 或 `#if DEBUG`。
- 不要在收纳条打开路径里重新引入“临时显示全部图标”的抓图流程（用户明确讨厌闪烁）。
- 不要提交 `build/`、`.build/`、`pictures.json`、诊断 JSON。
