# YoungBar 0.1.2

## 新功能

- **应用内更新**：••• 菜单或「通用 → 更新」里的「检查更新…」会查询 GitHub 最新版本。有新版本时显示更新说明，点「安装并重新打开」：在本地下载、校验 SHA-256、确认签名证书与当前 app 相同，然后正常退出（隐藏的图标先恢复显示）、替换并自动重新打开。
- 只有点「检查更新」时才会访问 GitHub，不会自动联网。

## 说明

- 0.1.1 及更早的版本还没有更新器，这一次请用安装命令或手动下载升级；之后的版本可以在 app 里直接更新。
- 如果 YoungBar 所在的文件夹不可写，或你用的是自己从源码编译的版本，更新器会提示到 GitHub 手动下载。

## 安装 / 升级

```sh
curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
```

## 校验

```sh
shasum -a 256 -c YoungBar-0.1.2.zip.sha256
```

对应源码：本 tag（`v0.1.2`）的源码归档。
