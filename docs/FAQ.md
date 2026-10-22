# FAQ：IP、许可证、私有 API 与分发

> 这不是法律意见。公开或商业发布前，请让律师确认。

## 1. 不开源、不盈利，可以用 Chiikawa 角色吗？

**不可以默认认为可以。** 不盈利不等于获得授权：

- 角色形象受版权保护，公开仓库和 Release 属于公开分发。
- 角色名/标识可能涉及商标；把它用作产品主题名，可能让人误以为官方联名。
- 权利人通常对个人 fan art 较宽容，但宽容不是许可，也不能保证不会被下架。
- 开源后别人可以再分发，风险会被放大。

更稳妥的做法：

- 公开版换成原创吉祥物（保留蓝/粉/黄配色即可）。
- 或者只在本地个人使用，不公开带这些素材的构建。
- 如果确实想用，先取得权利人书面许可。

## 2. 可以把 GPLv3 改成 MIT 吗？

不能直接改。许可证取决于代码版权：

- `Vendor/PelmetCore`、`Vendor/PelmetEngine` 来自 Dimble，是 **GPLv3**。
- 把它们链接进同一个 app 并分发时，整个组合作品要按 GPLv3 提供源码。
- 你自己的原创代码可以单独 MIT，但只要最终二进制包含 GPLv3 代码，就不能把整个项目改成 MIT。
- 想 MIT，只有两条路：移除/重写所有 GPLv3 代码，或把 GPL 部分拆成独立进程并让律师确认边界。

GPLv3 与是否盈利无关：它允许收费，但要求源码、许可证和修改说明。角色 IP 是另一套权利，和代码许可证无关。

## 3. 私有 API 是什么？还需要做接口吗？

不是网络接口。`MenuBarClientCore` 是 macOS 未公开的系统框架接口，Dimble/Pelmet 用它创建“评估模式”断言来隐藏菜单栏项目。

- 没有公开 API 可以隐藏第三方菜单栏项；这是目前能稳定做到的方式。
- 它没有兼容性承诺，macOS 更新可能失效；App Store 不接受。
- 打包成 .app 不会消除这个依赖，只是把风险藏进 app 里。
- 工程上应做能力探测、失败降级和兼容性测试，而不是再写一套“接口”。

## 4. 怎么让别人一键用上？

推荐顺序：

1. **GitHub Release + 签名/公证的 .app**：用户下载 DMG/zip，拖进 Applications。
2. **Homebrew Cask**：`brew install --cask youngbar`，升级也走 brew。
3. **安装脚本**：`curl -fsSL .../install.sh | sh`，下载最新 Release、移动到 /Applications；适合其他 Agent，但要说明 Gatekeeper 与权限。
4. **源码构建**：`git clone && sh Scripts/build.sh && open build/YoungBar.app`，适合开发者和 Agent。

辅助功能和屏幕录制必须由用户在系统设置里手动授权，任何安装方式都不能完全自动化。没有 Developer ID 时只能 ad-hoc 签名，权限可能因重建而重置。

## 5. 缓存里有什么？

`~/Library/Application Support/YoungBar/pictures.json` 保存菜单栏条带的裁剪图，用来让收纳条瞬间打开。它可能包含未读计数、股价等敏感信息。

当前策略：最多 120 项、14 天、编码后 8 MB；超出时丢最旧的。菜单里可以随时清除缓存。
