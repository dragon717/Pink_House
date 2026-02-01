import torch
import coremltools as ct
from transformers import AutoModelForImageSegmentation
from mobile_sam import sam_model_registry, SamPredictor
import numpy as np
import os
import urllib.request

def convert_rmbg():
    print("🚀 Starting RMBG-1.4 Conversion...")
    
    # 1. Load Model from Hugging Face
    model_id = "briaai/RMBG-1.4"
    print(f"Loading model: {model_id}")
    try:
        model = AutoModelForImageSegmentation.from_pretrained(model_id, trust_remote_code=True)
        model.eval()
    except Exception as e:
        print(f"Error loading RMBG model: {e}")
        return

    # 2. Trace Model
    print("Tracing model...")
    example_input = torch.rand(1, 3, 1024, 1024)
    traced_model = torch.jit.trace(model, example_input)

    # 3. Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="input", shape=example_input.shape)], # We will handle image preprocessing in Swift for flexibility or add ImageType here
        outputs=[ct.TensorType(name="output")],
        minimum_deployment_target=ct.target.iOS17 # Vision features
    )

    # 4. Save
    output_path = "RMBG14.mlpackage"
    mlmodel.save(output_path)
    print(f"✅ RMBG-1.4 saved to {output_path}")

def convert_mobilesam():
    print("\n🚀 Starting MobileSAM Conversion...")
    
    # 1. Download Weights
    weights_path = "mobile_sam.pt"
    if not os.path.exists(weights_path):
        print("Downloading MobileSAM weights...")
        url = "https://github.com/ChaoningZhang/MobileSAM/raw/master/weights/mobile_sam.pt"
        urllib.request.urlretrieve(url, weights_path)

    # 2. Load Model
    model_type = "vit_t"
    sam = sam_model_registry[model_type](checkpoint=weights_path)
    sam.eval()
    
    # --- Convert Encoder ---
    print("Converting Image Encoder...")
    encoder = sam.image_encoder
    example_input_image = torch.rand(1, 3, 1024, 1024)
    traced_encoder = torch.jit.trace(encoder, example_input_image)
    
    mlmodel_encoder = ct.convert(
        traced_encoder,
        inputs=[ct.ImageType(name="image", shape=example_input_image.shape, scale=1/255.0)],
        outputs=[ct.TensorType(name="image_embeddings")],
        minimum_deployment_target=ct.target.iOS17
    )
    mlmodel_encoder.save("MobileSAM_Encoder.mlpackage")
    print("✅ MobileSAM Encoder saved.")

    # --- Convert Decoder ---
    print("Converting Mask Decoder...")
    # MobileSAM/SAM decoder is complex. We usually wrap it to simplify inputs.
    class MobileSAMDecoderWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model.prompt_encoder
            self.decoder = model.mask_decoder

        def forward(self, image_embeddings, point_coords, point_labels):
            sparse_embeddings, dense_embeddings = self.model(
                points=(point_coords, point_labels),
                boxes=None,
                masks=None,
            )
            low_res_masks, iou_predictions = self.decoder(
                image_embeddings=image_embeddings,
                image_pe=self.model.get_dense_pe(),
                sparse_prompt_embeddings=sparse_embeddings,
                dense_prompt_embeddings=dense_embeddings,
                multimask_output=False, # We usually want the best mask
            )
            return low_res_masks, iou_predictions

    decoder_wrapper = MobileSAMDecoderWrapper(sam)
    decoder_wrapper.eval()

    # Create dummy inputs for tracing
    # Embeddings from encoder: (1, 256, 64, 64)
    image_embeddings = torch.randn(1, 256, 64, 64) 
    # Points: (Batch, N_points, 2). Let's support up to 5 points.
    point_coords = torch.randint(0, 1024, (1, 5, 2)).float()
    # Labels: (Batch, N_points)
    point_labels = torch.randint(0, 4, (1, 5)).float()

    traced_decoder = torch.jit.trace(decoder_wrapper, (image_embeddings, point_coords, point_labels))
    
    mlmodel_decoder = ct.convert(
        traced_decoder,
        inputs=[
            ct.TensorType(name="image_embeddings", shape=image_embeddings.shape),
            ct.TensorType(name="point_coords", shape=point_coords.shape),
            ct.TensorType(name="point_labels", shape=point_labels.shape)
        ],
        outputs=[
            ct.TensorType(name="masks"),
            ct.TensorType(name="iou_predictions")
        ],
        minimum_deployment_target=ct.target.iOS17
    )
    mlmodel_decoder.save("MobileSAM_Decoder.mlpackage")
    print("✅ MobileSAM Decoder saved.")

if __name__ == "__main__":
    print("Note: You need to install requirements first:")
    print("pip install torch coremltools transformers mobile-sam timm")
    
    convert_rmbg()
    convert_mobilesam()
