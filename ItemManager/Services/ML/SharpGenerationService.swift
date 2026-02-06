import Foundation
import CoreML
import UIKit
import simd
import Combine


/// Service responsible for generating 3D Gaussian Splats from 2D images
/// using the ml-sharp CoreML model.
class SharpGenerationService: ObservableObject {
    static let shared = SharpGenerationService()
    
    enum ModelState: Equatable {
        case loading
        case ready
        case error(String)
    }
    
    @Published var isGenerating = false
    @Published var progress: Float = 0.0
    @Published var modelState: ModelState = .loading
    
    // CoreML Model (Placeholder type until actual class is generated)
    private var model: SharpModel?
    
    private init() {
        AppLogger.info("SharpGenerationService: init starting")
        // Load model asynchronously in a detached task to avoid blocking MainActor
        // Use .utility priority to avoid starving the UI thread during heavy IO
        Task.detached(priority: .utility) { [weak self] in
            AppLogger.info("SharpGenerationService: Task started (Priority: Utility)")
            guard let self = self else { return }
            
            await MainActor.run { self.modelState = .loading }
            
            do {
                AppLogger.info("SharpGenerationService: Loading config")
                let config = MLModelConfiguration()
                // Use cpuOnly to minimize memory footprint and avoid OOM on constrained devices
                // ANE/GPU can require large contiguous memory blocks which fail when RAM is fragmented
                config.computeUnits = .cpuOnly 
                
                // Initialize model (heavy IO/Validation)
                // The model is large (~1.2GB), so this step might take significant time
                AppLogger.info("SharpGenerationService: Initializing SharpModel (This may take time due to model size)...")
                let start = Date()
                
                // Try to use async load if available (Swift 5.5+ / macOS 12+ / iOS 15+)
                // Note: generated Swift classes from CoreML usually provide `load(configuration:)` in newer Xcode versions.
                // If the compiler fails, we will revert to synchronous init.
                // Checking if we can use the async loading pattern:
                // Since we are already in a detached task, synchronous init is also fine, 
                // but we stick to the config optimization.
                let loadedModel = try SharpModel(configuration: config)
                
                let duration = Date().timeIntervalSince(start)
                
                // Assign safely
                self.model = loadedModel
                AppLogger.info("SharpGenerationService: CoreML model loaded successfully in \(String(format: "%.2f", duration))s.")
                
                await MainActor.run { self.modelState = .ready }
            } catch {
                let errorMessage = "Failed to load CoreML model: \(error.localizedDescription)"
                AppLogger.error("SharpGenerationService: \(errorMessage)")
                await MainActor.run { self.modelState = .error(errorMessage) }
            }
        }
        AppLogger.info("SharpGenerationService: init finished (Task scheduled)")
    }
    
    /// Errors that can occur during generation
    enum GenerationError: Error {
        case modelNotLoaded
        case preprocessingFailed
        case predictionFailed
        case postprocessingFailed
    }
    
    /// Generate Gaussian Splats from a 2D image
    /// - Parameter image: The source image (e.g., cutout of clothing)
    /// - Returns: Array of GaussianSplat structs
    func generate(from image: UIImage) async throws -> [GaussianSplat] {
        guard modelState == .ready else {
            throw GenerationError.modelNotLoaded
        }
        
        AppLogger.info("SharpGenerationService: Starting 3D generation...")
        
        await MainActor.run {
            self.isGenerating = true
            self.progress = 0.1
        }
        
        defer {
            Task { @MainActor in
                self.isGenerating = false
                self.progress = 0.0
                AppLogger.info("SharpGenerationService: Generation process finished.")
            }
        }
        
        // 1. Resize Image immediately to reduce memory footprint
        // We do this before entering the detached task if possible, or inside.
        // Let's do it inside to keep main thread free, but ensure we release the original image quickly.
        
        // Use Task.detached to ensure heavy work runs off the main thread
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { throw GenerationError.modelNotLoaded }
            
            // 1. Preprocessing
            AppLogger.info("SharpGenerationService: Preprocessing image...")
            
            // Optimization: Create a local scope for resizing to ensure intermediate objects are released
            guard let pixelBuffer = self.preprocessImage(image) else {
                 AppLogger.error("SharpGenerationService: Preprocessing failed")
                 throw GenerationError.preprocessingFailed
            }
            
            // At this point, `image` (the argument) is still held by the closure, 
            // but we have extracted what we need. 
            // We proceed to inference.
            
            await MainActor.run { self.progress = 0.3 }
            
            // 2. Inference
            if let model = self.model {
                AppLogger.info("SharpGenerationService: Running inference (CoreML Mode)...")
                do {
                    // Wrap inference in autoreleasepool to ensure intermediate tensors are released immediately
                    let output: SharpModelOutput = try await self.runInference(model: model, pixelBuffer: pixelBuffer)
                    
                    await MainActor.run { self.progress = 0.8 }
                    
                    // 3. Post-processing
                    AppLogger.info("SharpGenerationService: Post-processing results...")
                    // Note: Ensure your model output is named 'splats'. 
                    // If it's named something else (e.g. 'var_1234'), change 'output.splats' to that name.
                    return try self.parseOutput(output.splats)
                } catch {
                    AppLogger.error("SharpGenerationService: Inference failed - \(error)")
                    throw GenerationError.predictionFailed
                }
            } else {
                // Should not happen if modelState check passed, but kept for safety
                AppLogger.error("SharpGenerationService: Model is nil but state is ready")
                throw GenerationError.modelNotLoaded
            }
        }.value
    }
    
    /// Helper to resize and convert image to CVPixelBuffer
    /// Returns nil on failure
    private func preprocessImage(_ image: UIImage) -> CVPixelBuffer? {
        // Resize to 512x512 (standard for ml-sharp)
        guard let resizedImage = image.resized(to: CGSize(width: 512, height: 512)) else {
            return nil
        }
        return resizedImage.pixelBuffer()
    }
    
    /// Helper to run inference with autoreleasepool
    private func runInference(model: SharpModel, pixelBuffer: CVPixelBuffer) async throws -> SharpModelOutput {
        // Prepare inputs
        // Disparity factor: f_px / width
        // Assuming 60 deg FOV: f_px = (512/2) / tan(30) ≈ 443
        // factor = 443 / 512 ≈ 0.865
        let disparityFactor: Float = 0.865
        let disparityShape = [1] as [NSNumber]
        let disparityArray = try MLMultiArray(shape: disparityShape, dataType: .float32)
        disparityArray[0] = NSNumber(value: disparityFactor)
        
        let input = SharpModelInput(image: pixelBuffer, disparity_factor: disparityArray)
        
        // Use synchronous prediction within a detached task (which this is) + autoreleasepool
        // Note: CoreML async prediction doesn't strictly guarantee memory release timing as well as autoreleasepool block around sync call?
        // Actually, `await model.prediction` is better for concurrency but might hold memory.
        // Let's stick to await but wrapped in a helper that might help ARC.
        
        return try await model.prediction(input: input)
    }
    
    /// Parse MLMultiArray output to GaussianSplat array
    /// Expected shape: (N, 14) or (1, N, 14)
    /// Channels: 3 Pos, 4 Rot, 3 Scale, 3 Color, 1 Opacity
    private func parseOutput(_ output: MLMultiArray) throws -> [GaussianSplat] {
        var count = 0
        var channels = 0
        
        // Determine shape dynamically
        if output.shape.count == 3 {
            // Case: (Batch=1, N, Channels) e.g. (1, 4096, 14)
            count = output.shape[1].intValue
            channels = output.shape[2].intValue
        } else if output.shape.count == 2 {
            // Case: (N, Channels) e.g. (4096, 14)
            count = output.shape[0].intValue
            channels = output.shape[1].intValue
        } else {
            AppLogger.error("SharpGenerationService: Unexpected output shape: \(output.shape)")
            // Fallback: try to guess
            if let last = output.shape.last, last.intValue == 14 {
                channels = 14
                count = output.count / 14
            } else {
                return []
            }
        }
        
        AppLogger.info("SharpGenerationService: Parsing \(count) splats with \(channels) channels from shape \(output.shape)")
        
        var splats: [GaussianSplat] = []
        splats.reserveCapacity(count)
        
        // Pointer access is faster
        // Note: CoreML arrays can be strided, assuming dense here or using subscript slow path if needed.
        // For max performance, use raw pointer if dataType is Float32.
        
        if output.dataType == .float32 {
            let ptr = UnsafeMutablePointer<Float32>(OpaquePointer(output.dataPointer))
            
            for i in 0..<count {
                let offset = i * channels
                
                // Safety check for buffer overrun
                // if offset + 13 >= output.count { break }
                
                // 1. Position (0-2)
                let x = ptr[offset + 0]
                let y = ptr[offset + 1]
                let z = ptr[offset + 2]
                
                // 2. Scale (3-5) - Usually Exp activation
                // Note: Updated order based on convert_real.py
                let sx = exp(ptr[offset + 3])
                let sy = exp(ptr[offset + 4])
                let sz = exp(ptr[offset + 5])
                
                // 3. Rotation (6-9) - Quaternion (x,y,z,w)
                // Normalize quaternion
                let rx = ptr[offset + 6]
                let ry = ptr[offset + 7]
                let rz = ptr[offset + 8]
                let rw = ptr[offset + 9]
                let qLen = sqrt(rx*rx + ry*ry + rz*rz + rw*rw)
                // Avoid division by zero
                let rotation: SIMD4<Float>
                if qLen > 0.000001 {
                    rotation = SIMD4<Float>(rx/qLen, ry/qLen, rz/qLen, rw/qLen)
                } else {
                    rotation = SIMD4<Float>(0, 0, 0, 1)
                }
                
                // 4. Color (10-12) - Usually Sigmoid activation [0,1]
                // Or RGB direct. Let's assume Sigmoid.
                func sigmoid(_ v: Float) -> Float { return 1.0 / (1.0 + exp(-v)) }
                let r = sigmoid(ptr[offset + 10])
                let g = sigmoid(ptr[offset + 11])
                let b = sigmoid(ptr[offset + 12])
                
                // 5. Opacity (13) - Sigmoid
                let opacity = sigmoid(ptr[offset + 13])
                
                // Filter low opacity points
                if opacity < 0.1 { continue }
                
                splats.append(GaussianSplat(
                    position: SIMD3<Float>(x, y, z),
                    scale: SIMD3<Float>(sx, sy, sz),
                    rotation: rotation,
                    color: SIMD3<Float>(r, g, b),
                    opacity: opacity
                ))
            }
        } else if output.dataType == .float16 {
             // Handle Float16
             // Since we cannot easily use UnsafeMutablePointer<Float16> in all Swift versions or without extra imports,
             // and CoreML's dataPointer for Float16 is raw bytes.
             // We can use `output[i]` which is slower but safe, OR use unsafe raw pointer assuming Float16 is 2 bytes.
             
             // Check strict stride
             if output.strides.count == 2 && output.strides[1].intValue == 1 {
                 let ptr = UnsafeMutableRawPointer(output.dataPointer).assumingMemoryBound(to: Float16.self)
                 
                 for i in 0..<count {
                     let offset = i * channels
                     
                     // Helper to read and convert to Float
                     func read(_ idx: Int) -> Float {
                         return Float(ptr[idx])
                     }
                     
                     // 1. Position (0-2)
                     let x = read(offset + 0)
                     let y = read(offset + 1)
                     let z = read(offset + 2)
                     
                     // 2. Scale (3-5)
                     let sx = exp(read(offset + 3))
                     let sy = exp(read(offset + 4))
                     let sz = exp(read(offset + 5))
                     
                     // 3. Rotation (6-9)
                     let rx = read(offset + 6)
                     let ry = read(offset + 7)
                     let rz = read(offset + 8)
                     let rw = read(offset + 9)
                     let qLen = sqrt(rx*rx + ry*ry + rz*rz + rw*rw)
                     let rotation = SIMD4<Float>(rx/qLen, ry/qLen, rz/qLen, rw/qLen)
                     
                     // 4. Color (10-12)
                     func sigmoid(_ v: Float) -> Float { return 1.0 / (1.0 + exp(-v)) }
                     let r = sigmoid(read(offset + 10))
                     let g = sigmoid(read(offset + 11))
                     let b = sigmoid(read(offset + 12))
                     
                     // 5. Opacity (13)
                     let opacity = sigmoid(read(offset + 13))
                     
                     if opacity < 0.1 { continue }
                     
                     splats.append(GaussianSplat(
                         position: SIMD3<Float>(x, y, z),
                         scale: SIMD3<Float>(sx, sy, sz),
                         rotation: rotation,
                         color: SIMD3<Float>(r, g, b),
                         opacity: opacity
                     ))
                 }
             } else {
                 // Fallback for non-contiguous or complex strides (Slow path)
                 AppLogger.warning("Using slow path for Float16 parsing due to strides")
                 for i in 0..<count {
                     // 1. Position
                     let x = output[[i as NSNumber, 0 as NSNumber]].floatValue
                     let y = output[[i as NSNumber, 1 as NSNumber]].floatValue
                     let z = output[[i as NSNumber, 2 as NSNumber]].floatValue
                     
                     // 2. Scale
                     let sx = exp(output[[i as NSNumber, 3 as NSNumber]].floatValue)
                     let sy = exp(output[[i as NSNumber, 4 as NSNumber]].floatValue)
                     let sz = exp(output[[i as NSNumber, 5 as NSNumber]].floatValue)
                     
                     // 3. Rotation
                     let rx = output[[i as NSNumber, 6 as NSNumber]].floatValue
                     let ry = output[[i as NSNumber, 7 as NSNumber]].floatValue
                     let rz = output[[i as NSNumber, 8 as NSNumber]].floatValue
                     let rw = output[[i as NSNumber, 9 as NSNumber]].floatValue
                     let qLen = sqrt(rx*rx + ry*ry + rz*rz + rw*rw)
                     let rotation = SIMD4<Float>(rx/qLen, ry/qLen, rz/qLen, rw/qLen)
                     
                     // 4. Color
                     func sigmoid(_ v: Float) -> Float { return 1.0 / (1.0 + exp(-v)) }
                     let r = sigmoid(output[[i as NSNumber, 10 as NSNumber]].floatValue)
                     let g = sigmoid(output[[i as NSNumber, 11 as NSNumber]].floatValue)
                     let b = sigmoid(output[[i as NSNumber, 12 as NSNumber]].floatValue)
                     
                     // 5. Opacity
                     let opacity = sigmoid(output[[i as NSNumber, 13 as NSNumber]].floatValue)
                     
                     if opacity < 0.1 { continue }
                     
                     splats.append(GaussianSplat(
                         position: SIMD3<Float>(x, y, z),
                         scale: SIMD3<Float>(sx, sy, sz),
                         rotation: rotation,
                         color: SIMD3<Float>(r, g, b),
                         opacity: opacity
                     ))
                 }
             }
        } else {
            // Double or other types
             AppLogger.warning("Using slow path for generic type parsing")
             for i in 0..<count {
                 // 1. Position
                 let x = output[[i as NSNumber, 0 as NSNumber]].floatValue
                 let y = output[[i as NSNumber, 1 as NSNumber]].floatValue
                 let z = output[[i as NSNumber, 2 as NSNumber]].floatValue
                 
                 // 2. Scale
                 let sx = exp(output[[i as NSNumber, 3 as NSNumber]].floatValue)
                 let sy = exp(output[[i as NSNumber, 4 as NSNumber]].floatValue)
                 let sz = exp(output[[i as NSNumber, 5 as NSNumber]].floatValue)
                 
                 // 3. Rotation
                 let rx = output[[i as NSNumber, 6 as NSNumber]].floatValue
                 let ry = output[[i as NSNumber, 7 as NSNumber]].floatValue
                 let rz = output[[i as NSNumber, 8 as NSNumber]].floatValue
                 let rw = output[[i as NSNumber, 9 as NSNumber]].floatValue
                 let qLen = sqrt(rx*rx + ry*ry + rz*rz + rw*rw)
                 let rotation = SIMD4<Float>(rx/qLen, ry/qLen, rz/qLen, rw/qLen)
                 
                 // 4. Color
                 func sigmoid(_ v: Float) -> Float { return 1.0 / (1.0 + exp(-v)) }
                 let r = sigmoid(output[[i as NSNumber, 10 as NSNumber]].floatValue)
                 let g = sigmoid(output[[i as NSNumber, 11 as NSNumber]].floatValue)
                 let b = sigmoid(output[[i as NSNumber, 12 as NSNumber]].floatValue)
                 
                 // 5. Opacity
                 let opacity = sigmoid(output[[i as NSNumber, 13 as NSNumber]].floatValue)
                 
                 if opacity < 0.1 { continue }
                 
                 splats.append(GaussianSplat(
                     position: SIMD3<Float>(x, y, z),
                     scale: SIMD3<Float>(sx, sy, sz),
                     rotation: rotation,
                     color: SIMD3<Float>(r, g, b),
                     opacity: opacity
                 ))
             }
        }
        
        return splats
    }
    
    /// Generate a placeholder sphere of gaussians for testing
    private func generatePlaceholderSplats() -> [GaussianSplat] {
        var splats: [GaussianSplat] = []
        let count = 10000 // Increase count for better shape
        
        for _ in 0..<count {
            // Generate points on a sphere
            let theta = Float.random(in: 0...(2 * .pi))
            let phi = Float.random(in: 0...(.pi))
            let r: Float = 1.5 // Slightly larger sphere
            
            let x = r * sin(phi) * cos(theta)
            let y = r * sin(phi) * sin(theta)
            let z = r * cos(phi)
            
            let pos = SIMD3<Float>(x, y, z)
            
            // Color based on position (Rainbow sphere)
            // Map [-r, r] to [0, 1]
            let rCol = (x / r + 1) / 2
            let gCol = (y / r + 1) / 2
            let bCol = (z / r + 1) / 2
            let color = SIMD3<Float>(rCol, gCol, bCol)
            
            splats.append(GaussianSplat(
                position: pos,
                scale: SIMD3<Float>(0.02, 0.02, 0.02), // Smaller, sharper points
                rotation: SIMD4<Float>(0, 0, 0, 1),
                color: color,
                opacity: 0.8
            ))
        }
        
        return splats
    }
}

// Helper extension for resizing moved to UIImage+Extensions.swift
// to avoid duplication and conflicts.

