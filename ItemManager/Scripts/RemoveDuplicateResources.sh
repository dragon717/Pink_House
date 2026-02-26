#!/bin/bash

# 移除 App Bundle 根目录中重复的视频和字体文件
# 这些文件应该只在 asserts 文件夹中保留一份

APP_BUNDLE="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_FOLDER_PATH}"

if [ -d "$APP_BUNDLE" ]; then
    echo "Removing duplicate resources from App Bundle root..."
    
    # 删除根目录中重复的 .mov 文件（这些文件应该在 asserts 文件夹中）
    find "$APP_BUNDLE" -maxdepth 1 -name "*.mov" -type f -delete
    
    # 删除根目录中重复的 .mp4 文件（这些文件应该在 asserts 文件夹中）
    find "$APP_BUNDLE" -maxdepth 1 -name "*.mp4" -type f -delete
    
    # 删除根目录中重复的字体文件（这些文件应该在 asserts 文件夹中）
    find "$APP_BUNDLE" -maxdepth 1 -name "*.ttf" -type f -delete
    
    # 删除根目录中重复的其他资源文件
    find "$APP_BUNDLE" -maxdepth 1 -name "*.mp3" -type f -delete
    find "$APP_BUNDLE" -maxdepth 1 -name "*.wav" -type f -delete
    
    echo "Duplicate resources removed successfully."
fi
