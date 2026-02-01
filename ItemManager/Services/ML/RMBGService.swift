import Foundation
import UIKit
import CoreML
import Vision

@MainActor
class RMBGService {
    static let shared = RMBGService()
    
    private var model: RMBG14?
    
    private init() {
        // Initialize lazily to save memory
    }
    
    func loadModel() throws {
        if model == nil {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Use ANE
            model = try RMBG14(configuration: config)
        }
    }
    
    func process(image: UIImage) async throws -> UIImage {
        try loadModel()
        guard let model = model else { throw CutoutError.processingFailed }
        
        // 1. Resize to 1024x1024 (RMBG standard input)
        // Note: Check actual input size from model metadata after conversion
        let targetSize = CGSize(width: 1024, height: 1024)
        guard let resized = image.resized(to: targetSize),
              let pixelBuffer = resized.pixelBuffer() else {
            throw CutoutError.processingFailed
        }
        
        // 2. Predict
        let input = RMBG14Input(input: pixelBuffer)
        let output = try model.prediction(input: input)
        
        // 3. Process Mask (Output is usually a probability map)
        // Assuming output is CVPixelBuffer of mask
        let maskBuffer = output.output
        
        // 4. Apply Mask to Original Image
        guard let maskImage = UIImage(pixelBuffer: maskBuffer) else {
            throw CutoutError.processingFailed
        }
        
        // Resize mask back to original size if needed
        let finalMask = maskImage.resized(to: image.size) ?? maskImage
        
        return image.masking(with: finalMask)
    }
}

// Helper Extensions
extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
    
    func pixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let context = CIContext()
        if let cgImage = self.cgImage {
             context.render(CIImage(cgImage: cgImage), to: buffer)
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        
        return buffer
    }
    
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        self.init(cgImage: cgImage)
    }
    
    func masking(with mask: UIImage) -> UIImage {
        // Simple masking logic
        guard let cgImage = self.cgImage,
              let maskCG = mask.cgImage else { return self }
        
        // Invert mask if needed? RMBG usually outputs alpha.
        // If it's grayscale, use as mask.
        
        let maskImage = CGImage(maskWidth: maskCG.width,
                                height: maskCG.height,
                                bitsPerComponent: maskCG.bitsPerComponent,
                                bitsPerPixel: maskCG.bitsPerPixel,
                                bytesPerRow: maskCG.bytesPerRow,
                                provider: maskCG.dataProvider!,
                                decode: nil,
                                shouldInterpolate: false)!
                                
        // Actually, CoreGraphics masking is tricky. 
        // Better use CIBlendWithMask
        let originalCI = CIImage(cgImage: cgImage)
        let maskCI = CIImage(cgImage: maskCG)
        
        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalCI
        filter.maskImage = maskCI
        filter.backgroundImage = CIImage.empty()
        
        let context = CIContext()
        if let result = filter.outputImage,
           let resultCG = context.createCGImage(result, from: originalCI.extent) {
            return UIImage(cgImage: resultCG)
        }
        return self
    }
}
