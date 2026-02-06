import coremltools as ct
from coremltools.optimize.coreml import linear_quantize_weights, OpLinearQuantizerConfig, OptimizationConfig
import os
import shutil

def quantize_model(input_path, output_path):
    print(f"🚀 Starting quantization for {input_path}...")
    print(f"CoreML Tools Version: {ct.__version__}")
    
    if not os.path.exists(input_path):
        print(f"❌ Input model not found: {input_path}")
        return False

    try:
        # Load the model
        print("Loading CoreML model...")
        model = ct.models.MLModel(input_path)
        
        # Configure quantization
        print("Applying 8-bit linear quantization...")
        
        # Try wrapping in OptimizationConfig first (Fix for 'global_config' error)
        try:
            op_config = OpLinearQuantizerConfig(
                mode="linear_symmetric",
                weight_threshold=512
            )
            config = OptimizationConfig(global_config=op_config)
            compressed_model = linear_quantize_weights(model, config=config)
        except Exception as e:
            print(f"⚠️ First attempt failed: {e}")
            print("Retrying with direct config...")
            # Fallback to direct config if wrapper fails (for different versions)
            op_config = OpLinearQuantizerConfig(
                mode="linear_symmetric",
                weight_threshold=512
            )
            compressed_model = linear_quantize_weights(model, config=op_config)
        
        # Save
        print(f"Saving quantized model to {output_path}...")
        compressed_model.save(output_path)
        
        # Compare sizes
        orig_size = get_size(input_path)
        new_size = get_size(output_path)
        print(f"✅ Quantization complete!")
        print(f"   Original Size: {orig_size:.2f} MB")
        print(f"   New Size:      {new_size:.2f} MB")
        print(f"   Reduction:     {(1 - new_size/orig_size)*100:.1f}%")
        
        return True
    except Exception as e:
        print(f"❌ Quantization failed: {e}")
        return False

def get_size(path):
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            total_size += os.path.getsize(fp)
    return total_size / (1024 * 1024)

if __name__ == "__main__":
    # Path to the existing large model
    input_model = "ItemManager/Services/ML/SharpModel.mlpackage"
    # Temporary output path
    output_model = "ItemManager/Services/ML/SharpModel_Quantized.mlpackage"
    
    if quantize_model(input_model, output_model):
        print("✨ Do you want to replace the original model with the quantized one? (y/n)")
        # In automation, we assume yes if successful
        print("Automation: Replacing original model...")
        
        backup_path = input_model + ".bak"
        if os.path.exists(backup_path):
            shutil.rmtree(backup_path)
        os.rename(input_model, backup_path)
        os.rename(output_model, input_model)
        print(f"Original model backed up to {backup_path}")
        print(f"Quantized model installed at {input_model}")
