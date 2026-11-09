#!/usr/bin/env bash

process-indexed() {
    # "$@"会进行命令行参数展开
    local arguments=("$@") # 创建为一个数组
    echo "found ${#arguments[@]} arguments"
    
    local IFS=, # 切换分词符，会将后面数组展开后的符号用,连接
    echo "${arguments[*]}"
}

process-associative() {
    local arguments=("$@")
    echo "found: ${#arguments[@]} total arguments"

    declare -A unique # hash表和数组在bash里面都是array
    local item
    for item in "${arguments[@]}"; do # 当弄一个空变量在for时，自动遍历$@
        unique[$item]=1
    done 

    echo "found: ${#unique[@]} unique arguments"
}

process-commands() {
    local arguments=("$@")
    echo "found: ${#arguments[@]} total arguments"
    
    # bash 中如果以一个空变量for循环，会自动使用$@进行展开
    local item
    for item; do
        echo "running command: $item"
        "$item" # 非常危险, 一个字符串居然可以执行命令
    done
}

cmd=$1
echo "script called with arguments: $*"
shift 1
echo "script shifted to arguments: $*"

case "$cmd" in
    indexed)
        process-indexed "$@"
        ;;
    associative)
        process-associative "$@"
        ;;
    commands)
        process-commands "$@"
        ;;
    *)
        echo "unknown cmd: $cmd">&2
        exit 1
        ;;
esac
