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
output_path=""

declare -i scan_lines=0
declare -i follow_mode=0

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
    local option

    while (($# > 0)); do
        option=$1

        case "$option" in
            -h|--help)
                usage
                exit 0
                ;;

            -l|--level)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a log level"
                    return 1
                fi

                if [[ -n "$log_level" ]]; then
                    error "Log level specified multiple times"
                    return 1
                fi

                log_level=${2^^}
                shift 2
                ;;

            --level=*)
                if [[ -n "$log_level" ]]; then
                    error "Log level specified multiple times"
                    return 1
                fi

                log_level=${1#*=}
                log_level=${log_level^^}

                if [[ -z "$log_level" ]]; then
                    error "Option --level requires a log level"
                    return 1
                fi

                shift
                ;;

            -k|--keyword)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a keyword"
                    return 1
                fi

                if [[ -n "$filter_keyword" ]]; then
                    error "Keyword specified multiple times"
                    return 1
                fi

                filter_keyword=$2
                shift 2
                ;;

            --keyword=*)
                if [[ -n "$filter_keyword" ]]; then
                    error "Keyword specified multiple times"
                    return 1
                fi

                filter_keyword=${1#*=}

                if [[ -z "$filter_keyword" ]]; then
                    error "Option --keyword requires a keyword"
                    return 1
                fi

                shift
                ;;

            -n|--lines)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a positive integer"
                    return 1
                fi

                if ((scan_lines != 0)); then
                    error "Lines specified multiple times"
                    return 1
                fi

                if [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                    error "Lines must be a positive integer"
                    return 1
                fi

                scan_lines=$2
                shift 2
                ;;

            --lines=*)
                if ((scan_lines != 0)); then
                    error "Lines specified multiple times"
                    return 1
                fi

                option=${1#*=}

                if [[ ! "$option" =~ ^[1-9][0-9]*$ ]]; then
                    error "Lines must be a positive integer"
                    return 1
                fi

                scan_lines=$option
                shift
                ;;

            -f|--follow)
                if ((follow_mode)); then
                    error "Follow mode specified multiple times"
                    return 1
                fi

                follow_mode=1
                shift
                ;;

            -o|--output)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires an output path"
                    return 1
                fi

                if [[ -n "$output_path" ]]; then
                    error "Output path specified multiple times"
                    return 1
                fi

                output_path=$2
                shift 2
                ;;

            --output=*)
                if [[ -n "$output_path" ]]; then
                    error "Output path specified multiple times"
                    return 1
                fi

                output_path=${1#*=}

                if [[ -z "$output_path" ]]; then
                    error "Option --output requires an output path"
                    return 1
                fi

                shift
                ;;

            --)
                shift

                if (($# != 1)) || [[ -n "$logfile_path" ]]; then
                    error "Exactly one log file is required"
                    return 1
                fi

                logfile_path=$1
                shift
                ;;

            -*)
                error "Unknown option: $1"
                usage >&2
                return 1
                ;;

            *)
                if [[ -n "$logfile_path" ]]; then
                    error "Multiple log files provided"
                    return 1
                fi

                logfile_path=$1
                shift
                ;;
        esac
    done

    if [[ -z "$logfile_path" ]]; then
        error "Log file path not provided"
        usage >&2
        return 1
    fi
}

# validation
#
# 校验日志级别
validate_arguments() {
    case "$log_level" in
        ""|DEBUG|INFO|WARN|ERROR)
            ;;
        *)
            error "Invalid log level: $log_level"
            return 1
            ;;
    esac
}

validate_files() {
    # output path and input path
    # input_path 路径必须存在，必须是文件且可读
    local input_path
    local output_parent

    if [[ ! -f "$logfile_path" ]]; then
        error "Log file does not exist or is not a regular file"
        return 1
    fi

    if [[ ! -r "$logfile_path" ]]; then
        error "Log file is not readable"
        return 1
    fi

    input_path=$(realpath -e -- "$logfile_path") || {
        error "Failed to resolve log file path"
        return 1
    }

    logfile_path=$input_path

    if [[ -n "$output_path" ]]; then
        output_parent=$(dirname -- "$output_path")

        # 判断父目录是否存在
        if [[ ! -d "$output_parent" || ! -w "$output_parent" ]]; then 
            error "Output directory dose not exist or is not writable"
            return 1
        fi

        output_path=$(realpath -m -- "$output_path") || {
            error "Failed to resolve output path"
            return 1
        }
        
        # ensure output_path != input_path
        if [[ "$output_path" == "$logfile_path" ]]; then
            error "Output file must differ from input log file"
            return 1
        fi

        # 如果这个output_path是存在的，那么它必须是regular file且是可写的
        if [[ -e "$output_path" && ! -f "$output_path" ]]; then
            error "Output path is not a regular file"
            return 1
        fi

        if [[ -e "$output_path" && ! -w "$output_path" ]]; then
            error "Output file is not writable"
            return 1
        fi
    fi
}

# output 输出可能是stdout或者一个文件
init_output() {
    if [[ -n "$output_path" ]]; then
        if ! exec 3> "$output_path"; then
            error "Failed to open output file: $output_path" 
            return 1
        fi
    else
        exec 3>&1
    fi
}

close_output() {
    exec 3>&-
}

# 显示模式可能是-f实时读取或者读取一次整个文件
read_log_source() {
    if ((scan_lines > 0)); then
        tail -n "$scan_lines" -- "$logfile_path"
    else
        cat -- "$logfile_path"
    fi
}

get_line_level() {
    local line=$1

    read -r _ _ REPLY _ <<< "$line"
    REPLY=${REPLY^^} # 将获取的level全部大写
}

# Log Filtering 通过日志等级和keyword过滤
should_print_line() {
    local line=$1
    local line_level
    local line_lower
    local keyword_lower

    get_line_level "$line"
    line_level=$REPLY

    # Filter by log level
    if [[ -n "$log_level" && "$line_level" != "$log_level" ]]; then
        return 1
    fi

    # Filter by keyword 
    if [[ -n "$filter_keyword" ]]; then
        line_lower=${line,,}
        keyword_lower=${filter_keyword,,}

        if [[ "$line_lower" != *"$keyword_lower"* ]]; then
            return 1
        fi
    fi

    return 0
}

filter_stream() {
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if should_print_line "$line"; then
            printf '%s\n' "$line" >&3
        fi
    done
}

filter_process() {
    read_log_source | filter_stream
}

# Log Summary Mode
summarize_stream() {
    local line
    local line_level

    local -i line_count=0
    local -i debug_count=0
    local -i info_count=0
    local -i warn_count=0
    local -i error_count=0
    local -i unknown_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        ((++line_count))

        get_line_level "$line"
        line_level=$REPLY

        case "$line_level" in
            DEBUG)
                ((++debug_count))
                ;;
            INFO)
                ((++info_count))
                ;;
            WARN)
                ((++warn_count))
                ;;
            ERROR)
                ((++error_count))
                ;;
            *)
                ((++unknown_count))
                ;;
        esac
    done

    cat <<EOF >&3
========== Log Summary ==========
Log file: $logfile_path
Total lines: $line_count

DEBUG:   $debug_count
INFO:    $info_count
WARN:    $warn_count
ERROR:   $error_count
UNKNOWN: $unknown_count

=================================
EOF
}

get_log_summary() {
    read_log_source | summarize_stream
}

# Real-time Monitoring
follow_logs() {
    local -i initial_lines=0

    initial_lines=$scan_lines

    info "Following log file: $logfile_path"
    info "Press Ctrl+C to stop monitoring"

    if ((initial_lines > 0)); then
        tail -n "$initial_lines" -F -- "$logfile_path" | filter_stream
    else
        tail -n 0 -F -- "$logfile_path" | filter_stream
    fi
}

handle_sigint() {
    printf '\n' >&2
    info "Monitoring stopped by user"
    exit 130
}

handle_sigterm() {
    printf '\n' >&2
    info "Monitoring terminated"
    exit 143
}

main() {
    parse_arguments "$@"
    validate_arguments
    validate_files
    init_output

    if ((follow_mode)); then
        trap handle_sigint INT
        trap handle_sigterm TERM
        follow_logs
    elif [[ -n "$log_level" || -n "$filter_keyword" ]]; then
        filter_process
    else
        get_log_summary
    fi

    close_output
}

main "$@"
