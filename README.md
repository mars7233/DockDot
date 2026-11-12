# DockDot

**把 Mac 的 Dock 收进一个小圆点。**

DockDot 在屏幕边缘放一个类似 iPhone「辅助触控」的半透明小圆点。点一下，或者在任何地方单按一下 **⌥⌘**，就会弹出一个液态玻璃圆盘，你 Dock 上的 App 均匀排成一圈。指向某个方向、点一下就打开。把系统 Dock 设成自动隐藏之后，屏幕上就几乎看不到 Dock 了。

![设置窗口：左边是在不同参考背景上的实时预览，右边是液态玻璃参数](docs/settings.png)

## 功能

- **悬浮小圆点**：可以拖到任意位置，松手会吸附到最近的屏幕边缘，并记住位置。不用的时候半透明，鼠标移上去变清楚。
- **⌥⌘ 快捷键**：单独按一下 ⌥⌘ 就会在鼠标位置打开面板，再按一下收起。按住 ⌥⌘ 时按了别的键或点了鼠标（比如 ⌥⌘D、⌥⌘Esc、⌥⌘ 拖动），不会误触发。
- **环形面板**
  - 内容和 Dock 保持同步：先是 Dock 上固定的 App，后面接着正在运行但没固定的 App，所有图标等间距排成一圈。
  - 鼠标从圆心往哪个方向移就选中哪个图标，不用精确放在图标上。选中的光晕会在图标之间滑动。
  - 圆心显示 App 名称和状态（运行中 / 未运行 / 未固定在 Dock）。
  - 正在运行的 App，图标旁有一个小点。
  - 也可以用键盘：← → 切换，回车打开，Esc 关闭。
- **原生液态玻璃**：外圈用系统的透明液态玻璃（`NSGlassEffectView`），和桌面小组件是同一种材质；圆心是一小块常规玻璃，文字背景再乱也看得清。
- **跨屏幕、跨桌面切换**：App 的窗口如果在另一块屏幕上一个没显示的桌面（Space）里，点它会直接切到那个桌面，和点 Dock 图标的效果一样。
- **设置窗口**：外观参数都能调，左边有实时预览，并提供五种参考背景（桌面壁纸、浅色文档、深色文档、彩色、纯白），方便检查玻璃在各种背景上的效果。

## 系统要求

- **macOS 26（Tahoe）或更高版本**：液态玻璃是 macOS 26 才有的系统功能。在 macOS 27.2 上开发和测试。
- Apple 芯片和 Intel 的 Mac 都可以用（安装包是通用版）
- 「悬停 / 按下时玻璃有反应」需要 macOS 27

DockDot 启动时会先检查环境。如果系统低于 macOS 26，会弹出提示说明原因，提供「打开软件更新」按钮，然后退出，不会打开一个用不了的 App。

## 安装

### 下载安装（推荐）

1. 到 [Releases](https://github.com/mars7233/DockDot/releases/latest) 下载 `DockDot-x.y.z.dmg`，双击打开。
2. 把 **DockDot** 拖到旁边的 **Applications（应用程序）** 文件夹。
3. 在「应用程序」里打开 DockDot。

如果直接在安装盘里双击打开，DockDot 会提示你先把它放进「应用程序」文件夹，也可以点按钮让它自己移过去并重新打开。原因是：从安装盘里运行时，macOS 会把 App 放在一个临时位置，辅助功能权限和开机启动都会失效。

**第一次打开被拦住？** DockDot 没有付费的 Apple 开发者签名，所以 macOS 第一次会提示「无法验证开发者」或「Apple 无法检查其是否包含恶意软件」。处理方法：打开 **系统设置 → 隐私与安全性**，在页面下方找到 DockDot，点「**仍要打开**」。只需要这一次。

### 授权辅助功能

⌥⌘ 快捷键和跨桌面切换都需要「辅助功能」权限：

1. 打开 **系统设置 → 隐私与安全性 → 辅助功能**。
2. 打开 DockDot 的开关；如果列表里没有，点「+」，选择「应用程序」里的 DockDot。
3. 从菜单栏退出 DockDot，再重新打开。

没有授权时，小圆点照样能用，只是 ⌥⌘ 快捷键不起作用。授权状态可以在 **设置 → 通用** 里查看。

### 推荐：把系统 Dock 设成自动隐藏

```bash
defaults write com.apple.dock autohide -bool true && killall Dock
```

### 从源码编译

需要 Xcode 或 Command Line Tools（Swift 6）。

```bash
git clone git@github.com:mars7233/DockDot.git
cd DockDot
./scripts/make-signing-cert.sh   # 只需运行一次：创建本机自用的签名证书
./build.sh                       # 编译本机架构、签名，安装到 ~/Applications/DockDot.app
open ~/Applications/DockDot.app
```

打发布用的安装包（Apple 芯片 + Intel 通用版，输出到 `dist/DockDot-<版本>.dmg`）：

```bash
VERSION=1.0.0 ./scripts/package-dmg.sh
```

**为什么要建签名证书？** macOS 是按 App 的签名来记住「辅助功能」权限的。不用固定的证书签名的话，每次重新编译签名都会变，系统会把它当成一个新 App，你就得重新授权一次。`make-signing-cert.sh` 会在「登录」钥匙串里建一个只在本机使用的自签名证书「DockDot Local Signing」，打包脚本找到它就会用它签名。钥匙串里显示它「不受信任」是正常的，不影响使用。不建这个证书也能编译，只是会退回临时签名，每次编译后都要重新授权。发布版也用这个证书签名，所以用户升级到新版本时不用重新授权。

> 打包脚本会先在临时目录里组装和签名。这是因为开了 iCloud 同步的「文稿」等目录会给文件加扩展属性，`codesign` 遇到这些属性会拒绝签名。

## 使用

| 操作 | 效果 |
|---|---|
| 点击小圆点 | 在小圆点旁边打开 / 收起面板 |
| 拖动小圆点 | 换位置，松手后吸附到最近的屏幕边缘 |
| 单按一下 ⌥⌘ | 在鼠标位置打开 / 收起面板 |
| 鼠标往某个方向移 | 选中那个方向的图标 |
| 点击 / 回车 | 打开选中的 App |
| ← → | 用键盘切换选中的图标 |
| Esc、点圆心、点面板外面 | 收起面板 |

菜单栏的 ◎ 图标里有：打开面板、显示/隐藏小圆点、设置…（⌘,）、退出。

## 设置

**外观**：每一项改动都会立刻反映在左边的预览里，下次打开面板时生效。

| 分组 | 参数 |
|---|---|
| 液态玻璃 | 样式（透明 / 常规）、着色开关、着色颜色（内置调色盘）、着色强度、悬停 / 按下时玻璃有反应 |
| 布局 | 图标大小（36–64 pt）、图标离边缘的距离 |
| 细节 | 圆心玻璃（让中间文字更清楚）、选中光晕强度、运行中的小点 |

默认值：透明玻璃，黑色着色 11%，图标 64 pt，离边缘 22 pt，选中光晕 21%。随时可以点「恢复默认外观」。

**通用**：显示小圆点、小圆点不用时的透明度、快捷键说明、辅助功能授权状态、开机自动启动。

所有设置都存在 `~/Library/Preferences/local.dockdot.plist`。

## 实现原理

| 部分 | 做法 |
|---|---|
| 读取 Dock 内容 | 读系统 Dock 配置 `com.apple.dock` 里的 `persistent-apps` 得到固定的 App，再从 `NSWorkspace.runningApplications` 补上正在运行但没固定的 App |
| 打开 App | `NSWorkspace.openApplication`，效果和点 Dock 图标一样：没运行就启动，运行中就切过去，最小化的窗口也会恢复 |
| ⌥⌘ 单按检测 | 全局监听 `flagsChanged`。只有「从 ⌥⌘ 的子集按进来、再松开，期间没有别的按键或鼠标点击、且 0.8 秒内松开」才算一次单按。是否有别的输入，同时用两种方式判断：按键/点击监听，以及系统全局输入计数器（`CGEventSource.counterForEventType`） |
| 液态玻璃 | 外圈是一块 `NSGlassEffectView`（`.clear` + 着色）；圆心是另一块 `.regular` 玻璃，文字放在它的 `contentView` 里，这样系统会按背景明暗自动选择深色或浅色文字 |
| 跨桌面切换 | 辅助功能接口只能看到当前正在显示的桌面上的窗口。如果 App 在这些桌面上没有窗口，就从 `CGWindowListCopyWindowInfo`（覆盖所有桌面）里找到它最前面的那个窗口，再调用 SkyLight 的 `_SLPSSetFrontProcessWithOptions` / `SLPSPostEventRecordTo` 把这个窗口放到最前，系统会自动切到它所在的桌面。做法参考了 [AltTab](https://github.com/lwouis/alt-tab-macos) |

### 代码结构

```
Sources/DockDot/
├── main.swift            入口：先做环境检测，再启动；调试参数
├── EnvironmentCheck.swift 启动前的环境检测（系统版本、是否从安装盘运行）
├── AppDelegate.swift     组装各部分、菜单栏菜单
├── Dot.swift             悬浮小圆点（拖动、吸附、记住位置）
├── Hotkey.swift          ⌥⌘ 单按检测
├── Launcher.swift        面板窗口、定位、打开 / 收起
├── RadialView.swift      环形布局、液态玻璃、选中、鼠标 / 键盘交互
├── DockReader.swift      读取 Dock 内容、打开 App
├── SpaceFocus.swift      切到其他桌面上的窗口
├── Settings.swift        设置数据（UserDefaults）
└── SettingsWindow.swift  设置窗口（SwiftUI）：预览、参考背景、调色盘
Resources/AppIcon.icns        App 图标（由 scripts/make-icon.swift 生成）
scripts/make-signing-cert.sh  创建本机自用签名证书
scripts/make-app.sh           编译、组装、签名 DockDot.app
scripts/package-dmg.sh        打包发布用的 DMG（通用版）
build.sh                      本地开发：编译并安装到 ~/Applications
```

### 调试参数

```bash
# 打印读到的 Dock 内容
~/Applications/DockDot.app/Contents/MacOS/DockDot --dump

# 打印点击每个运行中的 App 会怎么切换（不会真的切换），排查多屏 / 多桌面问题
~/Applications/DockDot.app/Contents/MacOS/DockDot --where

# 启动时直接打开设置窗口
open ~/Applications/DockDot.app --args --settings

# 打印环境检测结果；后两个参数在正常的 Mac 上模拟「系统太旧」「从安装盘运行」的提示
~/Applications/DockDot.app/Contents/MacOS/DockDot --env-check
open ~/Applications/DockDot.app --args --simulate-old-macos
open ~/Applications/DockDot.app --args --simulate-dmg
```

## 已知限制

- 跨桌面切换用到了 SkyLight 私有接口，以后的 macOS 更新可能会让它失效。失效时会退回普通的「激活 App」，不会崩溃。
- 面板只显示 App，不显示 Dock 上的文件夹、文件和废纸篓。
- App 超过 22 个时会自动排成内外两圈。
- 没有 Apple 开发者签名和公证，第一次打开需要在「隐私与安全性」里点「仍要打开」。
- 只在 Apple 芯片的 Mac、macOS 27.2 上测试过；Intel 版能编译，但没有在真机上跑过。

## 致谢

- [chillintheshade/dok](https://github.com/chillintheshade/dok)：液态玻璃轮盘的材质用法（原生玻璃、不裁剪、圆心镜片）参考了它。
- [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos)：跨桌面聚焦窗口的做法。
- [ricky-yosh/RadialMenu](https://github.com/ricky-yosh/RadialMenu)：⌥⌘ 快捷键的灵感来源。
