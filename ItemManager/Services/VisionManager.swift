
import Foundation
import Vision
import UIKit
import SwiftUI
import Combine

class VisionManager: ObservableObject {
    static let shared = VisionManager()
    
    @Published var detectedLines: [CGRect] = []
    
    // Throttle control
    private var lastDetectionTime: Date = Date.distantPast
    private let throttleInterval: TimeInterval = 0.5
    private var isDetecting = false
    
    // Cache for normalized coordinates
    private var cachedImageSize: CGSize = .zero
    
    // Performance: Context reuse
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    func detectLines(in image: UIImage, roi: CGRect? = nil) {
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= throttleInterval else { return }
        guard !isDetecting else { return }
        
        lastDetectionTime = now
        isDetecting = true
        
        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. Preprocess Image (Downsample & Filter)
            // Convert to CIImage for filtering
            guard let ciImage = CIImage(image: image) else {
                self.endDetection()
                return
            }
            
            // Apply Grayscale & Contrast
            // This reduces color noise and enhances edges for line detection
            let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 2.0
            ])
            
            // Render back to CGImage for Vision
            // Use cached context for performance
            guard let processedCGImage = self.context.createCGImage(grayscale, from: grayscale.extent) else {
                self.endDetection()
                return
            }
            
            let request = VNDetectRectanglesRequest { request, error in
                guard let observations = request.results as? [VNRectangleObservation] else {
                    self.endDetection()
                    return
                }
                
                // Process observations
                // Vision coordinates are normalized (0-1), origin bottom-left
                var lines = observations.map { $0.boundingBox }
                
                // If ROI was used, convert coordinates back to full image normalized space
                if let roi = roi {
                    lines = lines.map { rect in
                        CGRect(
                            x: roi.origin.x + rect.origin.x * roi.width,
                            y: roi.origin.y + rect.origin.y * roi.height,
                            width: rect.width * roi.width,
                            height: rect.height * roi.height
                        )
                    }
                }
                
                // Filter lines based on minimum length
                // Since coordinates are normalized (0-1), we use different thresholds for H/V
                
                let minHLength: CGFloat = 0.15  // Horizontal: Require 15% of screen width
                let minVLength: CGFloat = 0.04  // Vertical: Require 4% of screen height
                
                // Aspect Ratio Threshold (Thickness check)
                // To avoid detecting buttons/text blocks as lines, we require them to be thin.
                // Ratio = ShortSide / LongSide. Lower means thinner.
                let maxHAspectRatio: CGFloat = 0.1 // Horizontal lines must be very thin
                let maxVAspectRatio: CGFloat = 0.2 // Vertical lines can be chunkier (due to ROI cropping)
                
                lines = lines.filter { rect in
                    let isHorizontal = rect.width > rect.height
                    let aspectRatio = isHorizontal ? (rect.height / rect.width) : (rect.width / rect.height)
                    
                    if isHorizontal {
                        return rect.width >= minHLength && aspectRatio < maxHAspectRatio
                    } else {
                        return rect.height >= minVLength && aspectRatio < maxVAspectRatio
                    }
                }
                
                DispatchQueue.main.async {
                    self.detectedLines = lines
                    self.endDetection()
                }
            }
            
            // Configuration for line-like rectangles
            request.minimumAspectRatio = 0.0  // Allow thin lines
            request.maximumAspectRatio = 0.25 // Slightly stricter than 0.4 to reject obvious blocks
            request.minimumSize = 0.03        // Reduced to 0.03 to catch smaller lines
            request.quadratureTolerance = 45  // Increased tolerance for imperfect rectangles
            request.minimumConfidence = 0.3   // Lower confidence to catch more potential lines
            request.maximumObservations = 20  // Find more candidates
            
            if let roi = roi {
                request.regionOfInterest = roi
            }
            
            let handler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func endDetection() {
        DispatchQueue.main.async {
            self.isDetecting = false
        }
    }
    
    // Find closest line to a point (in normalized coordinates 0-1)
    func findClosestLine(to point: CGPoint, threshold: CGFloat = 0.1) -> CGRect? {
        var closestLine: CGRect?
        var minDistance: CGFloat = threshold
        
        for line in detectedLines {
            // Calculate distance from point to the nearest point on the line segment
            // This is much more accurate than distance to center, especially for long lines
            
            // 1. Get line segment endpoints
            // VNRectangleObservation lines are actually rectangles, but we treat them as lines along their major axis
            let isHorizontal = line.width > line.height
            
            let p1, p2: CGPoint
            if isHorizontal {
                // Horizontal line: (minX, midY) -> (maxX, midY)
                p1 = CGPoint(x: line.minX, y: line.midY)
                p2 = CGPoint(x: line.maxX, y: line.midY)
            } else {
                // Vertical line: (midX, minY) -> (midX, maxY)
                p1 = CGPoint(x: line.midX, y: line.minY)
                p2 = CGPoint(x: line.midX, y: line.maxY)
            }
            
            // 2. Calculate distance from point to segment p1-p2
            let distance = distancePointToSegment(point, p1, p2)
            
            if distance < minDistance {
                minDistance = distance
                closestLine = line
            }
        }
        
        return closestLine
    }
    
    // Helper: Distance from point p to line segment v-w
    private func distancePointToSegment(_ p: CGPoint, _ v: CGPoint, _ w: CGPoint) -> CGFloat {
        let l2 = hypot(w.x - v.x, w.y - v.y) // length squared
        if l2 == 0 { return hypot(p.x - v.x, p.y - v.y) } // v == w case
        
        // Consider the line extending the segment, parameterized as v + t (w - v).
        // We find projection of point p onto the line.
        // It falls where t = [(p-v) . (w-v)] / |w-v|^2
        // We clamp t from [0,1] to handle points outside the segment.
        let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / (l2 * l2)
        let clampedT = max(0, min(1, t))
        
        let projection = CGPoint(
            x: v.x + clampedT * (w.x - v.x),
            y: v.y + clampedT * (w.y - v.y)
        )
        
        return hypot(p.x - projection.x, p.y - projection.y)
    }
    
    // Helper to take a screenshot of the window
    func captureScreen() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return nil }
        
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}
