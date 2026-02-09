import os
import sys
import subprocess
import argparse

def check_ffmpeg():
    """检查 ffmpeg 是否已安装"""
    try:
        subprocess.run(["ffmpeg", "-version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def separate_av(input_path):
    if not os.path.exists(input_path):
        print(f"❌ 错误：文件不存在 - {input_path}")
        return

    # 路径处理
    directory = os.path.dirname(input_path)
    filename = os.path.basename(input_path)
    name, ext = os.path.splitext(filename)
    
    output_video = os.path.join(directory, f"{name}_video{ext}")
    output_audio = os.path.join(directory, f"{name}_audio.m4a") 
    
    print(f"🎬 开始处理: {filename}")
    
    # 1. 提取无声视频 (流复制，极快)
    print("📹 正在提取无声视频...")
    cmd_video = [
        "ffmpeg", "-y", "-i", input_path,
        "-c:v", "copy", "-an",
        output_video
    ]
    try:
        subprocess.run(cmd_video, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        print(f"✅ 无声视频已保存: {os.path.basename(output_video)}")
    except subprocess.CalledProcessError as e:
        print(f"❌ 视频提取失败: {e}")
    
    # 2. 提取音频 (转码为 AAC 以确保兼容性)
    print("🎵 正在提取音频...")
    cmd_audio = [
        "ffmpeg", "-y", "-i", input_path,
        "-vn", "-c:a", "aac",
        output_audio
    ]
    
    try:
        subprocess.run(cmd_audio, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        print(f"✅ 音频已保存: {os.path.basename(output_audio)}")
    except subprocess.CalledProcessError as e:
        print(f"❌ 音频提取失败: {e}")
        
    print("✨ 所有任务完成！")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使用方法: python3 separate_av.py <video_file_path>")
        sys.exit(1)
        
    if not check_ffmpeg():
        print("❌ 错误：未找到 ffmpeg。请先安装 ffmpeg (brew install ffmpeg)")
        sys.exit(1)
        
    separate_av(sys.argv[1])
