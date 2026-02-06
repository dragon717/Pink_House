import coremltools as ct
from coremltools.optimize.coreml import palettize_weights, OpPalettizerConfig, OptimizationConfig
import os
import shutil

def quantize_model_4bit(input_path, output_path):
    print(f"🚀 Starting 4-bit Palettization for {input_path}...")
    
    if not os.path.exists(input_path):
        print(f"❌ Input model not found: {input_path}")
        return False

    try:
        # Load the model
        print("Loading CoreML model...")
        model = ct.models.MLModel(input_path)
        
        # Configure quantization
        print("Applying 4-bit KMeans palettization...")
        
        # Use kmeans for better accuracy at low bits
        op_config = OpPalettizerConfig(
            mode="kmeans",
            nbits=4,
            weight_threshold=512
        )
        config = OptimizationConfig(global_config=op_config)
        
        compressed_model = palettize_weights(model, config=config)
        
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
    # Use the backup (original Float16) if available, otherwise the current (Int8) one
    original_model = "ItemManager/Services/ML/SharpModel.mlpackage.bak"
    current_model = "ItemManager/Services/ML/SharpModel.mlpackage"
    
    input_model = original_model if os.path.exists(original_model) else current_model
    print(f"Using input model: {input_model}")
    
    # Output path
    output_model = "ItemManager/Services/ML/SharpModel_4bit.mlpackage"
    
    if quantize_model_4bit(input_model, output_model):
        print("✨ Replacing current model with 4-bit quantized version...")
        
        # If we used the backup, we keep it. If we used current, we might want to back it up if not exists.
        if input_model == current_model and not os.path.exists(original_model):
             shutil.copytree(current_model, original_model)
        
        if os.path.exists(current_model):
            shutil.rmtree(current_model)
            
        os.rename(output_model, current_model)
        print(f"4-bit Quantized model installed at {current_model}")
