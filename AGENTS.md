# AGENTS.md — YoungBar（羊霸霸）

> YoungBar 的操作须知。2026-10-23 起这是**独立仓库**（从 Leorea 的 `youngbar/` 拆出，保留了历史），不要把 Leorea 的 Windows 外设内容带进来。

## 1. 项目边界

- 只做 macOS 27 的菜单栏收纳工具：隐藏 / 展开 / 排序 / 原地打开 / 快捷键 / 外观。
- 最低系统 **macOS 27**（Apple 芯片；macOS 27 不支持 Intel），对外统一说「只支持 macOS 27 及以上」。写在 `Info.plist` 的 `LSMinimumSystemVersion`、`Package.swift` 与 `Vendor/*/Package.swift` 的 `platforms`、`Scripts/install.sh` 开头的检查，以及 README（中英）、`docs/INSTALL.md`、`docs/FAQ.md` 第 6 条、更新日志的「要求 / Requirements」；要改就一起改。
- 代码在 `Sources/YoungBar/`，依赖在 `Vendor/`（Dimble 的 PelmetCore / PelmetEngine，GPLv3）。
- 记录在 `docs/STATUS.md`（只写当前验证状态；历史在 `docs/JOURNAL.md`）与 `docs/IBAR-FEATURES.md`（iBar 对照表）。独立之前的轮次记在 Leorea 的 `docs/JOURNAL.md`。
- 不要依赖仓库外的路径（例如原来的 `../../app`、`../../projects`）。
- 日常开发在私有仓库 `51younglowkey/youngbar-dev`（本地 remote 叫 `origin`）；公开仓库 `51younglowkey/youngbar`（本地 remote 叫 `public`）只在发布时接收 main 和对应 tag，例如 `git push public main v0.1.5`。公开仓库不要改成私有。代码和 README 里的仓库地址（`Updater.swift`、`install.sh`）继续指向公开仓库，不要改成 dev。按 GPLv3，每个发布出去的版本，在公开仓库都要有对应 tag 的源码。

## 2. 构建与运行

```sh
sh Scripts/build.sh                    # release → build/YoungBar.app（不含测试钩子）
TESTHOOKS=1 sh Scripts/build.sh        # 带真机自检的测试版
swift test --disable-sandbox           # YoungBarCore 单元测试（报找不到 TestingMacros 插件时，加 -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing；2026-11-06 重跑和换 --scratch-path 都没用，这样才行）
open build/YoungBar.app
```

- CI：`.github/workflows/ci.yml` 每次推送在 Linux 上跑单元测试，在 GitHub 的 `xcode-27` 机器（macOS 27 SDK，Swift 6.4）上编译测试版和正式版并跑 `Scripts/verify.sh`。CI **只证明能编译**，不碰菜单栏；真机行为仍要按第 5 节自检。`install-script.yml` 在 `install.sh` 改动、发布新版本时和每周一次，在 macOS 27 上用 README 的一键安装装线上最新版，再覆盖更新一次：证明脚本和发布包的签名对得上（AppleScript 退出那一段不测）。私有仓库里分支推送只跑 Linux 单元测试；要 macOS 编译证据就开（草稿）PR 或手动触发 CI；`install-script.yml` 在公开仓库自动跑；私有仓库里只有 main 改了 `install.sh` 或它自己时才跑（云端会话用 GitHub 集成手动触发 workflow 会被拒：403 Resource not accessible by integration）。私有仓库的 CI 还跑 `Scripts/check-commits.sh`，检查这次带来的提交的作者和尾注（见第 5 节）。
- 没有 Mac 时（例如云端会话）：`Package.swift` 在 Linux 上只声明 YoungBarCore 和测试，`swift test --disable-sandbox` 可以在 `swift:6.4-noble` 容器里跑；YoungBarCore 里导入 CoreGraphics 要写成 `#if canImport(CoreGraphics)`。
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
  main.swift            BarApp 的状态、启动/退出、刷新节奏、顺序校准、名称与图标查找（~610 行）
  ControlPanel.swift    ••• 控件（每块屏的菜单栏一个面板，`ControlSlot`；外观跟随各自的菜单栏）、右键菜单、菜单栏按钮图片
  MenuBarLook.swift     问窗口服务器当前桌面的菜单栏是深是浅（SkyLight 私有调用，运行时解析，拿不到就回到按钮的外观）
  Shelf.swift           收纳条的打开与绘制、空收纳条的「点图标收进来」、从收纳条原地打开（AXPress / 显示后点击）
  LayoutActions.swift   显示方式、排序、全部隐藏/显示、交给引擎的模型（currentModel）
  SettingsBridge.swift  设置窗口的回调、权限、登录项、图标间隙
  EngineSync.swift      让引擎跟上外面：运行中的应用、新启动应用的接纳窗口、引擎事件、锁屏时不遍历
  ShelfKeyboard.swift   收纳条键盘导航、数字键 1–9（ShelfPanel，非激活面板也能拿键盘焦点；没有搜索）
  ShelfItems.swift      收纳条图标：拖动排序（只改保存的顺序，不 reveal）、右键改显示方式
  WhatsNew.swift        更新后第一次启动：先「本次更新内容」，再一步步的新功能引导（可跳过）；和使用引导一样跟随 **YoungBar 设置里的语言**。引导页在 `UpdateIntroModel.steps` 里按版本写，没写的版本只显示更新内容
  NotesView.swift       更新内容 / 更新窗口里的说明，按「区块 + 短句」绘制（YoungBarCore 的 ReleaseNotes.blocks）
  HotKey.swift          全局快捷键：组合键走 Carbon；默认「连按两下 ⌘」用全局/本地事件监视器（YoungBarCore 的 DoubleTapDetector）
  NotchOverflow.swift   被 macOS « 收走 / 被刘海挡住的图标（按收纳条所在的屏算）；显示器变化时同步每块屏的控件
  ShutOutIcons.swift    设为显示、但隐藏生效时被 macOS 拿掉的图标（没有 Apple 签名的应用）：找出来放进收纳条
  ConfigTransfer.swift  配置导入导出
  Guide.swift           首次启动引导。更新后不再走（用户要求，0.1.6 起）：更新后只显示「更新内容」；更新后权限丢了时，设置窗口的菜单栏页有授权按钮
  Preferences.swift     `Option`：barOptions 的键（磁盘上仍是 [String: Int]）
  BarSettings.swift     设置窗口的 AppKit 外壳，把 SettingsAction 转给 BarApp
  SettingsView.swift    设置窗口内容（SwiftUI）：侧栏、菜单栏 / 外观 / 通用三页（按使用频率排，打开时总是先显示菜单栏页；未授权时授权按钮也在菜单栏页），Form .grouped
  Theme.swift           配色、主题图（缓存）、控件图标
  Diagnostics.swift     运行态 JSON（YOUNGBAR_DIAGNOSTICS=1）；「复制诊断信息」的纯文本报告（摘要 + ••• 的只读检查 + 最近 60 条事件）
  FlightRecorder.swift  飞行记录器：本机 `events.log`（最多 500 行，重启不丢），记 ••• 每次移动和谁移动的（YoungBar 自己 / 外部）、屏幕排列、切桌面、睡眠唤醒、权限、引擎事件。复制诊断信息时带上最近的部分；行文只用英文
  TestHooks.swift       真机自检，只在 TESTHOOKS=1 构建时编译
Sources/YoungBarCore/   纯逻辑（事件日志、••• 的位置与检查（ControlLayout）、排序与落点、溢出判断、快捷键组合与保存值校验、配置文件、更新日志、收纳条内容、图片缩放、默认语言、菜单栏外观值），有单元测试；Linux 上也能编译
Tests/YoungBarCoreTests/
Vendor/
  PelmetCore            菜单栏模型、策略、ItemID、搜索排序（SearchRanker）
  PelmetEngine          隐藏/展开/排序、MenuBarClientCore 评估接口
```

- 更新器（`Updater.swift`）：启动 10 秒后、之后每天一次后台查 GitHub（始终开启，没有开关）；有新版本只在右键菜单第一行加「有新版本」（和控件的提示文字），菜单栏上不加圆点（用户要求），**不自动安装**。点「检查更新」时立即查。安装：下载 zip + .sha256 → 校验 → 解压 → 版本号、bundle id、签名（`SecStaticCodeCheckValidity` 对照本 app 的 designated requirement）→ 起一个 sh 脚本等本进程退出后换 bundle、`open`。**不要在 Swift 并发任务里直接调 `NSApp.terminate`**：`applicationShouldTerminate` 返回 `.terminateLater` 后 AppKit 在嵌套事件循环里等回复，而回复也是 main actor 任务，会死锁；用 `NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)`。
- **引擎的两种「显示」**：`reveal(_ sections)` 由 `conceal()` 收回；`reveal(items:)` **只有** `conceal(items:)` / `conceal(releasing:)` 收得回，`conceal()` 不管它。没收回的单个图标会一直留在菜单栏，改成隐藏也藏不住（0.1.4 及之前排序、改显示方式、导入都踩过）。每个 `reveal(items:)` 都要有配对的收回；清空 `shownUntil` 时用 `conceal(releasing: 那些项)`。
- **引擎不会自己知道外面发生了什么**：运行中的应用要 `setRunningBundles` 推给它（EngineSync 用 KVO 盯 `runningApplications`；`didLaunchApplicationNotification` 不保证覆盖只有菜单栏图标的应用）；隐藏生效时 macOS 把新注册的菜单栏图标停在屏幕外，要 `openAdoptionWindow` 才会落位（会闪一下：只对「显示」的应用在启动时开，「隐藏」的等第一次按它时再开；这期间它不在引擎的快照里，靠 `parkedKeys` 留在收纳条和设置里）；`engine.events` 要读，断言被撤掉时重新 `setModel`，但同一布局反复失败要停（藏不住的图标会让引擎一直重建断言）。后台同步用 `syncing` 标记，不要用 `busy`（`busy` 会让点击和快捷键直接被忽略）。
- **断言只放行有 Apple 签发签名的应用**：自签或 ad hoc 的应用（自己编译的），放行名单里有它，隐藏生效时 macOS 照样不显示它的图标，MenuBarAgent 的 AX 树里也没有它（YoungBar 自己的状态项同理）。让它回到菜单栏的办法没有（试过先隐藏再放行、写位置），所以 `shutOutKeys`（`ShutOutIcons.swift`，判断在 `YoungBarCore/ShutOut.swift`）把这类设为显示的图标放进收纳条和设置，模式不改。**认出来之后就不再看模式**：只有遍历重新列出它（一个图标都不隐藏了）或它的应用退出，才离开 `shutOutKeys`；设置里它在单独一段「系统不显示：固定在收纳条里」，没有显示/隐藏控件、不能拖，收纳条右键也没有模式项，点它一律原地 AXPress（reveal 对它没用）。曾经按「模式是显示」过滤，用户把它点成隐藏后两段都没有它，也没有行可以点回来。另一条路：保存为隐藏的自签应用启动时被正常藏起来（这时它是普通的隐藏行），一改成显示就同时离开 `concealed` 和遍历；`unlistedKeys`（上次刷新还在列表、这次哪都不在、应用还在跑）让它留着行，3 秒后去问它自己的 AX 树（`Watch.eagerPatience`；`setMode` 里 `shutOutWatch.forget` 让改模式后重新问）。查「图标不见了」先 `codesign -dvv` 看那个应用的签名，不要先怀疑 «。
- 「全部隐藏」是 `bulkHiddenKeys`：叠在保存的模式上（只含应用图标，不含系统图标），收纳条列出它们，`currentModel()` 带上它们，「全部显示」「恢复」或改任何一个图标时清掉。
- **多显示器（0.1.8）**：macOS 给每块屏画一条菜单栏，同一个状态项每条栏上各有一份（`engine.barCopies()`），`EngineSnapshot` 只留主屏那份。所以：① 每块有菜单栏的屏一个 •••（`controlSlots`，关掉「显示器具有单独的空间」时只有主屏有）；② ••• 只看自己那条栏上的图标（`barIcons` → `ControlLayout`），判断在不在某条栏要同时看 x 和 y（上下摆放的屏 x 完全重叠）；③ ••• 的纵坐标永远从那块屏的菜单栏算，不保留旧值（曾经只更新 x，用户那边 ••• 停在屏幕右下方）；被外部移出菜单栏时不等下一次遍历，当场放回（`controlDidMove`）；④ 收纳条开在点击的 ••• 或鼠标所在的屏（`anchorDisplayID`，关闭后回到主屏）；从外接屏点系统图标要点那条栏的副本（`pressAim`），AXPress 只在图标位置就在这块屏时才用。不要用「在屏幕右半边」这类判断：窄屏或图标多时不成立。
- ••• 的颜色：控件面板的 `appearance` 取当前桌面的菜单栏外观（`MenuBarLook`，`SLSGetMenuAppearanceThemeOnSpace`：0 浅、1 深；不建状态项，不要屏幕录制），不跟 `NSApp.appearance`（用户在 YoungBar 里选的外观）。切桌面（`activeSpaceDidChangeNotification`）和每次刷新都同步。YoungBar 状态项按钮的外观**启动后不再变**，只用来回退：接口没了，或者第一次刷新时和按钮对不上（`checkMenuBarTheme`：调用失败也读成 0，宁可不跟桌面，也不要在深色栏上画深色 •••）。面板用 `.vibrantDark` / `.aqua` 这一对：`.darkAqua` 比旁边的图标暗，`.vibrantLight` 比旁边的图标淡。
- 刷新：每次刷新是一次完整 AX 遍历，耗 CPU。收纳条/设置打开或有定时展开时 1 秒一次，空闲 4 秒一次；应用启动退出、唤醒、显示器变化立即刷新。设置窗口不可见时不要重建它的模型。
- 溢出：macOS 27 菜单栏满时在左端（刘海右侧）放一个 «，放不下的项 AX 位置互相重叠地堆在那里。判断规则在 `YoungBarCore/Overflow.swift`（与 Pelmet `PlacementGeometry.overflowTrapped` 相同）。

- 收纳条显示**应用图标**（系统项用 SF Symbol），打开时不临时 reveal 任何东西。截图方案（缓存菜单栏像素、显示拍摄时间、AX 实时文字）试过并被用户否决：分辨率低、发糊；会变的数值应该留在菜单栏常显区。
- 点收纳条里的第三方项：对隐藏状态下的 AXMenuBarItem 直接 AXPress（不 reveal、不动鼠标、••• 不漂移）；系统项没有 AXPress，才 reveal + 点击，点击时隐藏光标。
- 日期与控制中心位置由 macOS 固定，不能拖；**可以隐藏**。

## 5. 验证纪律

- 每条结论必须有证据：`~/Library/Application Support/YoungBar/*.json`、截图、或命令输出。
- **所有自检都要先 `TESTHOOKS=1 sh Scripts/build.sh`**；正式版忽略这些环境变量。
- 自检开关（环境变量）：`YOUNGBAR_SELFTEST`、`YOUNGBAR_INTERACTIONTEST`、`YOUNGBAR_ORDERTEST`、`YOUNGBAR_MENUTEST`、`YOUNGBAR_HOTKEYTEST`、`YOUNGBAR_PINNEDTEST`、`YOUNGBAR_GEARTEST`、`YOUNGBAR_SHELFOPENTEST`、`YOUNGBAR_ABOUTTEST`、`YOUNGBAR_CONCEALTEST`。
- `YOUNGBAR_NOASSERTIONTEST`：没有要隐藏的项时的菜单栏（引擎撤掉断言，macOS 会绘制原生状态项），检查不会多出一个 •••；`YOUNGBAR_NOASSERTION_HOLD=秒` 保持以便截图。
- 0.1.2 新增：`YOUNGBAR_UPDATETEST`（查 GitHub、记录结果和窗口号；`YOUNGBAR_SIGCHECK_PATH` 检查某个 app 是否与本 app 同证书；`YOUNGBAR_UPDATE_INSTALL=1` 真的安装）。配合 `YOUNGBAR_UPDATE_PRETEND_VERSION=0.1.0`（仅测试版）可以端到端升级到线上最新版：它会**替换正在运行的 bundle**（`build/YoungBar.app`），测完要重新 `sh Scripts/build.sh`。
- 0.1.4 新增：`YOUNGBAR_EXTRASTEST`（更新内容窗口、诊断文本、收纳条图标右键改为始终隐藏再恢复；`YOUNGBAR_EXTRAS_HOLD=秒`）、`YOUNGBAR_AUTOUPDATETEST`（配合 `YOUNGBAR_UPDATE_PRETEND_VERSION`：后台检查→菜单行、不弹窗；`YOUNGBAR_AUTOUPDATE_HOLD=秒`）、`YOUNGBAR_SHELFDRAGTEST`（真实鼠标在收纳条里拖动排序，检查保存顺序、没有 reveal，结束恢复顺序）、`YOUNGBAR_AUTOHIDETEST`（把一个显示中的应用图标当成新图标，检查自动收纳，结束恢复）。`YOUNGBAR_KEYBOARDTEST` 改为真实按键连按两下 ⌘、⌘⇧ / 慢按不触发、数字键、自定义快捷键并恢复；`YOUNGBAR_KEYBOARD_DIGIT=1` 时还会用数字键真的点开一个第三方项的菜单再 Esc。
- 0.1.5 新增：`YOUNGBAR_APPEARANCETEST`（外观设置依次切到跟随系统 / 浅色 / 深色，检查 ••• 每次都和菜单栏一致；`YOUNGBAR_APPEARANCE_HOLD=秒` 每步停留以便截图）、`YOUNGBAR_EMPTYSHELFTEST`（临时显示所有「隐藏」让收纳条变空，检查提供的图标、点一个收进来、收纳条不关，结束恢复）、`YOUNGBAR_LAUNCHTEST=<bundle id>`（**会真的退出并重开那个应用**，挑没有文档的菜单栏小工具；显示的应用检查图标回来，隐藏的检查不在菜单栏、但在收纳条和设置里）。`YOUNGBAR_BARLOOKTEST=<秒>`：记录这段时间里窗口服务器（`space`、`theme`、`bar`）、状态项按钮和 ••• 读到的外观每一次变化，配合外面切桌面（`osascript -e 'tell application "System Events" to key code 124 using control down'`，123 是向左）；`passed` 要求 ••• 和 `bar` 不一致不超过 2 秒，`launchCheckAtEnd` 是结束时跑一次启动核对的结果；`YOUNGBAR_BARLOOK_DISTRUST=1` 按「核对没过」跑，••• 应该只跟按钮。`YOUNGBAR_SHELFOPENTEST` 多查淡入后不透明度为 1，`YOUNGBAR_OVERFLOWTEST` 多查设置里「放不下」的标记；菜单栏没挤满时 `crowded:false`、不给 `passed`，`inconclusive` 写原因（多开几个带菜单栏图标的应用再跑）。`YOUNGBAR_CONTROLYTEST`：把 ••• 人为下移半个菜单栏，检查下一次刷新回到和图标平齐（`controlytest.json` 的 `levelAfter`）。自检里临时改的显示方式只放内存，不写进 defaults。
- `YOUNGBAR_FLIGHTTEST`：等 ••• 稳定后，从外部把它远移、近移各一次，检查日志分得清外部移动和 YoungBar 自己的动画移动、大幅移动计数、屏幕变化、诊断报告里的检查结果和 `events.log`；结束时 ••• 回到原位（`flighttest.json`）。测试行会留在 `events.log`，测完退出后删掉这个文件。
- 0.1.8 新增：`YOUNGBAR_DISPLAYTEST`（当前排列下每块屏：一个 •••、在菜单栏内、不压图标、外观对；挪到屏幕右下角后当场回来；收纳条开在这块屏；点图标瞄准这条栏的副本。不点任何东西，但会开关收纳条、抢键盘焦点；`YOUNGBAR_DISPLAY_POINTER=1` 还会把鼠标挪到每块屏再挪回；`YOUNGBAR_DISPLAY_HOLD=秒`；结果在 `displaytest.json`，`walk` 是这次遍历每个图标的主屏位置和各条栏上的副本）。`YOUNGBAR_DISPLAYCLICKTEST`：每块屏用真实鼠标悬停、点击、右键 •••，再从收纳条点开系统图标（输入法）和应用图标（`YOUNGBAR_DISPLAYCLICK_APP=<bundle id>`，默认 iFan，但它点开不弹窗口，判不了，用 `com.steipete.codexbar` 这类有菜单的；不是隐藏的会临时隐藏，只放内存），查菜单窗口在这块屏，Esc 关掉；会动鼠标；结果在 `displayclicktest.json`。截菜单栏用全局坐标（`screencapture -x -R 1800,-424,1920,31`），`-D` 对 `-R` 不起作用；活动屏跟点击走，不跟鼠标移动。`swift Scripts/display-lab.swift` 把这个自检跑过各种排列（左右上下、外接屏当主屏、低分辨率、镜像，`--with-off` 再加软件关屏）再恢复，每一步还记下 ••• 窗口 8 秒内的位置（`<步骤>-dots.txt`）；`--only <步骤>` 只跑一种；`--baseline <App>` 拿没有自检的旧版本跑，只记位置，用来做修前修后对比。macOS 改排列时会把面板挪到离原位很远的地方（0.1.7 上 1 秒左右才回来），这不是 YoungBar 挪的。**这个脚本会改显示器排列（只在本次登录有效），属于改系统设置：由作者自己运行，Claude 不运行**；Claude 只跑 `--dry-run`、读结果（`~/Library/Application Support/YoungBar/display-lab/<时间>/summary.txt`）。
- 0.1.1 新增：`YOUNGBAR_KEYBOARDTEST`（快捷键打开、方向键、Esc、自定义快捷键并恢复）、`YOUNGBAR_HOTKEYPROBE`（多组快捷键各按一次）、`YOUNGBAR_OVERFLOWTEST`（临时显示全部隐藏项制造拥挤，记录被 « 收走的项，恢复模式和顺序；`YOUNGBAR_OVERFLOW_HOLD=秒` 保持拥挤状态以便截图）、`YOUNGBAR_CONFIGTEST`（导出→改→导入）、`YOUNGBAR_SHOWGUIDE` / `YOUNGBAR_SHOWSETTINGS=general|layout|appearance`（打开窗口并把 windowNumber 写进 JSON，配合 `screencapture -l <id>` 截真实窗口）。
- 本机 shell 可以直接 `screencapture -x -R 700,0,1100,38` 截菜单栏；`cacheDisplay` 的离屏渲染没有窗口背景，深色模式下文字会看不见，不能当外观证据。
- 设置窗口交互：`open --env YOUNGBAR_SETTINGSUITEST=1 build/YoungBar.app`。用真实鼠标/键盘事件测试逐项模式菜单、拖动排序、右键移动、切换语言，结束后复原；结果在 `settingsuitest.json`。测试期间不要碰鼠标键盘。`YOUNGBAR_EXPECT_ORDER`（逗号分隔）可指定要恢复到的顺序。自检期间窗口会拉到屏幕那么高（这里没有滚动列表的办法，行在窗口外就点不到），结束时还原。`YOUNGBAR_SETTINGSUI_SHUTOUT=<bundle id>`：先把一个自签应用设成显示、等它进固定段再开始，检查带着固定行时其余操作照常（`fixedRowsAtStart`）。
- `YOUNGBAR_SHUTOUTTEST=<bundle id>`（一个在运行、没有 Apple 签发签名的菜单栏应用）：开着设置的菜单栏页，像设置里那样在显示 / 隐藏之间来回切，每 0.1 秒看它的行在哪一段；要求行从不消失（`neverGone`）、设为显示后进固定段并留在那里、在收纳条里、分段没乱，结束把保存的模式改回去（`shutouttest.json`，`steps` 里是每一步见到的段）。`YOUNGBAR_SHUTOUT_PRESS=1` 还会从收纳条点它、记下打开的窗口、Esc 关掉；`YOUNGBAR_SHUTOUT_HOLD=秒` 留着窗口以便截图（窗口号在 `shutout-window.json`）。固定段是运行时的状态：测完它还在固定段，重启 YoungBar 后按保存的模式回到原样。
- 构建时可以不退出正在运行的 YoungBar：`build.sh` 会整包替换，不再原地覆盖可执行文件。**但构建完要重启它**：运行中的进程和磁盘上的 app 对不上时，登录项查询和注册都报 error 22，设置里的「登录时打开」显示关闭、也打不开（2026-11-04 遇到过，重启后恢复；登录项本身没丢）。
- 从 worktree 跑 app 时，`refreshLoginItemIfMoved` 见到路径变了会把登录项改注册到 worktree。启动前先 `defaults write studio.wuyiyang.youngbar loginItemToken "<worktree>/build/YoungBar.app|<CFBundleVersion>"`，退出后写回原值，再开回主目录的 app：登录项不动，defaults 也和备份一样。
- 模拟全新安装要 `defaults delete` 掉 `itemModes`、`hiddenBundles`、`lastLaunchedVersion`、`sessionActive` 和 `barOptions` 里的 `onboarded`：`defaults import` 只合并，不删键。导入运行中导出的备份时先把 `sessionActive` 改成 false，否则下次启动走崩溃恢复。模拟升级只要 `defaults write … lastLaunchedVersion <旧版本>`。
- 设置窗口截图：`open -n --env YOUNGBAR_SETTINGS_PREVIEW=zh build/YoungBar.app`（或 `=en`）。只开设置窗口、**不碰菜单栏**，可以和正在运行的 YoungBar 并存；深浅两套截图写到 `~/Library/Application Support/YoungBar/preview-*.png`，然后自动退出。
- 自检会动真实菜单栏：点击、隐藏、拖动。**结束后必须恢复原状态**；测试打开的面板/菜单要关闭。
- 改状态数字时同步更新 `docs/STATUS.md`；结论变了追加「更正第 N 轮」，不改历史条目。
- 提交前：`sh Scripts/build.sh` 通过；`git status` 只包含预期文件。
- **提交作者一律是 51Young**（项目的硬性要求）：作者和提交者都是 `51Young <193584257+51younglowkey@users.noreply.github.com>`；不用 Claude 署名，也不加 `Co-Authored-By: Claude…`、`Claude-Session:` 之类的尾注。云端会话是新克隆的，第一次提交前先在仓库里 `git config user.name` / `git config user.email` 设好，提交后用 `git log --format='%an <%ae> | %cn'` 看一眼。`.claude/settings.json` 关掉了 Claude 的署名，但云端会话同时挂两个仓库时不读这个文件，那时要自己保证。私有仓库的 CI 用 `Scripts/check-commits.sh` 查每次带来的提交（本地也能跑：`sh Scripts/check-commits.sh origin/main..HEAD`）；github.com 上合并产生的提交由 GitHub 署名，只查作者名。私有仓库是 GitHub 免费版，设不了分支保护：**这个检查红了也能点合并，合并前要自己看**。网页合并会把作者写成账号的 Gmail，`gh pr merge --author-email` 又不接受 noreply 地址；要合并提交也符合规则，就本地 `git merge --no-ff` 后推送，GitHub 会自动把 PR 标记为已合并。

## 6. UI 与设计

- **混合结构**：设置窗口内容用 SwiftUI（`Form` + `.formStyle(.grouped)`，对齐 System Settings 的间距、对齐和控件），菜单栏控件、收纳条、右键菜单和所有改菜单栏的逻辑保持 AppKit。
- 设置页里不要再手写坐标；新选项就是 `Section` 里加一行：名称在左、控件在右、说明用第二个 `Text`。布尔值用开关。
- **选项要少**（0.1.4 用户要求）：能定成合理默认的就不做开关。0.1.4 去掉了：点击 ••• 的方式、始终显示收纳条、点击空白处展开、放不下的图标进收纳条（固定开）、自动收起秒数（固定 20 秒）、主题应用范围（固定全部）、左键显示菜单、自动检查更新开关、刷新列表按钮；权限行只在未授权时出现。加新开关前先想能不能直接定默认。
- **更新日志**：`docs/RELEASE-<版本>.md` 先中文、再单独一行 `# English`、再英文（GitHub 两段都显示，app 按 YoungBar 设置的语言只显示一段）。「新增 / 优化 / 移除 / 修复」每条一句话、十来个字（app 里原样显示）；开头可以有一段作者的话；「说明 / Notes / 校验」只在 GitHub 上看，app 会跳过。
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
- 不要用 `conceal()` 收回 `reveal(items:)` 显示的单个图标（见第 4 节）；不要在 Swift 并发任务里直接 `runModal`（会卡住所有主线程任务，用 `perform(_:with:afterDelay:)` 放到 run loop 上）。
- 不要让 ••• 控件面板成为 key window：它会抢走前台应用的键盘焦点。
