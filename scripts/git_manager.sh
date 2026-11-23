#!/usr/bin/env bash

set -Eeuo pipefail

# 遍历隐藏目录、不让.和..参与匹配
shopt -s nullglob dotglob

error() {
    printf "[ERROR]:%s\n" "$*">&2
}

info() {
    printf "[INFO]:%s\n" "$*"
}

# --exclude 接受一个目录路径，先原样保存，后面统一校验并转成绝对路径
add_exclude() {
    local path="$1"

    if [[ -z "$path" ]]; then
        error "--exclude requires a directory path!"
        return 1
    fi

    exclude_dirs+=("$path")
    return 0
}

# =================
# Global Varibales
# =================
declare -i recursive_mode=0

# Operation mode
declare -i status_mode=0
declare -i pull_mode=0
declare -i push_mode=0
declare -i fetch_mode=0

# dry mode
declare -i dry_mode=0
# verbose mode
declare -i verbose_mode=0

# exclude dir
declare -a exclude_dirs
# branch name
branch_name=""
# workspace dir
workspace_dir=""
# operation
git_operation=""

parse_arguments() {
    local option

    while (($# > 0)); do
        option="$1"
        case "$option" in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--recursive)
                if ((recursive_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                recursive_mode=1
                shift
                ;;
            -s|--status)
                if ((status_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                status_mode=1
                shift
                ;;
            --pull)
                if ((pull_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                pull_mode=1
                shift
                ;;
            --push)
                if ((push_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                push_mode=1
                shift
                ;;
            --fetch)
                if ((fetch_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                fetch_mode=1
                shift
                ;;
            -n|--dry-run)
                if ((dry_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                dry_mode=1
                shift
                ;;
            -v|--verbose)
                if ((verbose_mode)); then
                    error "$option can't be specified multiple times!"
                    return 1
                fi
                verbose_mode=1
                shift
                ;;
            --branch)
                if (($# < 2 )) || [[ -z "$2" || "$2" == -* ]]; then
                    error "$option requires a branch name!"
                    return 1
                fi

                if [[ -n "$branch_name" ]]; then
                    error "$option can't be specified multiple times!"
                    return 1
                fi

                branch_name="$2"
                shift 2
                ;;
            --branch=*)
                if [[ -n "$branch_name" ]]; then
                    error "$option can't be specified multiple times!"
                    return 1
                fi

                branch_name=${1#*=}
                if [[ -z "$branch_name" ]]; then
                    error "$option requires a branch name!"
                    return 1
                fi
                shift
                ;;
            --exclude)
                if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
                    error "$option requires an exclude directory path!"
                    return 1
                fi

                add_exclude "$2" || return 1
                shift 2
                ;;
            --exclude=*)
                add_exclude "${1#*=}" || return 1
                shift
                ;;
            --)
                shift
                if (($# != 1)) || [[ -n "$workspace_dir" ]]; then
                    error "Exactly one position args needed!"
                    return 1
                fi

                workspace_dir="$1"
                shift
                ;;
            *)
                if [[ "$option" == -* ]]; then
                    error "unknown option"
                    return 1
                fi
                
                if [[ -n "$workspace_dir" ]]; then
                    error "$option can't be specified multiple times!"
                    return 1
                fi

                workspace_dir="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$workspace_dir" ]]; then
        error "workspace must be provided!"
        return 1
    fi
}

usage() {
    cat <<'EOF'
Usage:
    git_manager.sh [OPTIONS] <directory>

Description:
    Automatically discover and manage Git repositories under a directory.

Options:
    -r, --recursive       Recursively scan subdirectories
    -s, --status          Display Git repository status
    --pull            Pull updates from remote repositories
    --push            Push local commits to remote repositories
    --fetch           Fetch updates from all remote repositories
    -n, --dry-run         Preview operations without executing them
    -v, --verbose         Display detailed execution information
        --branch NAME     Only operate on repositories using the specified branch
        --exclude PATH    Exclude a repository by path
    -h, --help            Display this help message

Examples:
    # Display repositories in the current directory
    ./git_manager.sh --status .

    # Recursively scan repositories
    ./git_manager.sh --recursive --status ~/workspace

    # Fetch updates from all repositories
    ./git_manager.sh --recursive --fetch ~/workspace

    # Pull updates using fast-forward only
    ./git_manager.sh --recursive --pull ~/workspace

    # Push local commits
    ./git_manager.sh --recursive --push ~/workspace

    # Only operate on repositories using the main branch
    ./git_manager.sh --recursive --branch main --status ~/workspace

    # Exclude a repository by path
    ./git_manager.sh --recursive --exclude ~/workspace/temp --status ~/workspace

    # Preview pull operations
    ./git_manager.sh --recursive --dry-run --pull ~/workspace

Notes:
    1. Exactly one operation must be specified:
       --status, --fetch, --pull, or --push.

    2. --branch filters repositories by their current branch.
       It does not switch branches.

    3. --pull uses --ff-only to prevent automatic merge commits.

    4. --dry-run displays planned operations without modifying repositories.

    5. --exclude accepts a directory path and can be specified multiple times.
       Paths are resolved to absolute paths.
EOF
}

find_all_repositories() {
    local rootDir="$1"  # 当前起始的遍历dir
    for f in "$rootDir"/*; do
        if [[ ! -d "$f" || -L "$f" ]]; then
            continue
        fi

        # check whether the current directory is a Git repository
        if [[ -e "$f/.git" ]]; then
            printf '%s\n' "$f"
            continue
        fi
        find_all_repositories "$f"
    done
}

validate_workspace() {
    local workspace="$1"

    if [[ -L "$workspace" ]]; then
        error "workspace must not be a symlink: $workspace"
        return 1
    fi

    if [[ ! -e "$workspace" ]]; then
        error "workspace does not exist: $workspace"
        return 1
    fi

    # -d 会将符号连接也算进去，上面已经排除
    if [[ ! -d "$workspace" ]]; then
        error "workspace is not a directory: $workspace"
        return 1
    fi

    REPLY=$(realpath -e -- "$workspace") || {
        error "resolve path $workspace failed!"
        return 1
    }
    # 检查权限，一个是要可读，并且向下搜索要保证可执行
    if [[ ! -r "$REPLY" || ! -x "$REPLY" ]]; then
        error "workspace is not readable/executable: $REPLY"
        return 1
    fi
    return 0
}

validate_exclude_dirs() {
    local idx directory dir_path

    for idx in "${!exclude_dirs[@]}"; do
        directory="${exclude_dirs[idx]}"

        if [[ -L "$directory" ]]; then
            error "exclude must not be a symlink: $directory"
            return 1
        fi

        if [[ ! -e "$directory" ]]; then
            error "exclude does not exist: $directory"
            return 1
        fi

        if [[ ! -d "$directory" ]]; then
            error "exclude is not a directory: $directory"
            return 1
        fi

        dir_path=$(realpath -e -- "$directory") || {
            error "resolve path $directory failed!"
            return 1
        }

        exclude_dirs[idx]="$dir_path"
    done

    return 0
}

validate_and_getOps() {
    # 1. Exactly one operation must be specified:
    local -i count=0 # 统计有几个操作被声明了

    local -Ai ops=(
        [status]="$status_mode"
        [pull]="$pull_mode"
        [push]="$push_mode"
        [fetch]="$fetch_mode"
    )

    for k in "${!ops[@]}"; do
        if ((ops[$k] != 0)); then
            REPLY="$k"
            ((count+=1))
        fi
    done

    if ((count == 0)); then
        error "No operations provided!"
        return 1
    fi

    if ((count != 1)); then
        error "multiple operations provided!"
        usage
        return 1
    fi
    return 0
}

main() {
    # 1. parse_arguments
    parse_arguments "$@"

    # 2. validate
    # 2.1 validate for workspace
    validate_workspace "$workspace_dir"
    workspace_dir="$REPLY"
    
    # 2.2 validate for exclude_dir
    validate_exclude_dirs

    # 2.3 validate for operations only one
    validate_and_getOps
    git_operation="$REPLY"
}

main "$@"
