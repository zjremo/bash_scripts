#!/usr/bin/env bash

# -e 任何命令返回非零状态时立即退出脚本
# -u 使用未定义变量时报错退出 (防止拼错变量名静默失败)
# -o 管道中任何一个命令失败，整个管道返回值就是失败
set -Eeuo pipefail

# ==========================================
# Global Variables
# ==========================================

declare -a files=()
declare -A category_count=()

declare -i dry_run=0
declare -i moved_count=0
declare -i failed_count=0
declare -i skipped_count=0

dir_path=""

# Include hidden files and ignore unmatched glob patterns.
shopt -s nullglob dotglob

# ==========================================
# Error Handling
# ==========================================

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

info() {
    printf '[INFO] %s\n' "$*"
}

cleanup() {
    # Reserved for temporary resource cleanup.
    :
}

trap cleanup EXIT

# ==========================================
# Usage
# ==========================================

usage() {
    cat <<'EOF'
Usage:
    file_manager.sh [OPTIONS] <directory>

Options:
    -n, --dry-run    Preview operations without modifying files
    -h, --help       Display this help message

Examples:
    ./file_manager.sh ~/Downloads
    ./file_manager.sh --dry-run ~/Downloads
    ./file_manager.sh ~/Downloads --dry-run
EOF
}

# ==========================================
# Argument Parsing
# ==========================================

parse_args() {
    while (($# > 0)); do
        case "$1" in
            -n|--dry-run)
                dry_run=1
                shift
                ;;

            -h|--help)
                usage
                exit 0
                ;;

            -*)
                error "Unknown option: $1"
                usage >&2
                exit 1
                ;;

            *)
                if [[ -n "$dir_path" ]]; then
                    error "Multiple directories provided"
                    exit 1
                fi

                dir_path=$1
                shift
                ;;
        esac
    done

    if [[ -z "$dir_path" ]]; then
        error "Directory path not provided"
        usage >&2
        exit 1
    fi
}

# ==========================================
# Directory Validation
# ==========================================

validate_directory() {
    if [[ ! -d "$dir_path" ]]; then
        error "Not a valid directory: $dir_path"
        exit 2
    fi

    if ! dir_path=$(realpath -e -- "$dir_path"); then
        error "Failed to resolve directory path"
        exit 2
    fi

    if [[ ! -r "$dir_path" || ! -x "$dir_path" ]]; then
        error "Directory is not accessible: $dir_path"
        exit 2
    fi
}

# ==========================================
# File Classification
# ==========================================

get_category() {
    local file=$1

    case "$file" in
        *.txt)
            REPLY="txt"
            ;;
        *.jpg|*.png)
            REPLY="img"
            ;;
        *.log)
            REPLY="log"
            ;;
        *.md)
            REPLY="md"
            ;;
        *)
            REPLY="addition"
            ;;
    esac
}

# ==========================================
# Step 1: Collect Files
# ==========================================

collect_files() {
    local file
    local category

    for file in "$dir_path"/*; do
        # Only process regular files, not directories or symlinks.
        [[ -f "$file" && ! -L "$file" ]] || continue

        files+=("$file")

        get_category "$file"
        category=$REPLY

        ((category_count["$category"] += 1))
    done

    info "Found ${#files[@]} files"

    for category in "${!category_count[@]}"; do
        printf '  %-10s %d files\n' \
            "$category" "${category_count[$category]}"
    done
}

# ==========================================
# Step 2: Create Category Directories
# ==========================================

create_directories() {
    local category
    local target_dir

    for category in "${!category_count[@]}"; do
        target_dir="$dir_path/$category"

        if [[ -d "$target_dir" ]]; then
            info "Directory already exists: $target_dir"
            continue
        fi

        if ((dry_run)); then
            info "[DRY-RUN] mkdir -p -- $target_dir"
            continue
        fi

        if mkdir -p -- "$target_dir"; then
            info "Created directory: $target_dir"
        else
            error "Failed to create directory: $target_dir"
            return 1
        fi
    done
}

# ==========================================
# Step 3: Move Files
# ==========================================

move_files() {
    local file
    local category
    local target_dir
    local target_file

    for file in "${files[@]}"; do
        get_category "$file"
        category=$REPLY

        target_dir="$dir_path/$category"
        target_file="$target_dir/${file##*/}"

        if ((dry_run)); then
            info "[DRY-RUN] mv -- $file $target_dir/"
            continue
        fi

        # Avoid overwriting existing files.
        if [[ -e "$target_file" || -L "$target_file" ]]; then
            error "Target already exists: $target_file"
            ((++skipped_count))
            continue
        fi

        if mv -n -- "$file" "$target_dir/"; then
            # GNU mv -n may return success even if it did not move.
            if [[ -e "$file" || -L "$file" ]]; then
                error "File was not moved: $file"
                ((++failed_count))
                continue
            fi

            info "Moved: $file -> $target_dir/"
            ((++moved_count))
        else
            error "Failed to move: $file"
            ((++failed_count))
        fi
    done
}

# ==========================================
# Step 4: Summary
# ==========================================

print_summary() {
    printf '\n'
    printf '%s\n' '========== Summary =========='

    if ((dry_run)); then
        info "Dry-run completed. No files were moved."
    else
        printf 'Moved:   %d\n' "$moved_count"
        printf 'Skipped: %d\n' "$skipped_count"
        printf 'Failed:  %d\n' "$failed_count"
    fi

    printf 'Directory: %s\n' "$dir_path"
    printf '%s\n' '============================='
}

# ==========================================
# Main
# ==========================================

main() {
    parse_args "$@"

    validate_directory

    if ((dry_run)); then
        info "Dry-run mode enabled"
    fi

    info "Target directory: $dir_path"

    collect_files

    if ((${#files[@]} == 0)); then
        info "No files found"
        return 0
    fi

    printf '\n'

    if ! create_directories; then
        error "Directory creation failed, aborting"
        return 1
    fi

    move_files

    print_summary

    if ((failed_count > 0 || skipped_count > 0)); then
        return 1
    fi

    return 0
}

main "$@"

