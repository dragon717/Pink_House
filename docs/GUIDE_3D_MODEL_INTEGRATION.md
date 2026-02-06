# 3D 模型集成指南

恭喜！iOS 端的 3D 渲染管线（基于 SceneKit）和 UI 交互（无闪烁覆盖层）已经准备就绪。
现在的最后一步是将真实的 AI 模型集成进来，替换掉演示用的彩虹球。

请按照以下步骤操作：

## 第一步：准备转换环境 (Mac 终端)

你需要一台安装了 Python 环境的 Mac。

1.  **下载 `ml-sharp` 代码库** (假设这是目标模型，或者使用其他类似 One-Shot 3DGS 模型)：
    ```bash
    git clone https://github.com/YourTargetModelRepo/ml-sharp.git
    cd ml-sharp
    ```

2.  **安装依赖**:
    确保安装了 `coremltools`：
    ```bash
    pip install coremltools torch
    ```

3.  **复制转换脚本**:
    将本项目中的 `Scripts/coreml_conversion/convert_sharp.py` 复制到 `ml-sharp` 的根目录。

## 第二步：执行模型转换

运行脚本将 PyTorch 模型 (`.pth` / `.ckpt`) 转换为 CoreML 模型 (`.mlpackage`)。

```bash
python convert_sharp.py --checkpoint path/to/your/model.pth --output SharpModel.mlpackage
```

**⚠️ 注意**:
- 脚本中的 `from sharp.model import SharpModel` 可能需要根据实际代码库修改。
- 确保输入尺寸设置为 512 (默认) 或模型训练时的尺寸。

## 第三步：导入 Xcode

1.  找到生成的 `SharpModel.mlpackage` 文件。
2.  将其直接拖入 Xcode 项目的 `ItemManager/Services/ML/` 目录下。
3.  在弹出的对话框中，确保勾选 "Copy items if needed" 和 "Add to targets: ItemManager"。

## 第四步：验证模型接口

1.  在 Xcode 中点击 `SharpModel.mlpackage`。
2.  查看 "Predictions" 标签页。
3.  **输入 (Input)**: 确认是否有名为 `image` 的输入，尺寸为 `512x512`。
4.  **输出 (Output)**: 
    - 记下输出的名字（例如 `var_1234` 或 `points`）。
    - 确认输出的多维数组形状（例如 `(N, 14)` 或 `(14, N)`）。

## 第五步：启用真实推理

打开 `ItemManager/Services/ML/SharpGenerationService.swift`：

1.  找到 `generate` 方法。
2.  取消注释 "Real Inference" 部分的代码。
3.  根据第四步中记下的输出名字，修改代码中的 `output.xxxxx`。
4.  如果在第四步中发现输出格式与代码假设（14通道）不同，请修改 `parseOutput` 方法中的索引逻辑。

```swift
// 示例修改
let output = try model.prediction(image: pixelBuffer)
let splats = try parseOutput(output.splats) // 假设输出名为 'splats'
```

---

完成以上步骤后，再次运行 App，点击“生成 3D 模型”，你将看到真实的衣物 3D 扫描效果！
