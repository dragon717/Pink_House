import Foundation
import UIKit
import CoreML

@MainActor
class MobileSAMService {
    static let shared = MobileSAMService()
    
    private var encoder: MobileSAM_Encoder?
    // private var decoder: MobileSAM_Decoder? // Placeholder for when Decoder is ready
    
    private var currentEmbedding: MLMultiArray?
    
    private init() {}
    
    func loadEncoder() throws {
        if encoder == nil {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            encoder = try MobileSAM_Encoder(configuration: config)
        }
    }
    
    /// Pre-compute embedding for an image. Call this when image is selected.
    func encode(image: UIImage) async throws {
        try loadEncoder()
        
        // Resize to 1024x1024
        guard let resized = image.resized(to: CGSize(width: 1024, height: 1024)),
              let buffer = resized.pixelBuffer() else {
            return
        }
        
        // Encode
        if let encoder = encoder {
            let output = try encoder.prediction(image: buffer)
            self.currentEmbedding = output.image_embeddings
            print("MobileSAM Embedding Computed. Shape: \(output.image_embeddings.shape)")
        }
    }
    
    /// Interactive prediction based on point
    func predict(point: CGPoint, in imageSize: CGSize) -> UIImage? {
        guard let embedding = currentEmbedding else {
            print("Error: No embedding. Call encode() first.")
            return nil
        }
        
        // Logic to run Decoder would go here.
        // Input: embedding, point coords (normalized or 1024 scale), labels (1 for foreground)
        
        // Placeholder return
        return nil
    }
}
