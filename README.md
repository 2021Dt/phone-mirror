# phone-mirror

手机插上 Mac，终端里敲个 `phone`，就能用鼠标和键盘操作 Android。手机屏幕默认熄着，Mac 上照常用。投屏靠 scrcpy，传文件靠 adb。

## 安装

Mac 上需要 Homebrew 和苹果的命令行开发工具。打开终端，运行下面几行。

```sh
brew tap --custom-remote 2021dt/phone-mirror https://github.com/2021Dt/phone-mirror.git
if brew command trust >/dev/null 2>&1; then
  brew trust --formula 2021dt/phone-mirror/phone-mirror
fi
brew install 2021dt/phone-mirror/phone-mirror
command -v adb >/dev/null || brew install --cask android-platform-tools
```

## 第一次投屏

在手机的「开发者选项」里打开「USB 调试」，用数据线连上 Mac。解锁手机，看到「允许 USB 调试」时点允许，然后在终端运行 `phone`。

点一下投屏窗口，按 `⌘1` 回手机桌面，按 `⌘2` 看最近用过的 App，按左 `Option+B` 返回上一页。想让手机也亮着屏，就用 `phone --screen-on` 启动。

连了好几台手机时，用 `phone list` 看序列号，再用 `phone -s 序列号` 选一台。中文输入用手机上的输入法，也可以在 Mac 上复制一段文字，按左 `Option+V` 粘贴到手机。

## 传文件

- **Mac → 手机**　在投屏窗口按 `⌘U`，选好的文件会发到手机的「下载」。
- **手机 → Mac**　按 `⌘D` 挑文件。找相机照片的话，从「下载」点「上一级」，再进 `DCIM/Camera`。取回的文件默认放在 Mac 的 `~/Downloads`。

两边都能按住 `⌘` 点选多个文件，也能按住 Shift 连选。碰到重名的照片，第二份会存成 `照片 (1).jpg`。

想换 Mac 上的保存位置，在投屏窗口按 `⌘,`，或在终端运行 `phone folder`。选一次就会记住。

只传文件也可以直接用终端。先打 `phone send`，留个空格，把 Finder 里选好的文件一起拖进来，回车就发。取文件用 `phone get`，知道文件名就可以跳过选择窗口。

```sh
phone get 周报.pdf 照片.jpg --to ~/Desktop
```

## 无线连接

Android 11 及以上可以走 Wi-Fi。让手机和 Mac 连上同一个可信的 Wi-Fi，在手机的「开发者选项 → 无线调试」里点「使用配对码配对设备」。

在 Mac 上运行 `phone pair IP:配对端口`，按提示输入手机上的配对码。然后用 `phone list` 看一眼。如果没出现这台手机，回到「无线调试」主页面，用那里显示的**连接端口**运行 `phone connect IP:连接端口`。连好以后，照常敲 `phone`。

## 更新

```sh
brew update && brew upgrade 2021dt/phone-mirror/phone-mirror
```

单独更新 scrcpy 用 `phone update`。熄屏、休眠时间和其他快捷键可以查 `phone -h`。
