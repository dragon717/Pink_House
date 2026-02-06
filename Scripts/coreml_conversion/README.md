# Sharp 模型 CoreML 转换指南

本目录包含将 Apple `ml-sharp` PyTorch 模型转换为 iOS 可用的 CoreML 模型 (`.mlpackage`) 的工具脚本。

## 前置条件

1.  你需要一台安装了 Python 环境的 Mac (推荐使用 `conda`)。
2.  你需要克隆 `ml-sharp` 的官方仓库。

## 步骤

### 1. 准备环境

```bash
# 1. 克隆 ml-sharp
git clone https://github.com/apple/ml-sharp.git
cd ml-sharp

# 2. 安装依赖 (参考 ml-sharp 的 README)
pip install -r requirements.txt
pip install coremltools
```

### 2. 配置转换脚本

将本目录下的 `convert_sharp.py` 复制到 `ml-sharp` 仓库的根目录下。

```bash
cp /path/to/Pink_House/Scripts/coreml_conversion/convert_sharp.py .
```

### 3. 运行转换

```bash
# 运行脚本
python convert_sharp.py --checkpoint /path/to/sharp_checkpoint.pth --output SharpModel.mlpackage
```

如果一切顺利，你将得到一个 `SharpModel.mlpackage` 文件。

### 4. 集成到 iOS 项目

将生成的 `SharpModel.mlpackage` 拖入 Xcode 项目的 `ItemManager/Services/ML/` 目录下，并确保 Target Membership 勾选了 `ItemManager`。

## 常见问题

*   **模型结构不匹配**：如果 `convert_sharp.py` 报错提示模型定义找不到，请检查 `from sharp.modeling.arch import ...` 这一行是否与 `ml-sharp` 实际的代码结构一致。你需要根据 `ml-sharp` 的最新代码调整导入路径。
*   **输入尺寸**：默认脚本假设输入为 512x512。如果模型需要其他尺寸，请修改脚本中的 `dummy_input` 形状。
*   **Ops 兼容性**：如果遇到 CoreML 不支持的 PyTorch 算子，尝试在 `ct.convert` 中启用 `ct.ComputeUnit.CPU_ONLY` 进行调试，或者修改 PyTorch 源码中的实现（例如将 `F.grid_sample` 替换为等价实现）。
