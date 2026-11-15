#!/usr/bin/env bash

set -Eeuo pipefail

# Global Variables
process_name=""
process_user=""
declare -i terminate_requested=0

declare -a pids=()

declare -i signal_sent_count=0
declare -i failed_count=0
declare -i disappeared_count=0

usage() {
    cat <<'EOF'
Usage:
    process_monitor.sh [OPTIONS] <processName>

Options:
    -k, --kill    Provide kill process function
    -u, --user    The Process Owner
    -h, --help    Display this help message

Examples:
    ./process_monitor.sh gopls
    ./process_monitor.sh --kill gopls
    ./process_monitor.sh gopls --kill
    ./process_monitor.sh --user=jrz --kill gopls
    ./process_monitor.sh --user jrz --kill gopls
EOF
}

error() {
    printf '[ERROR] %s\n' "$*">&2
}

info() {
    printf '[INFO] %s\n' "$*"
}

parse_arguments() {
    while (($# > 0)); do 
        case "$1" in
            -k|--kill)
                terminate_requested=1
                shift
                ;;
            -u|--user)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "Option $1 requires a username!"
                    exit 1
                fi

                if [[ -n "$process_user" ]]; then 
                    error "User specified multiple times!"
                    exit 1
                fi
                process_user=$2
                shift 2
                ;;
            --user=*)
                if [[ -n "$process_user" ]]; then
                    error "User specified multiple times!"
                    exit 1
                fi
                process_user="${1#*=}"
                
                if [[ -z "$process_user" ]]; then
                    error "Option --user requires a username"
                    exit 1
                fi
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift

                if (($# != 1)) || [[ -n "$process_name" ]]; then
                    error "Exactly one process name is required"
                    exit 1
                fi
                process_name=$1
                shift
                ;;
            -*)
               error "Unknown option: $1" 
               usage >&2
               exit 1
               ;;
           *)
               if [[ -n "$process_name" ]]; then
                   error "Multiple process names provided"
                   exit 1
               fi
               process_name=$1
               shift
               ;;
       esac
    done

    if [[ -z "$process_name" ]]; then
        error "Process name not provided"
        usage >&2
        exit 1
    fi
}

find_processes() {
    local pid_output
    local status
    local -a pgrep_args=()

    if [[ -n "$process_user" ]]; then
        pgrep_args+=(-u "$process_user")
    fi

    if pid_output=$(pgrep "${pgrep_args[@]}" -- "$process_name"); then
        readarray -t pids <<< "$pid_output"
    else
        status=$?
        if ((status==1)); then
            error "Process not found: $process_name"
        else
            error "pgrep failed with exit status: $status"
        fi
        return 1
    fi

    info "Found ${#pids[@]} matching processes"
}

get_process_info() {
    local pid=$1

    REPLY=$(ps -p "$pid" \
        -o pid= \
        -o user= \
        -o cmd= \
        -o pcpu= \
        -o pmem= \
        -o etime= \
        -o start=)

    [[ -n "$REPLY" ]]
}

show_process_info() {
    local pid
    local process_info

    printf '\n'
    printf '%-10s %-10s %-20s %-10s %-10s %-15s %-15s \n' \
        "PID" "USER" "COMMAND" "CPU(%)" "MEM(%)" "ELAPSED" "START"

    printf '%s\n' \
        "-----------------------------------------------------------------------"

    for pid in "${pids[@]}"; do
        if get_process_info "$pid"; then
            process_info=$REPLY
            printf '%s\n' "$process_info"
        else
            error "Process $pid disappeared before inspection"
            ((++disappeared_count))
        fi
    done

    printf '\n'
}

terminate_processes() {
    local pid

    info "Sending SIGTERM to matching processes..."
    for pid in "${pids[@]}"; do
        if kill -TERM "$pid"; then
            info "SIGTERM sent successfully: PID=$pid"
            ((++signal_sent_count))
        else
            error "Failed to terminate PID=$pid"
            ((++failed_count))
        fi
    done
}

print_summary() {
    printf '\n'
    printf '%s\n' '========== Summary =========='

    printf 'Process name: %s\n' "$process_name"
    printf 'Matched:      %d\n' "${#pids[@]}"

    if ((terminate_requested)); then
        printf 'Signal sent:   %d\n' "$signal_sent_count"
        printf 'Failed:       %d\n' "$failed_count"
    fi

    printf 'Disappeared:  %d\n' "$disappeared_count"

    printf '%s\n' '============================='

}

main() {
    # Step 1: Parse arguments.
    parse_arguments "$@"

    # Step 2: Find matching processes. 
    if ! find_processes; then 
        return 1
    fi

    # Step 3: Display process information.
    show_process_info

    # Step 4: Terminate processes if requested.
    if ((terminate_requested)); then
        terminate_processes
    fi

    # Step 5: Print execution summary.
    print_summary

    if ((failed_count > 0 || disappeared_count > 0)); then 
        return 1
    fi
    
    return 0
}

main "$@"
