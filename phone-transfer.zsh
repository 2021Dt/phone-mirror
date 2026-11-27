#!/bin/zsh -f
# Local download preferences and transfers for the device selected by phone.
emulate -L zsh
setopt extendedglob

mode=$1
adb_bin=$2
serial=$3
file=$4
picker=${0:A:h}/phone-picker.js
downloads=$HOME/Downloads
preference=${XDG_CONFIG_HOME:-$HOME/.config}/phone-mirror/download-dir
remote_downloads=/sdcard/Download
local_stage=
remote_stage=
failure_message=

remote() { "$adb_bin" -s "$serial" shell -T "$1"; }
choose() { /usr/bin/osascript -l JavaScript "$picker" "$@"; }

# The open picker starts one short-lived reader per directory. Exec adb so that
# cancelling the read also stops the process that is talking to the phone.
if [[ $mode == list ]]; then
    [[ $# == 4 && $file == /sdcard/* && "/$file/" != */../* ]] || exit 2
    list_command='
        for entry in ./* ./.[!.]* ./..?*; do
            if [ -d "$entry" ]; then kind=D
            elif [ -f "$entry" ]; then kind=F
            else continue
            fi
            printf "%s%s\000" "$kind" "${entry#./}"
        done'
    exec "$adb_bin" -s "$serial" shell -T "cd ${(qq)file} && [ -r . ] && $list_command"
fi

fail() { failure_message=$*; print -ru2 -- "phone：$failure_message"; exit 1; }
report_success() {
    print -r -- "phone：$1"
    if [[ $PHONE_WINDOW_FEEDBACK == 1 ]]; then
        choose notify "$1" >/dev/null || :
    fi
}
check_folder() {
    [[ -d $1 && -w $1 && -x $1 ]] || fail "保存目录不可用：$1。请选择已存在且可写的文件夹。"
}
pick_path() {
    # Preserve newlines in a chosen path, removing just osascript's output terminator.
    REPLY=$(choose "$@" && printf '.') || exit 1
    REPLY=${REPLY%.}
    REPLY=${REPLY%$'\n'}
    [[ -n $REPLY ]] || exit 0
}
cleanup() {
    local result=$?
    if [[ -n $local_stage ]]; then /bin/rm -rf -- "$local_stage"; fi
    if [[ -n $remote_stage ]]; then
        remote "rm -f ${(qq)remote_stage}/payload && rmdir ${(qq)remote_stage}" >/dev/null ||
            print -ru2 -- "phone：未能清理手机上的临时目录 $remote_stage"
    fi
    if [[ $PHONE_WINDOW_FEEDBACK == 1 && $result != (0|130|143) ]]; then
        choose error "${failure_message:-请检查手机连接和保存目录，然后重试。}" >/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
# Shortcut workers run in a background process group and never read from the terminal.
if [[ $PHONE_WINDOW_FEEDBACK == 1 ]]; then
    trap '' TTIN TTOU
fi

case $mode in
    folder)
        if [[ $2 == --reset ]]; then
            /bin/rm -f -- "$preference" || exit 1
            print -r -- "phone：已恢复默认保存目录 $downloads"
            exit 0
        fi
        if (( $# == 1 )); then
            pick_path folder
            folder=$REPLY
        else
            folder=$2
        fi
        [[ -n $folder ]] || fail '请选择保存目录。'
        folder=${folder:a}
        check_folder "$folder"
        [[ ! -d $preference ]] || fail "配置路径是目录：$preference"
        /bin/mkdir -p -- "${preference:h}" || exit 1
        local_stage=$(/usr/bin/mktemp -d "${preference:h}/.folder.XXXXXXXX") || exit 1
        (umask 077; print -rn -- "$folder" > "$local_stage/path") || exit 1
        /bin/mv -fh -- "$local_stage/path" "$preference" || exit 1
        report_success "以后取回的文件会保存到 $folder"
        exit 0 ;;
    send)
        if [[ -z $file ]]; then
            pick_path send
            file=$REPLY
        fi
        [[ -f $file && -r $file ]] || fail "无法读取文件 $file"
        file=${file:a}
        token=$(/usr/bin/uuidgen) || exit 1
        candidate_stage="$remote_downloads/.phone-send-$token"
        remote "mkdir -p $remote_downloads && mkdir ${(qq)candidate_stage}" || exit 1
        remote_stage=$candidate_stage
        "$adb_bin" -s "$serial" push "$file" "$remote_stage/payload" || exit 1
        destination=$remote_downloads ;;
    get)
        if [[ -n $5 ]]; then
            downloads=${5:a}
        elif [[ -e $preference || -L $preference ]]; then
            [[ -f $preference ]] || fail "无法读取保存目录配置：$preference"
            downloads=$(/bin/cat "$preference" && printf '.') || exit 1
            downloads=${downloads%.}
            [[ $downloads == /* ]] || fail '保存目录配置无效，请运行 phone folder 重新选择。'
        else
            /bin/mkdir -p -- "$downloads" || exit 1
        fi
        check_folder "$downloads"
        local_stage=$(/usr/bin/mktemp -d "$downloads/.phone-get.XXXXXXXX") || exit 1
        if [[ -z $file ]]; then
            pick_path get "$adb_bin" "$serial" "${0:A}" "$local_stage/list"
            file=$REPLY
        elif [[ $file != /* ]]; then
            file="$remote_downloads/$file"
        fi
        [[ $file == (/sdcard/*|/storage/*) && "/$file/" != */../* ]] ||
            fail '请从手机共享存储选择文件，或输入下载文件夹里的文件名。'
        remote "test -f ${(qq)file}" || fail "手机上找不到可读取的文件 $file"
        "$adb_bin" -s "$serial" pull "$file" "$local_stage/payload" || exit 1
        [[ -f $local_stage/payload ]] || fail '下载未生成普通文件。'
        destination=$downloads ;;
    *) fail '未知的传输方向。' ;;
esac

name=${file:t}
stem=$name
extension=
if [[ -n ${name:e} && -n ${name:r} ]]; then
    stem=${name:r}
    extension=.${name:e}
fi
integer copy_number=0
while true; do
    output="$destination/$name"
    if [[ $mode == get ]]; then
        # link(1) publishes the finished file atomically and never replaces an entry.
        if /bin/link "$local_stage/payload" "$output" 2>/dev/null; then break; fi
        # A redirected Downloads folder may be on a volume without hard links.
        if [[ ! -e $output && ! -L $output ]] &&
           (setopt noclobber; : > "$output") 2>/dev/null; then
            /bin/mv -f -- "$local_stage/payload" "$output" && break
            /bin/rm -f -- "$output"
            fail "无法保存到 $output"
        fi
        [[ -e $output || -L $output ]] || fail "无法保存到 $output"
    else
        # Shared Android storage may not support hard links. Reserve the final
        # name with noclobber before replacing our own empty reservation.
        remote "dst=${(qq)output}; src=${(qq)remote_stage}/payload;"'
            if [ -e "$dst" ] || [ -L "$dst" ]; then exit 17; fi
            if (set -C; : > "$dst") 2>/dev/null; then
                mv -f "$src" "$dst" && exit 0
                rm -f "$dst"
                exit 1
            fi
            if [ -e "$dst" ] || [ -L "$dst" ]; then exit 17; fi
            exit 1'
        result=$?
        (( result == 0 )) && break
        (( result == 17 )) || fail "无法保存到手机 $output"
    fi
    (( ++copy_number ))
    name="$stem ($copy_number)$extension"
done
report_success "已保存到 $output"
