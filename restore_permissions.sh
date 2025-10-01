#!/bin/bash

# 恢复目录的默认权限

# 检查是否提供了目录参数
if [ $# -ne 1 ]; then
    echo "用法: $0 <目录路径>"
    exit 1
fi

TARGET_DIR="$1"

# 检查目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误: '$TARGET_DIR' 不是一个有效的目录"
    exit 1
fi

echo "开始恢复 '$TARGET_DIR' 中的文件和目录权限..."

# 设置目录权限为755 (rwxr-xr-x)
find "$TARGET_DIR" -type d -exec chmod 755 {} \;

# 设置文件权限为644 (rw-r--r--)
find "$TARGET_DIR" -type f -exec chmod 644 {} \;

echo "权限恢复完成！"
