#!/bin/bash

# 复制视频文件到 Bundle 的脚本
# 在 Xcode Build Phase 中运行

set -e  # 遇到错误立即退出

echo "=== Copying video files to Bundle ==="

# 检查环境变量
if [ -z "$TARGET_BUILD_DIR" ]; then
    echo "Error: TARGET_BUILD_DIR not set"
    exit 1
fi

if [ -z "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
    echo "Error: UNLOCALIZED_RESOURCES_FOLDER_PATH not set"
    exit 1
fi

# 获取项目根目录（从 Xcode 环境变量推导）
PROJECT_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# 源视频目录
SOURCE_DIR="${PROJECT_ROOT}/ItemManager/asserts"

# 目标 Bundle 目录
BUNDLE_RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

echo "Project Root: ${PROJECT_ROOT}"
echo "Source: ${SOURCE_DIR}"
echo "Destination: ${BUNDLE_RESOURCES_DIR}"

# 检查源目录是否存在
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "Warning: Source directory not found: ${SOURCE_DIR}"
    echo "Skipping video copy."
    exit 0
fi

# 确保目标目录存在
mkdir -p "${BUNDLE_RESOURCES_DIR}/asserts/naicha"
mkdir -p "${BUNDLE_RESOURCES_DIR}/asserts/maomao"

# 复制 naicha 视频
if [ -d "${SOURCE_DIR}/naicha" ]; then
    echo "Copying naicha videos..."
    for file in "${SOURCE_DIR}/naicha"/*.mov; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo "  Copying: ${filename}"
            cp "$file" "${BUNDLE_RESOURCES_DIR}/asserts/naicha/${filename}"
        fi
    done
else
    echo "Warning: naicha directory not found"
fi

# 复制 maomao 视频
if [ -d "${SOURCE_DIR}/maomao" ]; then
    echo "Copying maomao videos..."
    for file in "${SOURCE_DIR}/maomao"/*.mov; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo "  Copying: ${filename}"
            cp "$file" "${BUNDLE_RESOURCES_DIR}/asserts/maomao/${filename}"
        fi
    done
else
    echo "Warning: maomao directory not found"
fi

# 复制 asserts 根目录下的其他资源（如字体、bgm等）
if [ -d "${SOURCE_DIR}" ]; then
    echo "Copying other resources from asserts root..."
    for file in "${SOURCE_DIR}"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            # 跳过 .md 文件
            if [[ "$filename" != *.md ]]; then
                echo "  Copying: ${filename}"
                cp "$file" "${BUNDLE_RESOURCES_DIR}/asserts/${filename}"
            fi
        fi
    done
fi

echo "=== Video copy completed ==="

# 列出复制的文件
echo "Files in Bundle asserts directory:"
ls -la "${BUNDLE_RESOURCES_DIR}/asserts/" 2>/dev/null || echo "  (directory listing failed)"
