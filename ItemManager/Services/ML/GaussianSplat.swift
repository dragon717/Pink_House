import Foundation
import simd

/// Represents a single 3D Gaussian Splat
/// This is the standard data structure for rendering
struct GaussianSplat: Identifiable {
    let id = UUID()
    
    /// Center position of the gaussian (x, y, z)
    var position: SIMD3<Float>
    
    /// Scale of the gaussian (x, y, z)
    var scale: SIMD3<Float>
    
    /// Rotation quaternion (ix, iy, iz, r)
    var rotation: SIMD4<Float>
    
    /// Color (R, G, B) - pre-sigmoid if from model, but here let's assume normalized [0,1]
    var color: SIMD3<Float>
    
    /// Opacity (Alpha) - normalized [0,1]
    var opacity: Float
    
    /// Spherical Harmonics coefficients (optional, for view-dependent color)
    /// Simplified to just base color for now
    // var sh: [Float]?
}

extension GaussianSplat {
    /// Create a random splat for testing
    static func random() -> GaussianSplat {
        return GaussianSplat(
            position: SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)),
            scale: SIMD3<Float>(0.1, 0.1, 0.1),
            rotation: SIMD4<Float>(0, 0, 0, 1),
            color: SIMD3<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)),
            opacity: Float.random(in: 0.5...1.0)
        )
    }
}
