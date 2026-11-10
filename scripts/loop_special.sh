#!/usr/bin/env bash

process_args() {
    # bash中如果以一个空变量for循环，会自动使用$@进行展开
    local item
    for item; do
        echo "arg: $item"
    done
}

process_args "$@"
