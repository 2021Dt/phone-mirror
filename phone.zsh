#!/bin/zsh -f
# Android mirroring through the current ADB server.
function phone {
    emulate -L zsh
    setopt extendedglob

    local usage='用法：phone [投屏选项] | phone usb [序列号] [投屏选项]
      phone -s 序列号 [投屏选项] | phone list | phone update | phone -h
      phone send [Mac文件] | phone get [手机文件] [--to Mac目录]（可在子命令前加 -s 序列号）
      phone folder [Mac目录 | --reset]
      投屏选项：-S / --screen-off、--screen-on、--keyboard=sdk / --keyboard=uhid
                --screen-off-timeout=秒数 或 --keep-active
      phone pair 地址:配对端口 | phone connect 地址:连接端口'
    local -a launch_options scrcpy_options
    local requested= endpoint= endpoint_host adb_bin scrcpy_bin
    if [[ $1 == -s && -n $2 && $2 != -* && $3 == (send|get) ]]; then
        requested=$2
        shift 2
    fi
    if [[ $1 != (send|get|folder) ]]; then
        while [[ ${argv[-1]} == (-S|--screen-off|--screen-on|--keyboard=sdk|--keyboard=uhid|--screen-off-timeout=*|--keep-active) ]]; do
            launch_options=("${argv[-1]}" "${launch_options[@]}")
            shift -p
        done
    fi
    local mode=${1:-auto}
    local script_file=${(%):-%x}
    local script_dir=${script_file:A:h}
    if (( ${#launch_options} )) && [[ $mode != (auto|usb|-s) ]]; then
        print -ru2 -- "$usage"
        return 2
    fi
    case $mode in
        -h|--help|help)
            print -r -- 'phone · Android 手机投屏

命令
  phone                             自动选手机，默认熄屏、不因空闲休眠、实体键盘
  phone send                        在 Mac 上选一个文件，发送到手机「下载」
  phone get                         从手机取文件，保存到选好的 Mac 目录（初始为「下载」）
  phone folder                      为以后的下载选一个 Mac 文件夹，无需连接手机
  phone list                        查看 ADB 设备列表和序列号
  phone update                      通过 Homebrew 检查并更新 scrcpy，无需连接手机
  phone usb [序列号]                通过 USB 投屏，可指定手机
  phone -s 序列号                   指定在线设备投屏
  phone pair 地址:配对端口          配对无线调试，按提示输入配对码
  phone connect 地址:连接端口       手动连接已配对的手机
  phone -h                          显示本帮助

更新 phone 本身
  brew update && brew upgrade 2021dt/phone-mirror/phone-mirror

常用示例（在终端输入）
  phone send ~/Downloads/报告.pdf   直接发送文件，也可以输入 phone send 后拖入文件
  phone get 报告.pdf                直接取回手机「下载」里的这个文件
                                    传文件遇到同名时，新副本会自动加编号
  phone get --to .                  只把这次选的文件存到当前目录
  phone folder --reset              恢复 Mac 默认的「下载」目录
  phone -s 序列号 get               指定要取文件的手机
  phone usb                         插线投屏，手机熄屏且不因空闲休眠
  phone --screen-on                 亮屏投屏，仍阻止空闲休眠
  phone usb --screen-on             USB 投屏，同时点亮手机屏幕
  phone usb --keyboard=sdk          USB 投屏，改用兼容键盘模式
  phone --screen-off               熄屏投屏，与默认行为相同，也可写 -S
  phone --screen-on --screen-off-timeout=300
                                    亮屏启动，空闲 5 分钟后自动休眠
  phone usb --keep-active           USB 熄屏投屏，阻止空闲休眠，与默认行为相同
  投屏选项放在命令末尾，可以组合，例如：
  phone usb --screen-on --keyboard=sdk

常用快捷键（先点击投屏窗口，Option 指左 Option）
  ⌘1  (Command+1)                  回到手机主屏幕
  ⌘2  (Command+2)                  打开最近任务，点击卡片即可切换 App
  ⌘U  (Command+U)                  从 Mac 选文件，发送到当前手机的「下载」
  ⌘D  (Command+D)                  从当前手机选文件，取回 Mac
  ⌘,  (Command+逗号)               选择并记住 Mac 接收文件的目录
  Option+O                         熄灭手机屏幕，继续投屏
  Option+Shift+O                   点亮手机屏幕
  Option+B                         返回上一页
  Option+C / Option+X              复制 / 剪切手机中选中的内容
  Option+V                         将 Mac 剪贴板内容粘贴到手机
  Option+K                         打开手机实体键盘设置（UHID 模式）
  Option+F                         切换全屏
  Option+↑ / Option+↓              调高 / 调低音量
  Option+N / Option+Shift+N         展开 / 收起通知栏
  Option+Q                         退出投屏
  Ctrl+鼠标左键拖动                模拟双指缩放或旋转（需应用支持）
  鼠标右键                         返回；手机屏幕关闭时会唤醒
  在终端按 Ctrl+C 也可以结束当前投屏。

设备选择
  只有一个在线候选时直接投屏。仅有无线和 USB 两条连接，且确认属于同一部
  手机时，优先无线。
  有多个候选且无法确认目标时，用 phone list 查看序列号，再用 phone -s 指定。

熄屏投屏
  默认关闭手机屏幕并阻止空闲休眠，电脑上可以继续操作。
  需要亮屏投屏时，运行 phone --screen-on，仍会阻止空闲休眠。
  在投屏窗口里，按左 Option+Shift+O 点亮，按左 Option+O 再次熄屏。
  用手机实体电源键亮屏后，也可以按左 Option+O 恢复熄屏投屏。

自动休眠时间
  --screen-off-timeout=秒数         临时修改手机的空闲休眠时间，例如 60、300、600。
                                    覆盖默认的不休眠行为，正常退出投屏后恢复原值。
  --keep-active                    投屏期间阻止空闲休眠，默认启用，USB 和无线均可用。
  这两个选项不能显式同时使用。秒数为 1～2147483 的整数，0 不代表永不休眠。
  默认熄屏启动；需要亮屏时加 --screen-on。退出投屏后不再阻止空闲休眠。
  自动休眠可能触发锁屏，与只关闭手机屏幕、继续投屏不同。
  保持熄屏投屏且不因空闲而休眠，直接运行 phone 或 phone usb 即可。

键盘
  默认使用 Android 实体键盘模式。在投屏窗口按左 Option+K，
  在手机上为 scrcpy 键盘选择与 Mac 一致的布局。中文由手机输入法处理。
  若实体键盘模式不适用，可在投屏命令末尾加 --keyboard=sdk。

首次无线配对（Android 11 或更新版本）
  1. 让 Mac 和手机连到同一个可信 Wi-Fi，打开手机的「开发者选项 → 无线调试」。
  2. 点「使用配对码配对设备」，运行 phone pair 地址:配对端口，再输入配对码。
  3. 如果 phone list 里还没有无线设备，用「无线调试」主页面当前显示的
     地址和连接端口运行 phone connect 地址:连接端口，然后运行 phone。

常见状态
  unauthorized  解锁手机，确认调试授权提示，再运行 phone list。
  offline       重新插拔 USB 数据线，或用手机当前的无线地址和端口重新连接。
  列表为空      检查手机是否已开启 USB 调试或无线调试。'
            return 0 ;;
        update)
            (( $# == 1 )) || { print -ru2 -- "$usage"; return 2; }
            local brew_bin
            brew_bin=$(whence -p brew) || { print -ru2 -- 'phone：找不到 brew，更新 scrcpy 需要 Homebrew。'; return 127; }
            print -ru2 -- 'phone：正在刷新 Homebrew 并检查 scrcpy 更新…'
            "$brew_bin" update --quiet || return $?
            HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" upgrade --formula scrcpy
            return $? ;;
        pair|connect)
            if (( $# == 1 )); then
                if [[ $mode == pair ]]; then
                    print -r -- '在手机的「开发者选项 → 无线调试」中点「使用配对码配对设备」。'
                    print -r -- '运行 phone pair 地址:配对端口，然后按 ADB 的提示输入配对码。'
                else
                    print -r -- '运行 phone connect 地址:连接端口。请用「无线调试」主页面显示的地址和端口。'
                fi
                return 0
            fi
            endpoint=$2
            endpoint_host=${endpoint%:*}
            if (( $# != 2 )) || [[ $endpoint == -* || $endpoint == *[[:space:]]* || $endpoint != ?*:[0-9]## ]] ||
                [[ $endpoint_host == *:* && $endpoint_host != \[*\] ]]; then
                print -ru2 -- "$usage"
                return 2
            fi ;;
        list)
            (( $# == 1 )) || { print -ru2 -- "$usage"; return 2; } ;;
        folder)
            (( $# <= 2 )) && [[ $# == 1 || -n $2 ]] || { print -ru2 -- "$usage"; return 2; }
            shift
            /bin/zsh -f "$script_dir/phone-transfer.zsh" folder "$@"
            return $? ;;
        send)
            (( $# == 1 || $# == 2 )) && [[ $# == 1 || -n $2 ]] || { print -ru2 -- "$usage"; return 2; } ;;
        get)
            local get_file= get_folder=
            shift
            while (( $# )); do
                if [[ $1 == --to ]]; then
                    [[ -n $2 && -z $get_folder ]] || { print -ru2 -- '用法：phone get [手机文件] --to Mac目录'; return 2; }
                    get_folder=$2
                    shift 2
                else
                    [[ -n $1 && -z $get_file ]] || { print -ru2 -- "$usage"; return 2; }
                    get_file=$1
                    shift
                fi
            done
            set -- "$mode" "$get_file" "$get_folder" ;;
        usb)
            [[ $# -le 2 && $2 != -* ]] || { print -ru2 -- "$usage"; return 2; }
            requested=$2 ;;
        -s)
            [[ $# == 2 && -n $2 && $2 != -* ]] || { print -ru2 -- "$usage"; return 2; }
            requested=$2 ;;
        auto)
            (( $# == 0 )) || { print -ru2 -- "$usage"; return 2; } ;;
        *)
            print -ru2 -- "$usage"
            return 2 ;;
    esac

    local screen_off=yes keyboard_mode=uhid screen_timeout= keep_active=yes keep_active_explicit=no option
    for option in "${launch_options[@]}"; do
        case $option in
            -S|--screen-off) screen_off=yes ;;
            --screen-on) screen_off=no ;;
            --keyboard=*) keyboard_mode=${option#*=} ;;
            --keep-active) keep_active_explicit=yes ;;
            --screen-off-timeout=*)
                screen_timeout=${option#*=}
                if [[ $screen_timeout != [0-9]## || ${#screen_timeout} -gt 7 ]] ||
                    (( 10#$screen_timeout < 1 || 10#$screen_timeout > 2147483 )); then
                    print -ru2 -- 'phone：--screen-off-timeout 需要 1～2147483 的整数秒，例如 --screen-off-timeout=300；不自动休眠请用 --keep-active。'
                    return 2
                fi
                screen_timeout=$(( 10#$screen_timeout )) ;;
        esac
    done
    if [[ -n $screen_timeout ]]; then
        if [[ $keep_active_explicit == yes ]]; then
            print -ru2 -- 'phone：--screen-off-timeout 与 --keep-active 不能同时使用，请选择自动休眠时间或保持运行。'
            return 2
        fi
        keep_active=no
    fi

    adb_bin=$(whence -p adb) || { print -ru2 -- 'phone：找不到 adb。'; return 127; }
    case $mode in
        list) "$adb_bin" devices -l; return $? ;;
        pair|connect) "$adb_bin" "$mode" "$endpoint"; return $? ;;
    esac

    local devices serial state details kind target hardware_serial
    local -a candidates usb_devices wireless_devices
    devices=$("$adb_bin" devices -l) || return $?
    while IFS=$' \t' read -r serial state details; do
        [[ $state == device && $serial != emulator-<-> ]] || continue
        if [[ " $details" == *[[:blank:]]usb:* ]]; then
            kind=usb
        elif [[ $serial == ?*:[0-9]## || $serial == *._adb-tls-connect._tcp* || $serial == *._adb._tcp* ]]; then
            kind=wireless
        else
            kind=unknown
        fi
        [[ $mode != usb || $kind == usb ]] || continue
        [[ -z $requested || $serial == "$requested" ]] || continue
        candidates+=("$serial")
        case $kind in
            usb) usb_devices+=("$serial") ;;
            wireless) wireless_devices+=("$serial") ;;
        esac
    done <<< "$devices"

    if (( ${#candidates} == 1 )); then
        target=$candidates[1]
    elif [[ $mode == (auto|send|get) ]] && (( ${#candidates} == 2 && ${#usb_devices} == 1 && ${#wireless_devices} == 1 )); then
        # A TCP endpoint and a USB serial may represent the same handset.
        if hardware_serial=$("$adb_bin" -s "$wireless_devices[1]" shell -T getprop ro.serialno 2>/dev/null) &&
            [[ ${hardware_serial%$'\r'} == "$usb_devices[1]" ]]; then
            target=$wireless_devices[1]
        fi
    fi

    if [[ -z $target ]]; then
        if (( ${#candidates} == 0 )); then
            print -ru2 -- 'phone：没有符合条件的在线设备。请检查无线调试，或解锁手机并允许 USB 调试。'
        elif [[ $mode == (send|get) ]]; then
            print -ru2 -- "phone：有多台在线设备，请用 phone -s 序列号 $mode 指定手机。"
        else
            print -ru2 -- 'phone：无法唯一确定目标。请从下方复制序列号，运行 phone -s 序列号。'
        fi
        print -ru2 -- "$devices"
        return 1
    fi

    if [[ $mode == (send|get) ]]; then
        shift
        /bin/zsh -f "$script_dir/phone-transfer.zsh" "$mode" "$adb_bin" "$target" "$@"
        return $?
    fi

    scrcpy_bin=$(whence -p scrcpy) || { print -ru2 -- 'phone：找不到 scrcpy。'; return 127; }
    scrcpy_options=("--keyboard=$keyboard_mode")
    if [[ $screen_off == yes ]]; then
        scrcpy_options+=(--turn-screen-off)
    fi
    if [[ -n $screen_timeout ]]; then
        scrcpy_options+=("--screen-off-timeout=$screen_timeout")
    elif [[ $keep_active == yes ]]; then
        scrcpy_options+=(--keep-active)
    fi
    print -ru2 -- 'phone · 以下快捷键在投屏窗口内使用，Option 指左 Option
  屏幕：Option+O 熄屏继续投屏 / Option+Shift+O 点亮
  导航：⌘1 主屏幕 / ⌘2 最近任务 / Option+B 返回
  输入：Option+C 复制 / Option+V 粘贴 Mac 剪贴板内容
  窗口：Option+F 全屏 / Option+Q 退出'
    if [[ $keyboard_mode == uhid ]]; then
        print -ru2 -- '  键盘：Option+K 设置手机实体键盘布局，中文由手机输入法处理'
    fi
    if [[ -n $screen_timeout ]]; then
        print -ru2 -- "  休眠：空闲 ${screen_timeout} 秒后自动休眠，正常退出投屏后恢复原值。"
    elif [[ $keep_active == yes ]]; then
        print -ru2 -- '  休眠：投屏期间阻止空闲休眠，退出投屏后结束。'
    fi
    print -ru2 -- '  手机被手动点亮后，按 Option+O 可重新熄屏，投屏会继续。
  文件：⌘U 发到手机 / ⌘D 取回 Mac / ⌘, 选择 Mac 保存目录'
    local hotkeys_bin=$script_dir/phone-hotkeys
    (
        if [[ -x $hotkeys_bin ]]; then
            "$hotkeys_bin" "$adb_bin" "$target" </dev/null &!
        else
            print -ru2 -- 'phone：找不到 phone-hotkeys，投屏窗口的导航和文件快捷键暂不可用。'
        fi
        ADB="$adb_bin" exec "$scrcpy_bin" --serial="$target" "${scrcpy_options[@]}"
    )
}

if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
    phone "$@"
fi
