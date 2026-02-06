import UIKit
import CoreVideo
import CoreImage

extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        
        // Create an extent vector (the area of the image)
        let extentVector = CIVector(x: inputImage.extent.origin.x,
                                    y: inputImage.extent.origin.y,
                                    z: inputImage.extent.size.width,
                                    w: inputImage.extent.size.height)
        
        // Create a CIAreaAverage filter
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        
        // Get the output image (which is 1x1 pixel)
        guard let outputImage = filter.outputImage else { return nil }
        
        // Create a bitmap context to read the pixel data
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        
        // Render the 1x1 image into the bitmap
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        // Create the UIColor
        return UIColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: CGFloat(bitmap[3]) / 255.0)
    }
    
    /// Returns a new image with orientation fixed to .up.
    /// If the image is already .up, returns self (unless forceCopy is true).
    func normalized(forceCopy: Bool = false) -> UIImage {
        if imageOrientation == .up && !forceCopy {
            return self
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        // Optimize: Use opaque context if the source image is opaque to save memory/disk space
        if let alphaInfo = cgImage?.alphaInfo {
            format.opaque = (alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast)
        }
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let size = self.size
        
        // If image is already smaller than max dimension, return original
        if size.width <= maxDimension && size.height <= maxDimension {
            return self
        }
        
        let aspectRatio = size.width / size.height
        var newSize: CGSize
        
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        // Optimize: Use opaque context if the source image is opaque
        if let alphaInfo = cgImage?.alphaInfo {
            format.opaque = (alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - ML Helpers (Consolidated)
    
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
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        let context = CIContext()
        if let cgImage = self.cgImage {
             context.render(CIImage(cgImage: cgImage), to: buffer)
        }
        
        return buffer
    }
    
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        self.init(cgImage: cgImage)
    }
    
    func masking(with mask: UIImage) -> UIImage {
        guard let cgImage = self.cgImage,
              let maskCG = mask.cgImage else { return self }
        
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
