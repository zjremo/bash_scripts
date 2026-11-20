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

usage() {
    cat <<'EOF'
Usage:
    git_manager.sh [OPTIONS] <directory>

Description:
    Automatically discover and manage Git repositories under a directory.

Options:
    -r, --recursive       Recursively scan subdirectories
    -s, --status          Display Git repository status
    -p, --pull            Pull updates from remote repositories
        --push            Push local commits to remote repositories
        --fetch           Fetch updates from all remote repositories
    -n, --dry-run         Preview operations without executing them
    -v, --verbose         Display detailed execution information
        --branch NAME     Only operate on repositories using the specified branch
        --exclude NAME    Exclude a repository by directory name
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

    # Exclude a repository
    ./git_manager.sh --recursive --exclude temp --status ~/workspace

    # Preview pull operations
    ./git_manager.sh --recursive --dry-run --pull ~/workspace

Notes:
    1. Exactly one operation must be specified:
       --status, --fetch, --pull, or --push.

    2. --branch filters repositories by their current branch.
       It does not switch branches.

    3. --pull uses --ff-only to prevent automatic merge commits.

    4. --dry-run displays planned operations without modifying repositories.

    5. --exclude can be specified multiple times.
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

    # -d 会将符号连接也算进去，后面必须排除这个情况
    if [[ ! -d "$workspace" || -L "$workspace" ]]; then
        return 1
    fi

    REPLY=$(realpath -e -- "$workspace")
    # 检查权限，一个是要可读，并且向下搜索要保证可执行
    if [[ ! -r "$REPLY" || ! -x "$REPLY" ]]; then
        return 1
    fi
    return 0
}

if [[ -z "$1" ]]; then
    echo "You must provide workspace dir!"
    exit 1
fi


if validate_workspace "$1"; then
    workspace=$REPLY
else
    error "Invalid workspace: $1"
    exit 1
fi

echo "workspace is legal"

find_all_repositories "$workspace"
