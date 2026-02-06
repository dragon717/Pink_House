import torch
import coremltools as ct
import argparse
import sys
import os

# ==========================================
# ⚠️ 注意：请根据 ml-sharp 实际代码结构调整以下导入
# 假设脚本运行在 ml-sharp 仓库根目录
# ==========================================
try:
    # 尝试导入 Sharp 模型定义类
    # 你可能需要查看 ml-sharp 源码找到正确的类名
    # 例如: from sharp.modeling.arch import SharpArchitecture
    from sharp.model import SharpModel as SharpArchitecture 
except ImportError:
    print("❌ Error: Could not import Sharp model definition.")
    print("Please run this script from the root of the ml-sharp repository.")
    print("And ensure you have updated the import statement in this script.")
    sys.exit(1)

def convert(checkpoint_path, output_path, input_size=512):
    print(f"🚀 Starting conversion for {checkpoint_path}...")

    # 1. Load Model
    # 根据 ml-sharp 的加载方式调整
    try:
        model = SharpArchitecture.load_from_checkpoint(checkpoint_path)
        model.eval()
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        # 尝试直接 torch.load
        print("Trying torch.load...")
        model = torch.load(checkpoint_path, map_location="cpu")
        if isinstance(model, dict) and 'state_dict' in model:
             # 如果是 state_dict，你需要先实例化模型结构
             # model = SharpArchitecture(...)
             # model.load_state_dict(model['state_dict'])
             pass
    
    # 2. Prepare Dummy Input for Tracing
    # Sharp 通常接受 (1, 3, H, W) 的输入
    dummy_input = torch.randn(1, 3, input_size, input_size)
    
    print("Running torch.jit.trace...")
    try:
        # 使用 Strict=False 以允许一些 Python 逻辑
        traced_model = torch.jit.trace(model, dummy_input, strict=False)
    except Exception as e:
        print(f"❌ Tracing failed: {e}")
        sys.exit(1)

    print("Converting to Core ML...")
    
    # 3. Convert
    # 定义输入
    image_input = ct.TensorType(
        name="image",
        shape=dummy_input.shape,
        scale=1/255.0, # 如果模型需要 0-1 输入
        bias=[0, 0, 0] # 
    )

    try:
        # 默认转换为 Float16 (CoreML 标准)
        # 如果需要更激进的压缩 (如 8-bit / 4-bit 量化)，可以使用 ct.models.neural_network.quantization_utils 或 ct.compression (iOS 16+)
        
        mlmodel = ct.convert(
            traced_model,
            inputs=[image_input],
            # 建议明确指定输出名称，以便在 Swift 中轻松调用
            outputs=[ct.TensorType(name="splats")], 
            minimum_deployment_target=ct.target.iOS17, # iOS 17+ for best performance
            compute_units=ct.ComputeUnit.ALL, # 使用 ANE
            convert_to="mlprogram", # 使用新格式
            # compute_precision=ct.precision.FLOAT16 # 显式指定 Float16 (通常默认就是)
        )
        
        # 可选：进一步量化权重 (Weight Quantization) 以减小模型体积
        # 需要 coremltools >= 7.0
        # from coremltools.models.neural_network import quantization_utils
        # mlmodel = quantization_utils.quantize_weights(mlmodel, nbits=16) # Float16
        
    except Exception as e:
        print(f"❌ CoreML Conversion failed: {e}")
        sys.exit(1)

    # 4. Save
    mlmodel.save(output_path)
    print(f"✅ Successfully saved model to {output_path}")
    print(f"   Input: {mlmodel.input_description}")
    print(f"   Output: {mlmodel.output_description}")
    
    # 5. Post-conversion Quantization (Optional but Recommended for Large Models)
    print("💡 Tip: Consider quantizing weights if model is too large (>500MB).")
    print("   Example using python:")
    print("   import coremltools as ct")
    print("   from coremltools.optimize.coreml import linear_quantize_weights, OpLinearQuantizerConfig")
    print("   model = ct.models.MLModel('SharpModel.mlpackage')")
    print("   config = OpLinearQuantizerConfig(mode='linear_symmetric', weight_threshold=512)")
    print("   compressed_model = linear_quantize_weights(model, config=config)")
    print("   compressed_model.save('SharpModel_Quantized.mlpackage')")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert ml-sharp PyTorch model to CoreML")
    parser.add_argument("--checkpoint", type=str, required=True, help="Path to .pth or .pt checkpoint")
    parser.add_argument("--output", type=str, default="SharpModel.mlpackage", help="Output path")
    parser.add_argument("--size", type=int, default=512, help="Input image size")
    
    args = parser.parse_args()
    
    convert(args.checkpoint, args.output, args.size)
