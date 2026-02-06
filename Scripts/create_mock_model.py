import coremltools as ct
import torch
import torch.nn as nn
import os

# Define a simple Mock model that outputs a fixed sphere of Gaussians
class MockSharpModel(nn.Module):
    def __init__(self, num_points=5000):
        super().__init__()
        self.num_points = num_points
        
        # Pre-calculate a sphere of points
        # Shape: (N, 14)
        # 0-2: Pos, 3-6: Rot, 7-9: Scale, 10-12: Color, 13: Opacity
        self.register_buffer('dummy_output', self._generate_sphere())

    def _generate_sphere(self):
        # Generate random points on a sphere
        N = self.num_points
        
        # Positions
        theta = torch.rand(N) * 2 * 3.14159
        phi = torch.rand(N) * 3.14159
        r = 1.5
        
        x = r * torch.sin(phi) * torch.cos(theta)
        y = r * torch.sin(phi) * torch.sin(theta)
        z = r * torch.cos(phi)
        
        pos = torch.stack([x, y, z], dim=1)
        
        # Rotation (Identity quaternion)
        rot = torch.tensor([0.0, 0.0, 0.0, 1.0]).repeat(N, 1)
        
        # Scale (Small) -> log scale
        # Exp(-3) ~ 0.05
        scale = torch.tensor([-3.0, -3.0, -3.0]).repeat(N, 1)
        
        # Color (Rainbow based on pos)
        # Normalize pos to [0, 1] for color
        r_col = (x / r + 1) * 0.5
        g_col = (y / r + 1) * 0.5
        b_col = (z / r + 1) * 0.5
        # Inverse sigmoid for color (since we apply sigmoid in Swift)
        # logit(p) = log(p / (1-p))
        # safe clamp
        r_col = torch.clamp(r_col, 0.01, 0.99)
        g_col = torch.clamp(g_col, 0.01, 0.99)
        b_col = torch.clamp(b_col, 0.01, 0.99)
        
        color = torch.log(torch.stack([r_col, g_col, b_col], dim=1) / (1 - torch.stack([r_col, g_col, b_col], dim=1)))
        
        # Opacity (High) -> Inverse sigmoid(0.9) ~ 2.2
        opacity = torch.tensor([2.2]).repeat(N, 1)
        
        # Reorder to match Real Model: Pos, Scale, Rot, Color, Opacity
        # Real model: mean(3), scale(3), quat(4), color(3), opacity(1)
        return torch.cat([pos, scale, rot, color, opacity], dim=1) # (N, 14)

    def forward(self, image, disparity_factor):
        # Trick: Make output depend on input to satisfy JIT tracer
        # Multiply by 0 and add to dummy output
        # image is (1, 3, 512, 512)
        # disparity_factor is (1,)
        
        # We need to broadcast or just use a scalar dependency
        dependency = image.sum() * 0.0 + disparity_factor.sum() * 0.0
        return self.dummy_output + dependency

def create_mock_model(output_path="SharpModel.mlpackage"):
    print("🔮 Creating Mock Sharp Model...")
    
    model = MockSharpModel()
    model.eval()
    
    # Trace
    dummy_image = torch.randn(1, 3, 512, 512)
    dummy_disparity = torch.tensor([1.0])
    traced_model = torch.jit.trace(model, (dummy_image, dummy_disparity))
    
    # Convert
    input_type = ct.ImageType(name="image", shape=dummy_image.shape, scale=1/255.0)
    disparity_type = ct.TensorType(name="disparity_factor", shape=dummy_disparity.shape)
    
    # Output type
    # We want output name to be 'splats'
    
    mlmodel = ct.convert(
        traced_model,
        inputs=[input_type, disparity_type],
        outputs=[ct.TensorType(name="splats")], # Explicitly name output
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram"
    )
    
    mlmodel.save(output_path)
    print(f"✅ Mock model saved to {output_path}")
    print(f"   Input: image (1, 3, 512, 512)")
    print(f"   Output: splats (5000, 14)")

if __name__ == "__main__":
    create_mock_model()
