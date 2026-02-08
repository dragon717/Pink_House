#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
批量去除视频右下角水印脚本
作者: Trae AI
日期: 2026-02-08

使用说明:
1. 确保已安装 ffmpeg:
   - macOS: brew install ffmpeg
   - Windows: 下载 ffmpeg 并添加到环境变量
2. 运行脚本:
   python3 remove_watermark.py [文件夹路径]

默认处理 ../asserts 目录下的 mp4 文件
"""

import os
import sys
import subprocess
import json
import shutil

# --- 配置区域 (可根据实际情况调整) ---
# 水印大概尺寸 (根据"小云雀AI生成"文字预估)
WATERMARK_WIDTH = 240   # 预估宽度，稍微大一点以覆盖
WATERMARK_HEIGHT = 80   # 预估高度
# 水印距离右下角的边距
MARGIN_RIGHT = 10
MARGIN_BOTTOM = 10
# -----------------------------------

def check_ffmpeg():
    """检查 ffmpeg 是否安装"""
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        print("错误: 未找到 ffmpeg 或 ffprobe。")
        print("请先安装 ffmpeg。macOS 用户可以使用: brew install ffmpeg")
        return False
    return True

def get_video_info(file_path):
    """获取视频的分辨率信息"""
    cmd = [
        "ffprobe",
        "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        file_path
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        for stream in data.get("streams", []):
            if stream.get("codec_type") == "video":
                return stream
    except subprocess.CalledProcessError as e:
        print(f"无法读取文件信息 {file_path}: {e}")
    except Exception as e:
        print(f"发生错误 {file_path}: {e}")
    return None

def process_file(file_path):
    """处理单个文件"""
    print(f"\n正在处理: {file_path}")
    
    info = get_video_info(file_path)
    if not info:
        print("跳过: 无法获取视频信息")
        return

    try:
        width = int(info.get("width"))
        height = int(info.get("height"))
    except (ValueError, TypeError):
        print("跳过: 无法解析分辨率")
        return

    # 计算 delogo 区域坐标
    # x = 总宽 - 水印宽 - 右边距
    # y = 总高 - 水印高 - 下边距
    x = width - WATERMARK_WIDTH - MARGIN_RIGHT
    y = height - WATERMARK_HEIGHT - MARGIN_BOTTOM
    
    # 边界检查
    x = max(0, x)
    y = max(0, y)
    
    # 输出文件路径
    dirname = os.path.dirname(file_path)
    filename = os.path.basename(file_path)
    name, ext = os.path.splitext(filename)
    output_path = os.path.join(dirname, f"{name}_clean{ext}")
    
    print(f"视频分辨率: {width}x{height}")
    print(f"去除水印区域: x={x}, y={y}, w={WATERMARK_WIDTH}, h={WATERMARK_HEIGHT}")
    
    # 构建 ffmpeg 命令
    # delogo 滤镜文档: https://ffmpeg.org/ffmpeg-filters.html#delogo
    # show=0: 不在去除区域显示边框 (默认0)
    cmd = [
        "ffmpeg",
        "-y", # 覆盖输出文件
        "-i", file_path,
        "-vf", f"delogo=x={x}:y={y}:w={WATERMARK_WIDTH}:h={WATERMARK_HEIGHT}:show=0",
        "-c:a", "copy", # 音频流直接复制，不重新编码
        output_path
    ]
    
    try:
        # 运行 ffmpeg，显示进度
        subprocess.run(cmd, check=True)
        print(f"成功: 已生成 {output_path}")
    except subprocess.CalledProcessError:
        print("失败: ffmpeg 处理出错")

def main():
    if not check_ffmpeg():
        sys.exit(1)
        
    # 确定要处理的目标
    if len(sys.argv) > 1:
        target_path = sys.argv[1]
    else:
        # 默认为脚本上一级目录下的 asserts
        script_dir = os.path.dirname(os.path.abspath(__file__))
        target_path = os.path.join(os.path.dirname(script_dir), "asserts")
    
    target_path = os.path.abspath(target_path)
    
    if not os.path.exists(target_path):
        print(f"错误: 路径不存在 {target_path}")
        sys.exit(1)

    if os.path.isfile(target_path):
        # 如果是单个文件
        if target_path.lower().endswith(".mp4"):
            process_file(target_path)
        else:
            print("错误: 指定的文件不是 mp4 格式")
    else:
        # 如果是目录
        print(f"开始扫描目录: {target_path}")
        count = 0
        for root, dirs, files in os.walk(target_path):
            for file in files:
                if file.lower().endswith(".mp4") and "_clean" not in file:
                    file_path = os.path.join(root, file)
                    process_file(file_path)
                    count += 1
                    
        if count == 0:
            print("未找到需要处理的 mp4 文件 (排除已包含 _clean 的文件)")
        else:
            print(f"\n全部完成，共处理 {count} 个文件。")

if __name__ == "__main__":
    main()
