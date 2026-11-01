# YoungBar（羊霸霸）状态板

> 只写**当前**状态和它的证据。0.1.0 及之前的阶段记录（截图缓存、旧 AppKit 设置窗口等）
> 已原样移到 [`JOURNAL.md`](JOURNAL.md) 附录。
>
> 最后核对：**2026-11-01 02:40 +00:00**，版本 **0.1.3 (4)**（2.2 的修复），MacBook 内建屏（1800×1169，刘海 790–1010pt），macOS 27。

## 1. 构建

| 项 | 值 | 证据 |
|---|---|---|
| 命令 | `sh Scripts/build.sh` → `build/YoungBar.app` | 构建通过（2026-10-29） |
| 工具链 | 只需命令行工具：Swift 6.4（CLT 27.0，2026-10-26 安装），**不需要 Xcode** | `swift --version`；包内不再使用 `@State`（宏插件只随 Xcode） |
| 测试版构建 | `TESTHOOKS=1 sh Scripts/build.sh`：编入 `TestHooks.swift` 的真机自检 | 正式版 `strings` 中 `YOUNGBAR_*TEST` 0 处；`otool -L` 无 ScreenCaptureKit |
| 单元测试 | `swift test --disable-sandbox`：17 项（排序、溢出判断、快捷键、配置文件） | 17 passed |
| 签名 | 本地 `YoungBar Local Signing` 证书；重建后辅助功能授权保持 | `codesign -dv`；重建后自检仍 `axTrusted:true` |

## 2. 当前行为与证据（0.1.1）

| 项 | 状态 | 证据 |
|---|---|---|
| 空闲 CPU | ✅ 0.32–0.33%（0.1.0：约 1.7%，40 小时累计 41 分钟） | 60 秒 `ps -o time` 差值，两次 |
| 刷新节奏 | ✅ 收纳条/设置打开或有定时展开时 1 秒；空闲 4 秒；应用启动退出、唤醒、显示器变化立即刷新 | `refreshInterval`、`startRefreshTriggers` |
| 快捷键打开收纳条 | ✅ 真实按键 ⌃⌥B 打开，收纳条成为键盘焦点，前台应用不变 | `keyboardtest.json`：`openedByShortcut`、`stripIsKey`、`frontAppStillFront` |
| 键盘导航 | ✅ 打开即选中第一项；→ 1、←← 绕回 4；Esc 先清搜索再关闭 | `selectionAfterOpen:0`、`selectionAfterRight:1`、`selectionAfterTwoLeft:4`、`queryClearedByEsc`、`closedByEsc` |
| 搜索 | ✅ 输入 "ifa" 只剩 iFan 且被选中；⌫ 删一字；无匹配显示「没有匹配的项目」 | `matches`、`searchFoundTarget`、`queryAfterDelete:"if"`、`noMatchCount:0`；![搜索](images/shelf-search.png) |
| 自定义快捷键 | ✅ 改成 ⌃⌥⌘Y 后真实按键能打开、旧的 ⌃⌥B 失效；测试后恢复 ⌃⌥B | `openedByCustom`、`oldShortcutIgnored`、`restoredDisplay`；8 组组合各按一次均打开 1 次（`hotkeyprobe.json`） |
| 放不下的图标 | ✅ 把 5 个隐藏项临时全部显示：macOS 把有道收进 «，YoungBar 识别并列进收纳条；恢复后为空 | `overflowtest.json`：`overflowAllShown:[有道]`、`stripListsOverflow`、`restored`、`overflowAfter:[]` |
| 拥挤时的 ••• | ✅ 不再跟着被收进 « 的项跑到刘海下面；缩窄后停在 « 左侧 | ![拥挤的菜单栏](images/menubar-overflow.png) |
| 配置导入导出 | ✅ 导出 → 改一个选项 → 导入，模式、选项、顺序全部还原 | `configtest.json`：`passed:true` |
| 首次启动引导 | ✅ 新安装显示；老用户升级自动标记已看过；授权状态每秒刷新 | ![引导](images/guide.png) |
| 收纳条打开 | ✅ 21ms，不临时显示任何图标 | `shelfopen.json`：`openMs:21`、`revealedOnOpen:0` |
| 显示 → 自动收起 | ✅ | `selftest.json`：`appeared`、`autoHidden`、`goneAgain` |
| 测试后复原 | ✅ `itemModes`、`hiddenBundles` 与测试前备份相同；`barOptions` 只多了 `onboarded:1` | `defaults export` 前后对比 |

![通用（0.1.1）](images/general-0.1.1.png)

## 2.1 应用内更新（0.1.2，未发布）

| 项 | 状态 | 证据 |
|---|---|---|
| 已是最新 | ✅ 当前 0.1.1 对线上 0.1.1：显示「已是最新版本」 | `updatetest.json`：`state:upToDate` |
| 发现新版本 | ✅ 测试版假装 0.1.0：找到线上 0.1.1，显示更新说明 | `state:available`、`offered:0.1.1`；![更新](images/update-available.png) |
| 签名检查 | ✅ 本 app 通过；同一份 app 用 ad-hoc 重签后被拒 | `selfAccepted:true`、`sigcheckAccepted:false` |
| 端到端安装 | ✅ 下载 → SHA-256 → 解压 → 版本/签名检查 → 正常退出 → 脚本换 bundle → 重新打开；新进程 PID 不同，`build/YoungBar.app` 变成 GitHub 上的 0.1.1 发布包 | `update.log`：`installed 0.1.1 at …/build/YoungBar.app`；`strings` 无测试钩子 |
| 升级后权限 | ✅ 新版本照常隐藏图标（辅助功能授权保留） | 升级后菜单栏截图只剩常显项 |
| 更正 | 第一次端到端时卡在「正在安装」：在并发任务里直接调 `NSApp.terminate` 与 `applicationShouldTerminate` 的异步回复互相等待（`sample` 显示主线程停在 `-[NSApplication _shouldTerminate]` 的嵌套事件循环）。改为 run loop 上的 `perform` 后通过 | `sample` 输出；第二次 `update.log` |

## 2.2 用户反馈：多出一个 •••（2026-11-01，0.1.3）

小红书与交流群反馈「三个点和菜单栏图标重叠」「会多三个点 / 两个隐藏 logo」。

| 项 | 状态 | 证据 |
|---|---|---|
| 原因 | 控件是一块浮在菜单栏上的面板，下面垫着 YoungBar 自己的原生状态项（标题 `•••`）占位。有隐藏断言时 macOS 不绘制这个状态项；**没有要隐藏的项时**（新用户、隐藏的应用都没在运行）引擎撤掉断言，macOS 就把 `•••` 画出来，和浮动控件叠在一起 | `noassertiontest.json`：`assertionBare:false`，原生项 x 1037.5、控件 x 1035；![修复前](images/no-assertion-before.png)（爱心控件旁露出原生 `•••` 的点） |
| 修复 | 原生状态项改为空白占位（无标题，保留 accessibility label），只由浮动控件画图标 | `nativeTitle:""`；![修复后](images/no-assertion-after.png) 只剩一个控件 |
| 复现方式 | `YOUNGBAR_NOASSERTIONTEST=1`（可加 `YOUNGBAR_NOASSERTION_HOLD=秒`）：临时给引擎空模型，不改保存的模式，结束后恢复 | 两次运行均 `restored:true`，`concealedAfter` 与 `concealedBefore` 相同 |
| 单元测试 | 23 passed | `swift test --disable-sandbox` |

边界：本机控件图标是爱心；用户用的默认省略号没有单独截图，但原生项与控件位置的重叠关系相同。没有在拥挤（« 收走）的同时又无断言的状态下测过。

边界：只测了 `build/` 下、目录可写的情况；`/Applications` 里由非管理员用户运行（目录不可写）时会提示去 GitHub 手动下载，没有实测。下载中途取消没有实测。

## 2.3 0.1.4 进行中（2026-11-01，Info.plist 已是 0.1.4 (5)，未发布、未打包）

> 本节取代第 2 节里「快捷键打开收纳条」「搜索」「自定义快捷键」三行：默认快捷键已不是 ⌃⌥B，搜索已移除。

| 项 | 状态 | 证据 |
|---|---|---|
| 自动检查更新 | ✅ 启动 10 秒后、之后每天一次查 GitHub；假装 0.1.2 时找到 0.1.3：控件右上角出现主题色圆点，右键菜单第一行「有新版本 0.1.3，点此更新…」，**不弹窗、不自动安装**。始终开启，设置里没有开关 | `autoupdatetest.json`：`found:0.1.3`、`badge:true`、`windowOpened:false`；![圆点](images/update-badge.png) |
| 默认快捷键：连按两下 ⌘ | ✅ 真实按键连按两下 ⌘ 打开收纳条（键盘焦点在收纳条，前台应用不变）；⌘ 后接 ⌘⇧、两次间隔 0.7 秒都不触发；改成 ⌃⌥⌘Y 后能打开、⌘⌘ 失效；测试后恢复 | `keyboardtest.json`：`passed:true`、`defaultDisplay:"双击 ⌘"`、`commandShiftIgnored`、`slowTapsIgnored`、`doubleCommandIgnoredAfterChange`；另一个进程发出的 ⌘⌘ 也能打开（截图） |
| 设置里录快捷键 | 🟡 可以录组合键，或连按两下 ⌘ / ⌥ / ⌃；连按的识别逻辑有单元测试，**设置窗口里真的录一次没有实测** | `DoubleTapDetectorTests` 5 项 |
| 去掉搜索 | ✅ 收纳条里打字不再筛选；Esc 直接关闭 | `typingIgnored:true`、`closedByEsc:true` |
| 数字键 1–9 | ✅ 键盘打开时前 9 个图标标出数字；按数字直接打开（ChatGPT 菜单在收纳条旁弹出）；超过图标数的数字只响一声 | `digitPressed:true`（`digitTarget: codex`）、`digitPastEndIgnored:true`；![数字](images/strip-numbers.png) |
| 收纳条里拖动排序 | ✅ 真实鼠标把第一个拖到最后：收纳条和保存的顺序都跟着变，菜单栏没有任何图标被显示；测试后恢复顺序 | `shelfdragtest.json`：`stripReordered`、`savedOrderFollows`、`nothingRevealed`、`orderRestored` |
| 新图标自动收纳（默认关） | ✅ 打开选项后，把 State 当作新图标：自动设为隐藏并收进收纳条，提示「新图标已放进收纳条：State」；第一次运行（没有保存过顺序）不会触发；Apple 的图标不受影响；测试后恢复 | `autohidetest.json`：`modeAfter:1`、`concealed`、`inStrip`、`shownAgain`、`restored` |
| 更新内容窗口 | ✅ 从 0.1.3 升到 0.1.4 后第一次启动自动弹出；按「新增 / 优化 / 移除 / 修复」分区、每条一句短话，不含安装命令和校验；••• 菜单「本次更新内容…」可再打开；新安装不弹 | 真实启动截图；`extrastest.json`：`whatsNewShown`、`notesHaveNoInstall`；![更新内容](images/whats-new-0.1.4.png) |
| 复制诊断信息 | ✅ ••• 菜单一项：复制 8 行纯文本（版本、macOS、机型、屏幕/刘海、权限与隐藏状态、快捷键、控件位置、各状态图标名单）并弹窗显示内容 | `extrastest.json`：`reportLines:8`、`report` |
| 收纳条图标右键 | ✅ 菜单列出另外两种状态和「在设置中调整…」；选「始终隐藏」后该图标离开收纳条；测试后恢复 | `menuTitles`、`modeAfterMenu:2`、`leftStrip`、`restored` |
| 数字显示开关 | ✅ 「图标下方显示数字」默认开；关掉后数字键照样能打开 | 设置截图；`shelfNumbered` 读这个选项 |
| 设置精简 | ✅ 去掉：点击 ••• 方式（「在菜单栏中展开」会重影，已删除该模式）、始终显示收纳条、点击空白处展开、放不下的图标进收纳条（固定开）、自动收起秒数（固定 20 秒）、主题应用范围（固定全部）、右键菜单「左键显示菜单」、自动检查更新开关、刷新列表按钮；权限行只在未授权时显示。通用页分为：基本 / 收纳条 / 关于 | ![通用](images/general-0.1.4.png) ![外观](images/appearance-0.1.4.png) |
| 单元测试 | 31 passed | `swift test --disable-sandbox` |
| 测试后复原 | ✅ 键盘测试前后 `defaults export` 只差 `sessionActive`（运行标记） | diff |

边界：老用户如果从没改过快捷键，升级后默认从 ⌃⌥B 变成连按两下 ⌘（改过的保留）。数字键之外的拖动只在 3 个图标、收纳条不滚动时测过。自动收纳只用「假装新图标」测过，没有真的装一个新应用。去掉的选项：老用户之前存的值会被忽略（例如开过「始终显示收纳条」的人升级后不再常开）。`YOUNGBAR_SETTINGSUITEST`（真实鼠标走设置窗口）本轮没有重跑。

## 3. 验证边界（不许含糊）

- **多显示器没有验证**（手头只有内建屏）。已做的只是代码层面：显示器增减时把控件放回状态项旁；
  空白处点击、溢出判断只看控件所在那块屏；兜底位置用主屏而不是「当前有键盘焦点的屏」。
- 溢出只在「把隐藏项全部显示」这一种拥挤方式下实测过一次；被 « 收走的是有道。
  « 菜单里的项从收纳条点开时走 AXPress，没有单独真机点过。
- 键盘测试中收纳条里的按键是直接送给处理函数的（不是真实键盘事件），只有快捷键本身是真实按键。
  第一次跑自定义快捷键时 ⌃⌥⌘Y 有一次没打开，之后 3 轮共 10 次都正常；推测是测试期间有真实鼠标点击把收纳条关了，未确认。
- 系统级快捷键（如输入法切换）会抢在 YoungBar 之前，注册时 macOS 不报冲突，所以这种冲突检测不到。
- 设置测试（`YOUNGBAR_SETTINGSUITEST`，真实鼠标）本轮没有重跑：它会接管鼠标。
- 图标间隙需要重启才能看到效果；开机自启动没有真的登出再登录过。
- 一次重启后，两个隐藏项（Figma、iFan）的保存顺序按 macOS 的实际顺序校准了，与测试前备份不同；这是既有的「顺序跟随真实菜单栏」行为。

## 4. 下一步

1. 有第二块显示器时验证：控件、收纳条位置、点开隐藏项。
2. 从收纳条点开被 « 收走的项。
3. 重启验证图标间隙；登出验证开机自启动。
