# YoungBar 0.1.3

## 修复

- **菜单栏多出一个 •••**：没有需要隐藏的图标时（刚装好还没隐藏任何东西，或隐藏的应用都没在运行），YoungBar 的 ••• 旁边会再叠一个「•••」，看起来像两个隐藏按钮重叠在一起。现在只会显示一个。

## 安装 / 升级

0.1.2 用户：点 ••• 菜单或「通用」里的「检查更新…」，再点「安装并重新打开」。

0.1.1 及更早版本：

```sh
curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
```

## 校验

```sh
shasum -a 256 -c YoungBar-0.1.3.zip.sha256
```

对应源码：本 tag（`v0.1.3`）的源码归档。
