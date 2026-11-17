#!/usr/bin/env bash

# 处理的日志格式为:
# 2026-11-17 00:01:02 DEBUG connecting to database
# 2026-11-17 00:01:03 INFO server started
# 2026-11-17 00:01:04 WARN connection pool is almost full
# 2026-11-17 00:01:05 ERROR database connection failed
# 2026-11-17 00:01:06 INFO request completed

# -e 退出码非0时脚本立即退出
# -u 使用未定义的变量时报错退出
# -o pipefail 管道中cmd1 | cmd2 任意一个命令失败整个管道失败
# -E ERR trap和-e的行为传递到函数
set -Eeuo pipefail

# Global Variables
log_level=""
filter_keyword=""
logfile_path=""
declare -i scan_lines=0 # 为0代表查看的是全文，不为0代表倒数几行
# declare -i follow_mode=0 # 为0代表暂时展示，不是实时查看
declare -i output_mode=0 # 0代表stdout, 1代表输出文件路径
output_path="" # output_mode为1时才起作用

usage() {
    cat <<'EOF'
Usage:
    log_monitor.sh [OPTIONS] <log_file>

Options:
    -l, --level     Provide log level to grep
    -k, --keyword   Provide the keyword to filter
    -n, --lines     Analysis only the last lines of count n
    -f, --follow    实时查看日志
    -o, --output    Store the result to the file
    -h, --help      Display this help message

Examples:
    ./log_moniter.sh ./app.log
    ./log_monitor.sh --level ERROR ./app.log
    ./log_monitor.sh --keyword database ./app.log
    ./log_monitor.sh -n 100 -l ERROR ./app.log
    ./log_monitor.sh --level ERROR --follow ./app.log
    ./log_monitor.sh -l ERROR -f -o ./error.log ./app.log
}
EOF
}

error() {
    printf '[ERROR] %s\n' "$*">&2
}

info() {
    printf '[info] %s\n' "$*"
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--level)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a log level!"
                    exit 1
                fi

                if [[ -n "$log_level" ]]; then
                    error "Mutiple log_level provided"
                    exit 1
                fi
                log_level=$2
                shift 2
                ;;
            -n|--lines)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a lines"
                    exit 1
                fi

                if ((scan_lines != 0)); then
                    error "Multiple scan_lines provided"
                    exit 1
                fi
                scan_lines=$2
                shift 2
                ;;
            -k|--keyword)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a keyword"
                    exit 1
                fi

                if [[ -n "$filter_keyword" ]]; then
                    error "Mutiple filter_keyword provided"
                    exit 1
                fi
                filter_keyword=$2
                shift 2
                ;;
            -o|--output) 
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires you to provide output_path"
                    exit 1
                fi

                if [[ -n "$output_path" ]]; then
                    error "Mutiple output_path provided"
                    exit 1
                fi
                output_mode=1
                output_path=$(realpath "$2")
                shift 2
                ;;
            # -f|--follow)
            #     follow_mode=2
            #     shift
            #     ;;
            --)
                shift
                
                if (($# != 1)) || [[ -n "$logfile_path" ]]; then
                    error "Exactly one logfile_path is required"
                    exit 1
                fi
                logfile_path=$1
                shift
                ;;
            -*)
                error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -n "$logfile_path" ]]; then
                    error "Multiple logfile_path provided"
                    exit 1
                fi
                logfile_path=$1
                shift
                ;;
        esac
    done

    if [[ -z "$logfile_path" ]]; then
        error "Logfile path not provided"
        usage >&2
        exit 1
    fi
}

get_log_summary() {
    local -i line_count=0
    local -i debug_count=0
    local -i info_count=0
    local -i warn_count=0
    local -i error_count=0

    local -a src_cmd=(cat "$logfile_path")
    ((scan_lines != 0)) && src_cmd=(tail -n "$scan_lines" "$logfile_path")

    # 打开 fd3: output_mode为1时指向输出文件, 否则指向终端
    if ((output_mode == 1)); then
        exec 3> "$output_path"
    else
        exec 3>&1
    fi

    # 只读取一遍文本内容 且为流式读取
    while read -r line; do
        # 剔除空行
        if [[ -z "$line" ]]; then
            continue
        fi

        ((++line_count))
        # -q 静默模式
        if grep -qi "debug" <<< "$line"; then
            ((debug_count+=1))
        elif grep -qi "info" <<< "$line"; then
            ((info_count+=1))
        elif grep -qi "warn" <<< "$line"; then
            ((warn_count+=1))
        else
            ((error_count+=1))
        fi
    done< <("${src_cmd[@]}")

    # 写入控制台 or 文件路径
    cat<<EOF >&3
========== Log Summary ==========
Log file: $logfile_path
Total lines: $line_count

DEBUG: $debug_count
INFO:  $info_count
WARN:  $warn_count
ERROR: $error_count

=================================
EOF
    exec 3>&-
}

filter_process() {
    local -a src_cmd=(cat "$logfile_path")
    ((scan_lines != 0)) && src_cmd=(tail -n "$scan_lines" "$logfile_path")

    # 打开 fd3: output_mode为1时指向输出文件, 否则指向stdout
    if ((output_mode == 1)); then
        exec 3> "$output_path"
    else
        # 打开文件时清空一次，后续printf是接连写入
        exec 3>&1
    fi

    # 级别和关键字是"与"的关系，用连续的 grep 管道过滤
    while read -r line; do
        printf '%s\n' "$line" >&3
    done< <(
        if [[ -n "$log_level" && -n "$filter_keyword" ]]; then
            "${src_cmd[@]}" | grep -i -e "$log_level" | grep -i -e "$filter_keyword"
        elif [[ -n "$log_level" ]]; then
            "${src_cmd[@]}" | grep -i -e "$log_level"
        elif [[ -n "$filter_keyword" ]]; then
            "${src_cmd[@]}" | grep -i -e "$filter_keyword"
        else
            "${src_cmd[@]}"
        fi
    )
    exec 3>&-
}

main() {
    # Step 1: Parse arguments
    parse_arguments "$@"

    # Step 2: 判断模式, 一种是需要过滤的，一种是没有过滤的基于全部
    if [[ -n "$log_level" || -n "$filter_keyword" ]]; then # 需要过滤
        filter_process
    else
        get_log_summary # scan_lines and output_mode影响
    fi
}

main "$@"
