# 视频去水印工具说明

本文档介绍了如何使用 `ItemManager/scripts/remove_watermark.py` 脚本来批量去除视频右下角的水印（针对 "小云雀AI生成" 等固定位置水印）。

## 1. 依赖安装

本脚本依赖 `ffmpeg` 进行视频处理。在运行之前，请确保你的系统已安装 `ffmpeg`。

### macOS

推荐使用 Homebrew 安装：

```bash
brew install ffmpeg
```

> 如果遇到权限问题，请根据 Homebrew 的提示修复权限（通常涉及 `sudo chown ...`），然后再尝试安装。

## 2. 脚本功能

*   **自动分辨率适配**：自动读取视频分辨率，根据右下角定位水印位置。
*   **批量处理**：支持一次性处理整个文件夹中的所有 `.mp4` 文件。
*   **单文件处理**：支持指定处理单个视频文件。
*   **无损音频**：视频重新编码（去除水印），音频流直接复制，保证音质不变。
*   **安全输出**：生成的文件会自动添加 `_clean` 后缀（例如 `video.mp4` -> `video_clean.mp4`），不会覆盖原文件。

## 3. 使用方法

### 运行环境

请在终端（Terminal）中运行脚本。

### 基本命令

```bash
# 进入项目根目录
cd /path/to/Pink_House

# 运行脚本
python3 ItemManager/scripts/remove_watermark.py [目标路径]
```

### 场景示例

**场景 A：处理单个视频**

如果你只想处理某一个特定的视频文件：

```bash
python3 ItemManager/scripts/remove_watermark.py "/Users/username/path/to/video.mp4"
```

**场景 B：批量处理文件夹**

如果你想处理 `asserts` 目录下的所有视频：

```bash
python3 ItemManager/scripts/remove_watermark.py "/Users/username/path/to/asserts_folder"
```

**场景 C：默认行为**

如果不带参数直接运行脚本，默认会尝试寻找脚本上一级目录的同级 `asserts` 目录（即 `ItemManager/asserts`）进行处理。

```bash
python3 ItemManager/scripts/remove_watermark.py
```

## 4. 参数配置

如果水印位置或大小发生变化，你可以直接编辑 `remove_watermark.py` 文件开头的配置区域：

```python
# --- 配置区域 (可根据实际情况调整) ---
# 水印大概尺寸 (根据"小云雀AI生成"文字预估)
WATERMARK_WIDTH = 240   # 宽度
WATERMARK_HEIGHT = 80   # 高度
# 水印距离右下角的边距
MARGIN_RIGHT = 10
MARGIN_BOTTOM = 10
# -----------------------------------
```

## 5. 常见问题

*   **找不到 ffmpeg**: 请确认已安装并在终端能直接运行 `ffmpeg -version`。
*   **Permission denied**: 确保你有读取源文件和写入目标文件夹的权限。
*   **去不干净/去多了**: 请根据实际视频的分辨率和水印大小，微调脚本中的 `WATERMARK_WIDTH`, `WATERMARK_HEIGHT` 以及边距参数。
