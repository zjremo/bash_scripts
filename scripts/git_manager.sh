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
# number of repositories whose operation failed
declare -i failure_count=0

# exclude dir
declare -a exclude_dirs=()
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
                    error "workspace can't be specified multiple times!"
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

# 判断路径是否命中 --exclude（命中目录本身或它的整棵子树）
is_excluded() {
    local path="$1"
    local excluded

    if ((${#exclude_dirs[@]} == 0)); then
        return 1
    fi

    for excluded in "${exclude_dirs[@]}"; do
        # validate 阶段已 realpath，尾部不会带 /，直接前缀匹配即可
        if [[ "$path" == "$excluded" || "$path" == "$excluded"/* ]]; then
            return 0
        fi
    done

    return 1
}

# 取仓库当前分支名，detached HEAD 时返回非 0
get_current_branch() {
    local repo="$1"
    git -C "$repo" symbolic-ref --short -q HEAD
}

record_failure() {
    error "$1"
    failure_count+=1
}

# 统一执行会修改仓库的 git 命令：
# dry-run 只打印计划，verbose 额外打印实际命令
run_git() {
    local repo="$1"
    shift

    if ((dry_mode)); then
        info "[DRY-RUN] $repo: git $*"
        return 0
    fi

    if ((verbose_mode)); then
        info "$repo: git $*"
    fi

    git -C "$repo" "$@"
}

# 对单个已发现的仓库做过滤，然后执行操作
process_repository() {
    local repo="$1"
    local branch

    # 过滤条件一：--branch 只保留当前分支匹配的仓库（不会切换分支）
    if [[ -n "$branch_name" ]]; then
        if ! branch=$(get_current_branch "$repo"); then
            if ((verbose_mode)); then
                info "skip $repo: detached HEAD"
            fi
            return 0
        fi

        if [[ "$branch" != "$branch_name" ]]; then
            if ((verbose_mode)); then
                info "skip $repo: current branch '$branch' != '$branch_name'"
            fi
            return 0
        fi
    fi

    # 过滤条件二：--exclude 已在上层 dfs 剪枝，这里无需重复判断

    info "==> $repo"

    case "$git_operation" in
        status)
            # status 只读，dry-run 下照常执行
            if ((verbose_mode)); then
                info "$repo: git status"
                git -C "$repo" status || record_failure "git status failed: $repo"
            else
                git -C "$repo" status --short --branch || record_failure "git status failed: $repo"
            fi
            ;;
        fetch)
            run_git "$repo" fetch --all || record_failure "git fetch failed: $repo"
            ;;
        pull)
            run_git "$repo" pull --ff-only || record_failure "git pull failed: $repo"
            ;;
        push)
            run_git "$repo" push || record_failure "git push failed: $repo"
            ;;
        *)
            error "unknown operation: $git_operation"
            return 1
            ;;
    esac

    return 0
}

dfs_operation() {
    local root_dir="$1"
    local f

    for f in "$root_dir"/*; do
        # 只处理真实目录：普通文件跳过，符号链接跳过（防循环/越界）
        if [[ ! -d "$f" || -L "$f" ]]; then
            continue
        fi

        # 已经是git仓库，不用继续向下探测
        if [[ "${f##*/}" == ".git" ]]; then
            continue
        fi

        # 命中 --exclude 的目录连同整棵子树一起剪掉
        if is_excluded "$f"; then
            if ((verbose_mode)); then
                info "skip excluded: $f"
            fi
            continue
        fi

        if [[ -e "$f/.git" ]]; then
            # check filter condition (branch and exclude_dir)
            # process operation (dry-run ? or truely process)
            process_repository "$f"
        fi

        if ((recursive_mode)); then
            dfs_operation "$f"
        fi
    done
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

    # 3. process operation
    dfs_operation "$workspace_dir"

    # 单个仓库失败不中断整体遍历，但最终要返回非 0
    if ((failure_count > 0)); then
        error "$failure_count operation(s) failed!"
        return 1
    fi

    return 0
}

main "$@"
