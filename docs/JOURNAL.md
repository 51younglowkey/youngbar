# YoungBar Journal

YoungBar 在 2026-10-23 从 Leorea 的 `youngbar/` 拆成独立仓库（保留历史）。
独立之前的第 1–147 轮记录在 Leorea 的 `docs/JOURNAL.md`；从本轮开始记在这里。

---

## 2026-10-23 · 独立仓库与 OPS 5.5 大改（观察记录）

- **仓库**：`~/Documents/General_Workspace/YoungBar`，私有远程
  [`51younglowkey/youngbar`](https://github.com/51younglowkey/youngbar)。
  观察时 `main` 与 `origin/main` 同步在 `8fab9f0`，工作区干净；远程 `pushedAt`
  为 2026-10-23T20:11:37Z。Leorea 内的旧 `youngbar/` 已由 `00e2b34` 删除，
  Leorea `README` 由 `7eaa2c6` 指向新仓库。
- **设置窗口**：`4605c70` 改为 SwiftUI `Form(.grouped)` + 侧栏 List，AppKit
  只保留 `NSWindow + NSSplitViewController` 外壳。三页：通用 / 菜单栏 / 外观；
  去掉手写坐标；每项显示状态改为一行菜单；语言原地刷新；窗口记住位置。
- **设置交互**：`f230584` 修正分组 Form 的 `onMove` 不响应拖动，改为
  `draggable + dropDestination`；新增 `YOUNGBAR_SETTINGSUITEST` 真机测试
  逐项模式、拖动、右键移动、切换语言，测试后恢复备份。证据
  `settingsuitest.json`：`modePassed/dragPassed/languagePassed:true`（02:30）。
- **外观**：`feeaf60` 把蓝/粉/黄统一为 OKLCH 同亮度同彩度；收纳条材质改为
  30–100% 不透明度滑块；恢复主题色玻璃、侧栏角色图、色块名字、40pt 图标格；
  分段按钮替代两步下拉。
- **收纳条**：`ea54e9c` 改为应用图标（系统项 SF Symbol），删除
  `StatusPictures.swift` 与截图缓存，**不再需要屏幕录制**；隐藏项点击改为
  直接 AXPress（不 reveal、不动鼠标、••• 不漂移）；系统项仍 reveal+点击。
  `870db8a` 把收纳条改回 ••• 正下方居中，并在 app 路径变化时自动重登登录项。
  `8fab9f0` 在按下前读 AX 位置，只有靠近 ••• 才原地按，否则显示后点击；
  诊断新增 `axX`。
- **构建**：`build.sh` 先组装/签名 staging 再整包替换，运行中重建不再被
  `Code Signature Invalid` 杀掉。App 用本地 `YoungBar Local Signing` 证书签名。
- **本轮核对**：`diagnostics.json` 20:07，`axTrusted:true`、`itemCount:11`；
  `settingsuitest.json` 02:30 全通过，但那之后 `ea54e9c` 删了设置里的屏幕录制行，
  **整套设置测试没有再跑**。当前版本 `0.1.0 (1)`。
- **仍然未验证 / 未做**：多显示器；图标间隙重启后的实际间距；开机自启动
  登出再登录；真实触控板拖动手感；英文菜单栏页截图；系统项 reveal+点击路径；
  可配置快捷键、键盘导航、收纳条内拖拽排序、配置导出。
- **文档整理**：`STATUS.md` 追加 4.7 当前基线，并明确 2 / 4.1–4.6 为历史；
  `README.md` 修正独立仓库的构建路径与 known gaps；`IBAR-FEATURES.md` 顶部
  标明 5.5 起不再截图/缓存；FAQ / INSTALL / SIGNING 删除了已不存在的
  屏幕录制与 `pictures.json` 缓存说明。旧缓存/屏幕录制/旧 AppKit 设置的描述保留为历史，
  不再作为现状。
