#!/usr/bin/env bash

getCategory() {
    local file=$1
    case $file in
        *.txt)
            echo "txt"
            ;;
        *.jpg | *.png)
            echo "img"
            ;;
        *.log)
            echo "log"
            ;;
        *.md)
            echo "md"
            ;;
        *)
            echo "addition"
            ;;
    esac
}

if [[ -z $1 ]]; then
    echo "dir_path not provided!"
    exit 1
fi

dir_path=$1 # dir_path 目录路径

if [[ "$dir_path" != "/" ]]; then
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
        ((++cnt))
        category=$(getCategory "$file")
        ((sufixes["$category"]+=1))
    fi
done

printf 'files:\n'
printf '  %s\n' "${files[@]}"

for key in "${!sufixes[@]}"; do
    printf "%s files count: %s\n" "$key" "${sufixes[$key]}"
    # create dir to store files if not exists
    if [[ -d "$dir_path/$key" ]]; then
        echo "$dir_path/$key has been created!, no need to create"
    else
        case $dry_run in 
            0) 
                if ! mkdir -p "$dir_path/$key"; then
                    echo "create $dir_path/$key failed, exit...">&2
                    exit 1
                fi
                echo "create $dir_path/$key successfully!"
                ;;
            1)
                echo "[DRY-RUN] mkdir -p $dir_path/$key!"
        esac
    fi
done

# Step2: 将文件分类装入新建的分类目录下面
for file in "${files[@]}"; do
    category=$(getCategory "$file")
    dst_dir="$dir_path/$category"
    case $dry_run in 
        0)
            if mv -- "$file" "$dst_dir/"; then
                echo "mv $file $dst_dir/ successfully!"
            else
                echo "mv $file failed!">&2
                exit 1
            fi
            ;;
        1)
            echo "[DRY-RUN] mv -- $file $dst_dir/"
            ;;
    esac
done
printf "all files have been traversed, in %s\n" $dir_path
