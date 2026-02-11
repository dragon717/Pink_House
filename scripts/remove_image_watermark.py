#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
图片水印去除脚本 (基于 ffmpeg delogo)
功能: 去除图片指定位置(默认左上角)的水印
作者: Trae AI
日期: 2026-02-12

说明:
使用了 padding + fillborders + delogo + crop 的组合滤镜，
以解决 delogo 无法处理边缘水印(Logo area is outside of the frame)的问题。

更新 v2:
- 增加 --debug 参数，会在输出图片上画出 delogo 区域的绿色边框，方便确认位置
- 增加 --preset 参数，提供预设的几种水印位置/大小
"""

import os
import sys
import subprocess
import argparse
import shutil

# 默认水印区域配置 (左上角)
# 根据用户反馈"AI生成"几个字，通常比较小，且可能有边距
# Preset 1: 紧贴左上角，较小
PRESET_1 = {"x": 0, "y": 0, "w": 200, "h": 60}
# Preset 2: 左上角有偏移，常规大小 (默认)
PRESET_2 = {"x": 10, "y": 10, "w": 240, "h": 80}
# Preset 3: 左上角大范围覆盖
PRESET_3 = {"x": 0, "y": 0, "w": 400, "h": 150}

# Preset 4: 巨大范围 (v3 基础上高度增加)
PRESET_4 = {"x": 0, "y": 0, "w": 450, "h": 300}

# Preset 5: 超大范围
PRESET_5 = {"x": 0, "y": 0, "w": 600, "h": 400}

# Preset 6: 覆盖左上角 1/4 区域
PRESET_6 = {"x": 0, "y": 0, "w": 800, "h": 600}

DEFAULT_PAD = 10

def check_ffmpeg():
    if shutil.which("ffmpeg") is None:
        print("错误: 未找到 ffmpeg，请先安装。")
        return False
    return True

def process_image(file_path, x, y, w, h, show_border=False, output_dir=None, suffix="_clean"):
    if not os.path.exists(file_path):
        print(f"文件不存在: {file_path}")
        return

    dirname = os.path.dirname(file_path)
    filename = os.path.basename(file_path)
    name, ext = os.path.splitext(filename)
    
    if output_dir:
        out_dir = output_dir
    else:
        out_dir = dirname
        
    output_path = os.path.join(out_dir, f"{name}{suffix}{ext}")
    
    print(f"正在处理: {filename}")
    print(f"去除区域: x={x}, y={y}, w={w}, h={h}, debug={show_border}")

    # 构建复杂滤镜链
    # 1. pad: 四周增加 padding，用黑色填充 (避免 delogo 边缘报错)
    # 2. fillborders: 将 padding 区域用镜像像素填充 (提供更好的 delogo 插值来源)
    # 3. delogo: 去除水印 (坐标需要加上 padding 偏移)
    # 4. crop: 剪裁掉 padding，恢复原图尺寸
    
    pad = DEFAULT_PAD
    # pad=iw+2*pad:ih+2*pad:pad:pad
    pad_filter = f"pad=iw+{2*pad}:ih+{2*pad}:{pad}:{pad}"
    
    # fillborders=left=pad:top=pad:right=pad:bottom=pad:mode=mirror
    fill_filter = f"fillborders=left={pad}:top={pad}:right={pad}:bottom={pad}:mode=mirror"
    
    # delogo x/y need to be shifted by pad
    delogo_x = x + pad
    delogo_y = y + pad
    
    show_val = 1 if show_border else 0
    delogo_filter = f"delogo=x={delogo_x}:y={delogo_y}:w={w}:h={h}:show={show_val}"
    
    # crop=iw-2*pad:ih-2*pad:pad:pad
    crop_filter = f"crop=iw-{2*pad}:ih-{2*pad}:{pad}:{pad}"
    
    vf_arg = f"{pad_filter},{fill_filter},{delogo_filter},{crop_filter}"
    
    cmd = [
        "ffmpeg",
        "-y",
        "-i", file_path,
        "-vf", vf_arg,
        "-update", "1", # 针对单张图片输出优化
        "-frames:v", "1",
        output_path
    ]
    
    try:
        # 运行 ffmpeg
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        print(f"成功: {output_path}")
    except subprocess.CalledProcessError as e:
        print(f"失败: {filename}")
        # 尝试打印错误信息
        if e.stderr:
            try:
                print(e.stderr.decode())
            except:
                print(e.stderr)

def main():
    parser = argparse.ArgumentParser(description="去除图片左上角水印")
    parser.add_argument("files", nargs="+", help="图片文件路径")
    parser.add_argument("--x", type=int, default=None, help="水印起始 X 坐标")
    parser.add_argument("--y", type=int, default=None, help="水印起始 Y 坐标")
    parser.add_argument("--width", type=int, default=None, help="水印宽度")
    parser.add_argument("--height", type=int, default=None, help="水印高度")
    parser.add_argument("--debug", action="store_true", help="是否显示绿框(调试用)")
    parser.add_argument("--preset", type=int, choices=[1, 2, 3, 4, 5, 6], default=2, help="预设配置: 1=小, 2=常规, 3=大, 4=巨大(高), 5=超大, 6=极巨")
    parser.add_argument("--auto-test", action="store_true", help="自动生成6个版本的测试图")
    
    args = parser.parse_args()
    
    if not check_ffmpeg():
        sys.exit(1)

    # 确定参数
    x, y, w, h = 0, 0, 0, 0
    
    # 如果指定了具体参数，优先使用
    if args.x is not None:
        x = args.x
        y = args.y if args.y is not None else 0
        w = args.width if args.width is not None else 200
        h = args.height if args.height is not None else 60
    else:
        # 使用预设
        preset_map = {
            1: PRESET_1, 2: PRESET_2, 3: PRESET_3,
            4: PRESET_4, 5: PRESET_5, 6: PRESET_6
        }
        preset = preset_map.get(args.preset, PRESET_2)
        
        x, y, w, h = preset["x"], preset["y"], preset["w"], preset["h"]

    for f in args.files:
        if args.auto_test:
            print(f"--- 正在为 {f} 生成多版本测试图 ---")
            # V1
            process_image(f, PRESET_1["x"], PRESET_1["y"], PRESET_1["w"], PRESET_1["h"], args.debug, suffix="_v1")
            # V2
            process_image(f, PRESET_2["x"], PRESET_2["y"], PRESET_2["w"], PRESET_2["h"], args.debug, suffix="_v2")
            # V3
            process_image(f, PRESET_3["x"], PRESET_3["y"], PRESET_3["w"], PRESET_3["h"], args.debug, suffix="_v3")
            # V4
            process_image(f, PRESET_4["x"], PRESET_4["y"], PRESET_4["w"], PRESET_4["h"], args.debug, suffix="_v4")
            # V5
            process_image(f, PRESET_5["x"], PRESET_5["y"], PRESET_5["w"], PRESET_5["h"], args.debug, suffix="_v5")
            # V6
            process_image(f, PRESET_6["x"], PRESET_6["y"], PRESET_6["w"], PRESET_6["h"], args.debug, suffix="_v6")
        else:
            process_image(f, x, y, w, h, args.debug)

if __name__ == "__main__":
    main()
