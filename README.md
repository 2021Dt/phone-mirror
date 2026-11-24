# phone-mirror

`phone` 是一个 macOS Zsh 命令。连上 Android 手机后，在终端运行 `phone` 就能用 scrcpy 投屏。默认关闭手机实体屏幕，并在投屏期间保持唤醒。点一下投屏窗口，按 **⌘1** 回到手机主屏幕，按 **⌘2** 打开最近任务。

## 安装

需要 macOS、Zsh、Git 和 Apple 命令行开发工具。已有 Homebrew 的 scrcpy 和 adb 可以直接使用。缺少哪个就安装哪个。

```sh
brew install scrcpy
brew install --cask android-platform-tools
```

克隆仓库，在这台 Mac 上编译快捷键程序，然后先从项目目录运行帮助。

```sh
git clone https://github.com/2021Dt/phone-mirror.git
cd phone-mirror
chmod u+x phone.zsh
clang -Os -fobjc-arc -framework AppKit -framework Carbon phone-hotkeys.m -o phone-hotkeys
./phone.zsh -h
```

用 `type -a phone` 查看已有的同名命令。如果名字可用，把入口链接到个人命令目录。链接指向当前项目，请将项目保留在这个位置。

```sh
mkdir -p "$HOME/.local/bin"
ln -s "$PWD/phone.zsh" "$HOME/.local/bin/phone"
```

如果 `command -v phone` 找不到入口，将 `export PATH="$HOME/.local/bin:$PATH"` 加入 `~/.zshrc`，然后重新打开终端。已有同名命令时，也可以直接用 `./phone.zsh` 投屏。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `phone` | 自动选择在线手机并投屏 |
| `phone list` | 查看连接状态和设备序列号 |
| `phone usb` | 只用 USB 连接 |
| `phone -s 序列号` | 有多台手机时指定目标 |
| `phone --screen-on` | 投屏时保持手机屏幕亮起 |
| `phone --screen-on --screen-off-timeout=300` | 亮屏启动，空闲 5 分钟后允许休眠 |
| `phone update` | 通过 Homebrew 检查并更新 scrcpy |
| `phone -h` | 查看全部选项、快捷键和配对说明 |

首次使用 USB 时，在手机的开发者选项中开启 USB 调试，解锁手机并确认这台 Mac 的调试授权。设备选择有歧义时，`phone` 会列出候选设备。同一部手机同时通过 USB 和无线连接，并且序列号能确认时，会优先使用无线连接。

### 无线调试

Android 11 及以上可在同一可信 Wi-Fi 下配对。在手机的「开发者选项 → 无线调试」中点「使用配对码配对设备」，运行 `phone pair 地址:配对端口`，按提示输入配对码。配对后运行 `phone list`。如果还没显示设备，用「无线调试」主页面的**连接端口**运行 `phone connect 地址:连接端口`，再运行 `phone`。

### 窗口内操作

| 按键 | 用途 |
| --- | --- |
| ⌘1 / ⌘2 | 回主屏幕 / 打开最近任务，点卡片切换 App |
| 左 Option + B | 返回上一页 |
| 左 Option + O / 左 Option + Shift + O | 投屏时熄灭 / 点亮手机实体屏幕 |
| 左 Option + V | 将 Mac 剪贴板内容粘贴到手机 |

⌘1 和 ⌘2 只在当前投屏窗口处于前台时启用。默认通过 Android 的实体键盘模式输入，中文可以用手机输入法，或在 Mac 上复制后粘贴。

`phone update` 更新 Homebrew 的 scrcpy。要更新本项目，在仓库目录运行 `git pull --ff-only`，再运行上面的 `clang` 命令，重新打开投屏即可。
