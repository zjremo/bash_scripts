#!/usr/bin/env bash

declare -A dict

while [[ $# -gt 0 ]]; do   
    case "$1" in
        --*)
            key="${1#--}"

            if [[ $# -eq 1 || "$2" == -* ]]; then
                dict["$key"]=true
                shift
            else # key -value
                dict["$key"]="$2"
                shift 2
            fi
            ;;
        -*)
            key="${1#-}"
            if [[ $# -eq 1 || "$2" == -* ]]; then
                dict["$key"]=true
                shift
            else # key -value
                dict["$key"]="$2"
                shift 2
            fi
            ;;
        *)
            echo "unknown argument: $1">&2
            exit 1
            ;;
    esac
done

for key in "${!dict[@]}"; do
    printf "%s = %s\n" "$key" "${dict[$key]}"
done
