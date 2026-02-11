#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
批量去除视频水印脚本 (支持右下角/左上角)
作者: Trae AI
日期: 2026-02-11

使用说明:
1. 确保已安装 ffmpeg:
   - macOS: brew install ffmpeg
   - Windows: 下载 ffmpeg 并添加到环境变量
2. 运行脚本:
   python3 remove_watermark.py [文件夹路径或文件路径] [--position bottom_right|top_left]
"""

import os
import sys
import subprocess
import json
import shutil
import argparse

# --- 配置区域 (可根据实际情况调整) ---
# 水印大概尺寸
DEFAULT_WIDTH = 240   
DEFAULT_HEIGHT = 80   
# 水印距离边距
DEFAULT_MARGIN = 10
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

def process_file(file_path, position="bottom_right", width_val=DEFAULT_WIDTH, height_val=DEFAULT_HEIGHT, margin=DEFAULT_MARGIN):
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
    x = 0
    y = 0
    
    if position == "bottom_right":
        # x = 总宽 - 水印宽 - 右边距
        # y = 总高 - 水印高 - 下边距
        x = width - width_val - margin
        y = height - height_val - margin
    elif position == "top_left":
        # x = 左边距
        # y = 上边距
        x = margin
        y = margin
    else:
        print(f"未知位置: {position}")
        return
    
    # 边界检查
    x = max(0, x)
    y = max(0, y)
    
    # 输出文件路径
    dirname = os.path.dirname(file_path)
    filename = os.path.basename(file_path)
    name, ext = os.path.splitext(filename)
    output_path = os.path.join(dirname, f"{name}_clean{ext}")
    
    print(f"视频分辨率: {width}x{height}")
    print(f"去除水印区域 ({position}): x={x}, y={y}, w={width_val}, h={height_val}")
    
    # 构建 ffmpeg 命令
    # delogo 滤镜文档: https://ffmpeg.org/ffmpeg-filters.html#delogo
    # show=0: 不在去除区域显示边框 (默认0)
    cmd = [
        "ffmpeg",
        "-y", # 覆盖输出文件
        "-i", file_path,
        "-vf", f"delogo=x={x}:y={y}:w={width_val}:h={height_val}:show=0",
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
        
    parser = argparse.ArgumentParser(description="批量去除视频水印脚本")
    parser.add_argument("path", nargs="?", help="要处理的文件或目录路径")
    parser.add_argument("--position", choices=["bottom_right", "top_left"], default="bottom_right", help="水印位置 (默认: bottom_right)")
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH, help=f"水印宽度 (默认: {DEFAULT_WIDTH})")
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT, help=f"水印高度 (默认: {DEFAULT_HEIGHT})")
    parser.add_argument("--margin", type=int, default=DEFAULT_MARGIN, help=f"边距 (默认: {DEFAULT_MARGIN})")
    
    args = parser.parse_args()
    
    # 确定要处理的目标
    target_path = args.path
    if not target_path:
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
            process_file(target_path, args.position, args.width, args.height, args.margin)
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
                    process_file(file_path, args.position, args.width, args.height, args.margin)
                    count += 1
                    
        if count == 0:
            print("未找到需要处理的 mp4 文件 (排除已包含 _clean 的文件)")
        else:
            print(f"\n全部完成，共处理 {count} 个文件。")

if __name__ == "__main__":
    main()
