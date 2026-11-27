# phone-mirror

`phone` 让你在 Mac 上用 scrcpy 控制 Android 手机，也能通过 ADB 批量收发文件。连上手机，在终端运行 `phone` 即可投屏。手机实体屏幕默认熄灭，投屏期间保持唤醒。在投屏窗口按 **⌘1** 回到手机主屏幕，按 **⌘2** 打开最近任务。

## 安装

在装有 Homebrew 和 Apple 命令行开发工具的 Mac 上运行下面的命令。Homebrew 从公开仓库获取源码，安装 scrcpy，并在本机编译投屏快捷键程序。首次使用和从旧 SSH 安装迁移都可以运行同一组命令。

```sh
brew tap --custom-remote 2021dt/phone-mirror https://github.com/2021Dt/phone-mirror.git
if brew command trust >/dev/null 2>&1; then brew trust --formula 2021dt/phone-mirror/phone-mirror; fi
brew install 2021dt/phone-mirror/phone-mirror
command -v adb >/dev/null || brew install --cask android-platform-tools
phone -h
```

已有手工安装的用户可以运行 `type -a phone` 查看哪个入口优先生效，用 `"$(brew --prefix)/bin/phone" -h` 直接测试 Homebrew 版。如果第一个入口是自己先前创建的 `~/.local/bin/phone` 符号链接，可以将它改名备份，再运行 `rehash`，然后用 `command -v phone` 确认。

```sh
brew update
brew upgrade 2021dt/phone-mirror/phone-mirror
```

以上两条命令更新本工具。`phone update` 可单独更新 scrcpy。卸载本工具用 `brew uninstall 2021dt/phone-mirror/phone-mirror`。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `phone` | 自动选择在线手机并投屏 |
| `phone send` | 在 Mac 上选一个或多个文件，发送到手机「下载」 |
| `phone get` | 浏览手机文件，将选中的文件保存到 Mac 的接收目录 |
| `phone folder` | 选择并记住 Mac 上的接收目录 |
| `phone list` | 查看连接状态和设备序列号 |
| `phone usb` | 只用 USB 连接 |
| `phone -s 序列号` | 有多台手机时指定目标 |
| `phone --screen-on` | 投屏时保持手机屏幕亮起 |
| `phone --screen-on --screen-off-timeout=300` | 亮屏启动，空闲 5 分钟后允许休眠 |
| `phone update` | 通过 Homebrew 检查并更新 scrcpy |
| `phone -h` | 查看全部选项、快捷键和配对说明 |

首次使用 USB 时，在手机的开发者选项中开启 USB 调试，解锁手机并确认这台 Mac 的调试授权。设备选择有歧义时，`phone` 会列出候选设备。同一部手机同时通过 USB 和无线连接，并且序列号能确认时，会优先使用无线连接。

### 传文件

在投屏窗口内按 **⌘U**，从 Mac 选文件发到手机「下载」。按 **⌘D**，从手机选文件取回 Mac。在文件列表里按住 **⌘** 点选多个文件，或按住 **Shift** 连选一段，再确认传输。要修改 Mac 的接收目录，按 **⌘,**（Command 加英文逗号），选一次即可记住。

手机连上后直接运行 `phone send` 或 `phone get` 即可，投屏窗口可以关着。`phone get` 从手机的「下载」开始。单击「上一级」或双击文件夹，路径和列表会在同一个窗口里更新。例如回到共享存储，再打开 `DCIM/Camera` 就能找相机照片。双击文件开始下载，按 Esc 取消。有多台手机时，用 `phone -s 序列号 get` 或 `phone -s 序列号 send` 选设备。

也可以在终端输入 `phone send` 和一个空格，把 Finder 里选中的多个文件一起拖进来并回车。取回时可以一次给出多个手机文件名，默认从手机「下载」查找。两边遇到同名文件都会保留两份，例如 `报告 (1).pdf`。

```sh
phone send "周报.pdf" "现场照片.jpg"
phone get "周报.pdf" "现场照片.jpg" --to ~/Desktop
```

批量传输会逐个处理文件。某个文件失败时，后续文件仍会继续，结束时会显示成功数量和失败项，方便单独重试。

Mac 起初使用 `~/Downloads`。运行一次 `phone folder`，选好目录，以后 `phone get` 就存到那里。也可以直接指定已有目录，例如 `phone folder ~/Desktop`。临时保存到当前项目可用 `phone get --to .`，下次下载仍用常用目录。`phone folder --reset` 可恢复到 `~/Downloads`。发到手机的文件默认存入手机「下载」。

### 无线调试

Android 11 及以上可在同一可信 Wi-Fi 下配对。在手机的「开发者选项 → 无线调试」中点「使用配对码配对设备」，运行 `phone pair 地址:配对端口`，按提示输入配对码。配对后运行 `phone list`。如果还没显示设备，用「无线调试」主页面的**连接端口**运行 `phone connect 地址:连接端口`，再运行 `phone`。

### 窗口内操作

| 按键 | 用途 |
| --- | --- |
| ⌘1 / ⌘2 | 回主屏幕 / 打开最近任务，点卡片切换 App |
| ⌘U / ⌘D | 发到当前手机 / 取回 Mac |
| ⌘, | 选择 Mac 常用接收目录 |
| 左 Option + B | 返回上一页 |
| 左 Option + O / 左 Option + Shift + O | 投屏时熄灭 / 点亮手机实体屏幕 |
| 左 Option + V | 将 Mac 剪贴板内容粘贴到手机 |

这些 Command 快捷键只在当前投屏窗口处于前台时启用。默认通过 Android 的实体键盘模式输入，中文可以用手机输入法，或在 Mac 上复制后粘贴。
