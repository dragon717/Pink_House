# 图片去水印工具指南 (Remove Watermark Guide)

本文档总结了去除图片左上角水印的技术方案、最佳实践及脚本使用说明。

## 1. 需求背景

需要批量去除图片左上角的“AI生成”字样水印。

*   **挑战**: 
    1.  水印位于图片左上角边缘，直接使用 `ffmpeg delogo` 滤镜会报错 `Logo area is outside of the frame`。
    2.  水印大小不固定，需要灵活调整去除范围。

## 2. 技术方案

我们使用 Python 调用 **FFmpeg** 的高级滤镜链来解决此问题。

### 核心原理

为了解决边缘水印报错的问题，采用了 **Padding + Fillborders + Delogo + Crop** 的组合策略：

1.  **Pad (填充)**: 
    *   在图片四周增加黑色边框（Padding），使原图的左上角不再是整个画布的边缘。
    *   例如：增加 10px 的边框，原 `(0,0)` 坐标变为 `(10,10)`。
2.  **Fillborders (镜像填充)**:
    *   将刚刚增加的黑色 Padding 区域，用原图边缘的像素进行**镜像 (Mirror)** 填充。
    *   **目的**: `delogo` 算法依赖周围像素进行插值修复，黑色边框会导致修复区域边缘发黑，使用镜像像素能提供自然的过渡素材。
3.  **Delogo (去水印)**:
    *   对指定区域应用去水印算法。此时坐标需要加上 Padding 的偏移量。
4.  **Crop (剪裁)**:
    *   处理完成后，将 Padding 剪裁掉，恢复原图尺寸。

### 滤镜链命令示例

```bash
ffmpeg -i input.png -vf "pad=iw+20:ih+20:10:10,fillborders=left=10:top=10:right=10:bottom=10:mode=mirror,delogo=x=10:y=10:w=200:h=60,crop=iw-20:ih-20:10:10" output.png
```

## 3. 脚本使用说明

脚本位置: `scripts/remove_image_watermark.py`

### 基本用法

```bash
# 处理单个文件
python3 scripts/remove_image_watermark.py image.png

# 处理多个文件
python3 scripts/remove_image_watermark.py img1.png img2.png
```

### 常用参数

*   `--preset [1-6]`: 使用预设的去除范围配置（推荐）。
    *   `1`: 小范围 (200x60) - 紧贴左上角
    *   `2`: 常规范围 (240x80) - 默认，有轻微偏移
    *   `3`: 大范围 (400x150)
    *   `4`: 巨大范围 (450x300) - 针对大面积水印
    *   `5`: 超大范围 (600x400)
    *   `6`: 极巨范围 (800x600)
*   `--debug`: **调试模式**。不去除水印，而是在目标区域画一个**绿框**，用于确认位置是否正确。
*   `--auto-test`: 自动生成所有预设版本的测试图（v1-v6），方便对比效果。

### 自定义区域

如果预设都不满足需求，可以手动指定坐标和大小：

```bash
python3 scripts/remove_image_watermark.py image.png --x 0 --y 0 --width 300 --height 100
```

## 4. 最佳实践 (Best Practices)

### A. 如何确定水印范围？

1.  **使用 Debug 模式**:
    不要盲目尝试，先运行 debug 模式生成带绿框的图片：
    ```bash
    python3 scripts/remove_image_watermark.py test.png --debug --preset 4
    ```
2.  **观察绿框**:
    打开生成的图片，检查绿框是否完全覆盖了水印文字。
    *   如果没覆盖全：增大 `width`/`height` 或调整预设。
    *   如果框太大：减小范围，避免破坏无关画面。

### B. 效果权衡

*   **原则**: 去除范围越小越好。
*   `delogo` 本质是利用周围像素进行模糊插值，范围越大，画面模糊/扭曲感越强。
*   对于复杂背景（如人脸、文字细节），大范围去水印可能会产生明显的“马赛克”或“涂抹”痕迹。

### C. 批量处理建议

1.  先拿一张典型图片，使用 `--auto-test` 生成多个版本。
2.  挑选效果最好且范围最小的一个预设（例如 v4）。
3.  使用该预设批量处理剩余图片：
    ```bash
    python3 scripts/remove_image_watermark.py *.png --preset 4
    ```

## 5. 故障排查

*   **报错 `Logo area is outside of the frame`**:
    *   这是因为 `x + width` 或 `y + height` 超出了图片边界。
    *   本脚本已通过 Padding 方案解决此问题。如果手动修改代码，请确保保留 Padding 逻辑。
*   **去水印处有黑边**:
    *   检查 `fillborders` 滤镜是否生效。如果只 Pad 黑色而不做镜像填充，边缘就会发黑。
