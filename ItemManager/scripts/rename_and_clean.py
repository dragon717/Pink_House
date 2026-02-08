#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
批量去水印并重命名脚本
功能：
1. 遍历指定目录下的 mp4 文件
2. 根据文件名关键词重命名为简短英文名
3. 去除右下角水印
4. 输出到 processed 子目录
"""

import os
import sys
import subprocess
import shutil
import re
import json

# --- 去水印配置 (复用 remove_watermark.py 的配置) ---
WATERMARK_WIDTH = 240
WATERMARK_HEIGHT = 80
MARGIN_RIGHT = 10
MARGIN_BOTTOM = 10
# ------------------------------------------------

# --- 命名映射规则 ---
KEYWORD_MAPPING = [
    (r"Eating|吃", "eating"),
    (r"Drinking|喝", "drinking"),
    (r"Listening|倾听", "listening"),
    (r"Grooming|洗脸", "grooming"),
    (r"Enjoy|点头部", "enjoy"),
    (r"Angry|点肚子.*Angry", "angry"),
    (r"Rolling|点肚子.*Rolling|翻滚", "rolling"),
    (r"Sleeping|睡觉", "sleeping"),
    (r"浴缸|洗澡", "bathing"),
    (r"玩小球", "playing"),
]

def check_ffmpeg():
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        print("错误: 未找到 ffmpeg 或 ffprobe。请先安装。")
        return False
    return True

def get_video_info(file_path):
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", file_path
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        for stream in data.get("streams", []):
            if stream.get("codec_type") == "video":
                return stream
    except Exception as e:
        print(f"无法读取文件信息 {file_path}: {e}")
    return None

def get_new_name(filename, counts):
    base_name = "video" # 默认名
    
    # 尝试匹配关键词
    for pattern, name in KEYWORD_MAPPING:
        if re.search(pattern, filename, re.IGNORECASE):
            base_name = name
            break
    
    # 处理计数
    if base_name not in counts:
        counts[base_name] = 1
    else:
        counts[base_name] += 1
        
    # 如果是第1个，是否要加序号？为了统一，建议都加，或者只有重复时加
    # 策略：如果有多个同类文件，为了区分，最好都加序号，或者从_01开始
    # 这里简单起见：如果是第1个，暂时不加后缀，如果有第2个，第2个加_2，把第1个重命名为_1（比较麻烦）
    # 简单策略：直接加序号 _01, _02
    
    return f"{base_name}_{counts[base_name]:02d}"

def process_directory(input_dir):
    input_dir = os.path.abspath(input_dir)
    output_dir = os.path.join(input_dir, "processed")
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    print(f"输入目录: {input_dir}")
    print(f"输出目录: {output_dir}")
    
    files = [f for f in os.listdir(input_dir) if f.lower().endswith(".mp4")]
    files.sort() # 排序以保证顺序一致
    
    counts = {}
    
    for filename in files:
        file_path = os.path.join(input_dir, filename)
        
        # 确定新名字
        new_name_base = get_new_name(filename, counts)
        new_filename = f"{new_name_base}.mp4"
        output_path = os.path.join(output_dir, new_filename)
        
        print(f"\n处理: {filename[:30]}... -> {new_filename}")
        
        # 获取分辨率
        info = get_video_info(file_path)
        if not info:
            print("跳过: 无法获取视频信息")
            continue
            
        try:
            width = int(info.get("width"))
            height = int(info.get("height"))
        except:
            print("跳过: 分辨率解析失败")
            continue
            
        # 计算去水印区域
        x = max(0, width - WATERMARK_WIDTH - MARGIN_RIGHT)
        y = max(0, height - WATERMARK_HEIGHT - MARGIN_BOTTOM)
        
        # 执行 ffmpeg
        cmd = [
            "ffmpeg", "-y", "-v", "error",
            "-i", file_path,
            "-vf", f"delogo=x={x}:y={y}:w={WATERMARK_WIDTH}:h={WATERMARK_HEIGHT}:show=0",
            "-c:a", "copy",
            output_path
        ]
        
        try:
            subprocess.run(cmd, check=True)
            print("成功")
        except subprocess.CalledProcessError as e:
            print(f"失败: {e}")

if __name__ == "__main__":
    if not check_ffmpeg():
        sys.exit(1)
        
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    process_directory(target_dir)
