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

// Helper Extensions moved to UIImage+Extensions.swift
// to avoid conflicts with SharpGenerationService and other ML services.

