#!/bin/bash

# 清理 Archive 中的重复文件
# 用法: ./clean_archive.sh [xcarchive路径]

if [ -z "$1" ]; then
    # 自动查找最新的 Archive
    ARCHIVE_PATH=$(find ~/Library/Developer/Xcode/Archives -name "*.xcarchive" -type d | sort -t'/' -k7,7 -k8,8 -k9,9 | tail -1)
else
    ARCHIVE_PATH="$1"
fi

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "错误: 找不到 Archive 路径: $ARCHIVE_PATH"
    exit 1
fi

echo "正在清理 Archive: $ARCHIVE_PATH"

# 找到 App Bundle
APP_BUNDLE=$(find "$ARCHIVE_PATH" -name "*.app" -type d | head -1)

if [ ! -d "$APP_BUNDLE" ]; then
    echo "错误: 找不到 App Bundle"
    exit 1
fi

echo "App Bundle: $APP_BUNDLE"
echo ""

# 计算清理前的大小
SIZE_BEFORE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "清理前大小: $SIZE_BEFORE"
echo ""

# 1. 删除 asserts 2.zip (备份文件)
if [ -f "$APP_BUNDLE/asserts 2.zip" ]; then
    echo "删除: asserts 2.zip"
    rm -f "$APP_BUNDLE/asserts 2.zip"
fi

# 2. 删除根目录中重复的 .mov 文件（这些应该在 asserts 文件夹中）
echo "删除根目录中重复的 .mov 文件..."
find "$APP_BUNDLE" -maxdepth 1 -name "*.mov" -type f -delete

# 3. 删除根目录中重复的 .mp4 文件
echo "删除根目录中重复的 .mp4 文件..."
find "$APP_BUNDLE" -maxdepth 1 -name "*.mp4" -type f -delete

# 4. 删除根目录中重复的字体文件
echo "删除根目录中重复的 .ttf 文件..."
find "$APP_BUNDLE" -maxdepth 1 -name "*.ttf" -type f -delete

# 5. 删除根目录中重复的音频文件
echo "删除根目录中重复的 .mp3 文件..."
find "$APP_BUNDLE" -maxdepth 1 -name "*.mp3" -type f -delete

# 6. 删除根目录中的 .md 文档文件
echo "删除根目录中的 .md 文档文件..."
find "$APP_BUNDLE" -maxdepth 1 -name "*.md" -type f -delete

# 7. 删除其他不需要的文件
rm -f "$APP_BUNDLE/GenerativeAI-Info.bak.plist"
rm -f "$APP_BUNDLE/README.md"

echo ""
# 计算清理后的大小
SIZE_AFTER=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "清理后大小: $SIZE_AFTER"
echo ""
echo "✅ 清理完成！"
