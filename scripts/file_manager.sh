#!/usr/bin/env bash

if [[ -z $1 ]]; then
    echo "dir_path not provided!"
    exit 1
fi

dir_path=$1 # dir_path 目录路径

if [[ $dir_path == */ ]]; then
    dir_path="${dir_path%/}"
fi

# 校验目录存在
if [[ ! -d "$dir_path"  ]]; then
    echo "error: $dir_path is not a valid directory"
    exit 2
fi

declare -i dry_run=0
if [[ $2 == "--dry-run" ]]; then
    dry_run=1
fi

if (( dry_run == 1 )); then
    echo "dry_run mode open..."
fi

# Step1: 取出所有的文件和后缀
declare -a files
declare -A sufixes
cnt=0
for file in "$dir_path"/*; do
    if [[ -f "$file" ]]; then
        files[$cnt]="$file"
        ((cnt++))
        case "$file" in
            *.txt)
                ((sufixes["txt"]++))
                ;;
            *.jpg | *.png)
                ((sufixes["img"]++))
                ;;
            *.log)
                ((sufixes["log"]++))
                ;;
            *.md)
                ((sufixes["md"]++))
                ;;
            *)
                ((sufixes["addition"]++))
        esac
    fi
done

echo "files: ${files[@]}"

for key in "${!sufixes[@]}"; do
    printf "%s files count: %s\n" $key ${sufixes[$key]}
    # create dir to store files if not exists
    if [[ -d "$dir_path/$key" ]]; then
        echo "$dir_path/$key has been created!, no need to create"
    else
        case $dry_run in 
            0) 
                if ! mkdir -p "$dir_path/$key"; then
                    echo "create $dir_path/$key failed, exit..."
                    exit 2
                fi
                echo "create $dir_path/$key successfully!"
                ;;
            1)
                echo "It's dry-run, create $dir_path/$key successfully!"
        esac
    fi
done

# Step2: 将文件分类装入新建的分类目录下面
for file in "${files[@]}"; do
    dst_dir="$dir_path/addition"
    case $file in
        *.txt)
            dst_dir="$dir_path/txt"
            ;;
        *.jpg | *.png)
            dst_dir="$dir_path/img"
            ;;
        *.log)
            dst_dir="$dir_path/log"
            ;;
        *.md)
            dst_dir="$dir_path/md"
            ;;
    esac
    case $dry_run in 
        0)
            (mv "$file" "$dst_dir/")
            echo "mv $file $dst_dir/ successfully!"
            ;;
        1)
            echo "It's dry-run, mv $file $dst_dir/ successfully!"
            ;;
    esac
done
printf "all files have been traversed, in %s\n" $dir_path
