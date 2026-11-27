#!/bin/zsh -f
# Local download preferences and transfers for the device selected by phone.
emulate -L zsh
setopt extendedglob

mode=$1
adb_bin=$2
serial=$3
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
    file=$4
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
pick_files() {
    local selection_file=$local_stage/selection records
    : > "$selection_file" || fail '无法创建文件选择清单。'
    choose "$@" "$selection_file" >/dev/null || fail '文件选择器未能完成。'
    records=$(< "$selection_file") || fail '无法读取选择的文件。'
    [[ -n $records ]] || exit 0
    [[ $records == *$'\0' ]] || fail '文件选择清单不完整，请重试。'
    records=${records%$'\0'}
    files=("${(@0)records}")
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
        shift 3
        files=("$@")
        if (( ! $#files )) || [[ $#files == 1 && -z $files[1] ]]; then
            local_stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/phone-send.XXXXXXXX") || exit 1
            pick_files send
        fi
        token=$(/usr/bin/uuidgen) || exit 1
        candidate_stage="$remote_downloads/.phone-send-$token"
        remote "mkdir -p $remote_downloads && mkdir ${(qq)candidate_stage}" ||
            fail '无法在手机的「下载」目录创建临时文件夹。'
        remote_stage=$candidate_stage
        destination=$remote_downloads ;;
    get)
        shift 3
        if [[ $1 == --to ]]; then
            (( $# >= 2 )) || fail '缺少保存目录。'
            chosen_folder=$2
            shift 2
            files=("$@")
        else
            # Older launchers pass a single file (or empty picker request), then the destination.
            chosen_folder=$2
            files=()
            [[ -z $1 ]] || files+=("$1")
        fi
        if [[ -n $chosen_folder ]]; then
            downloads=${chosen_folder:a}
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
        if (( ! $#files )); then
            pick_files get "$adb_bin" "$serial" "${0:A}" "$local_stage/list"
        fi
        destination=$downloads ;;
    *) fail '未知的传输方向。' ;;
esac

transfer_file() {
    local file=$1 name=${1:t} stem extension= result
    reason="无法读取文件 $file"
    if [[ $mode == send ]]; then
        [[ -f $file && -r $file ]] || return 1
        reason="未能发送 $file"
        "$adb_bin" -s "$serial" push "${file:a}" "$remote_stage/payload" || return 1
    else
        [[ $file == /* ]] || file="$remote_downloads/$file"
        reason="文件不在手机共享存储中：$file"
        [[ -n $name && $file == (/sdcard/*|/storage/*) && "/$file/" != */../* ]] || return 1
        reason="手机上找不到可读取的文件 $file"
        remote "test -f ${(qq)file}" || return 1
        reason="未能下载 $file"
        "$adb_bin" -s "$serial" pull "$file" "$payload" && [[ -f $payload ]] || return 1
    fi

    stem=$name
    if [[ -n ${name:e} && -n ${name:r} ]]; then
        stem=${name:r}
        extension=.${name:e}
    fi
    local -i copy_number=0
    while true; do
        output="$destination/$name"
        reason="无法保存到 $output"
        if [[ $mode == get ]]; then
            # Publish atomically; use a noclobber reservation on volumes without hard links.
            if /bin/link "$payload" "$output" 2>/dev/null; then return 0; fi
            if [[ ! -e $output && ! -L $output ]] &&
               (setopt noclobber; : > "$output") 2>/dev/null; then
                /bin/mv -f -- "$payload" "$output" && return 0
                /bin/rm -f -- "$output"
                return 1
            fi
            [[ -e $output || -L $output ]] || return 1
        else
            # On Android shared storage, reserve the name before moving our finished payload.
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
            (( result == 0 )) && return 0
            (( result == 17 )) || return 1
        fi
        (( ++copy_number ))
        name="$stem ($copy_number)$extension"
    done
}

integer completed=0 index=0
failed_names=()
for file in "${files[@]}"; do
    (( ++index ))
    # A successful download may be hard-linked into place. Each pull needs its own inode.
    payload="$local_stage/payload-$index"
    if transfer_file "$file"; then
        (( ++completed ))
        if (( $#files > 1 )); then print -r -- "phone：已保存到 $output"; fi
    else
        if (( $#files == 1 )); then fail "$reason"; fi
        print -ru2 -- "phone：$reason"
        failed_names+=("${file:t}")
    fi
    if [[ $mode == get ]]; then /bin/rm -f -- "$payload"; fi
done

if (( $#failed_names )); then
    sample="${(j:、:)failed_names[1,3]}"
    if (( $#failed_names > 3 )); then sample+=" 等"; fi
    fail "已完成 $completed/$#files 个文件。失败 $#failed_names 个：$sample。"
elif (( $#files == 1 )); then
    report_success "已保存到 $output"
else
    report_success "已保存 $completed 个文件到 $destination"
fi
