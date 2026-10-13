import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

/// Cabinet display derivatives only. No sticker border, model changes or original-image writes.
nonisolated enum WardrobeStorageCutoutProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func process(_ data: Data) -> Data? {
        process(data, lift: liftSubject)
    }

    static func process(_ data: Data, lift: (CGImage) -> CGImage?) -> Data? {
        guard !Task.isCancelled, let image = decode(data), let pixels = Pixels(image) else { return nil }
        if pixels.isCutout { return croppedPNG(image, pixels: pixels) }
        // Vision treats a pair of shoes as foreground instances; retain every instance.
        if let lifted = lift(image), !Task.isCancelled,
           let liftedPixels = Pixels(lifted), liftedPixels.isCutout,
           let png = croppedPNG(lifted, pixels: liftedPixels) { return png }
        guard !Task.isCancelled, let removed = removeLightBackground(pixels) else { return nil }
        return croppedPNG(removed, pixels: Pixels(removed))
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ] as CFDictionary)
    }

    private static func liftSubject(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard !Task.isCancelled, let observation = request.results?.first,
                  !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let original = CIImage(cgImage: image)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = original
            blend.maskImage = CIImage(cvPixelBuffer: buffer)
            blend.backgroundImage = CIImage.empty()
            guard let output = blend.outputImage else { return nil }
            return context.createCGImage(output, from: original.extent)
        } catch { return nil }
    }

    /// Only remove light, neutral pixels connected to the image border. A global white
    /// color key would erase the white toe / lace inside the subject as well.
    private static func removeLightBackground(_ input: Pixels) -> CGImage? {
        let width = input.width, height = input.height, count = width * height
        guard width > 2, height > 2 else { return nil }
        let rgba = input.rgba
        var border: [Int] = []
        for x in 0..<width { border.append(x); border.append((height - 1) * width + x) }
        for y in 1..<(height - 1) { border.append(y * width); border.append(y * width + width - 1) }
        let lightBorder = border.filter { pixel in
            let p = pixel * 4
            let r = Int(rgba[p]), g = Int(rgba[p + 1]), b = Int(rgba[p + 2])
            return rgba[p + 3] > 245 && min(r, g, b) >= 218 && max(r, g, b) - min(r, g, b) <= 30
        }
        guard lightBorder.count * 10 >= border.count * 6 else { return nil }
        let background = (0..<3).map { channel in
            let values = lightBorder.map { Int(rgba[$0 * 4 + channel]) }.sorted()
            return values[values.count / 2]
        }
        func isBackground(_ pixel: Int) -> Bool {
            let p = pixel * 4
            if rgba[p + 3] < 12 { return true }
            let r = Int(rgba[p]), g = Int(rgba[p + 1]), b = Int(rgba[p + 2])
            return min(r, g, b) >= 205 && max(r, g, b) - min(r, g, b) <= 40 &&
                abs(r - background[0]) <= 12 && abs(g - background[1]) <= 12 && abs(b - background[2]) <= 12
        }
        var visited = [UInt8](repeating: 0, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(count)
        func enqueue(_ pixel: Int) {
            if visited[pixel] == 0 && isBackground(pixel) {
                visited[pixel] = 1
                queue.append(pixel)
            }
        }
        for pixel in border { enqueue(pixel) }
        var cursor = 0
        while cursor < queue.count {
            if cursor % 4096 == 0 && Task.isCancelled { return nil }
            let pixel = queue[cursor], x = pixel % width, y = pixel / width
            cursor += 1
            if x > 0 { enqueue(pixel - 1) }
            if x + 1 < width { enqueue(pixel + 1) }
            if y > 0 { enqueue(pixel - width) }
            if y + 1 < height { enqueue(pixel + width) }
        }
        guard queue.count > count / 30, count - queue.count > max(12, count / 300) else { return nil }
        var output = rgba
        for pixel in queue {
            let p = pixel * 4
            output[p] = 0; output[p + 1] = 0; output[p + 2] = 0; output[p + 3] = 0
        }
        return Pixels.image(output, width: width, height: height)
    }

    static func croppedPNG(_ image: CGImage, pixels: Pixels? = nil) -> Data? {
        guard let pixels = pixels ?? Pixels(image), let bounds = pixels.subjectBounds else { return nil }
        let padding = max(2, min(image.width, image.height) / 60)
        let crop = bounds.insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard let cropped = image.cropping(to: crop) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cropped, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    struct Pixels {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            self.width = width; self.height = height
            guard width > 0, height > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drew else { return nil }
            rgba = bytes
        }

        var isCutout: Bool {
            let count = width * height
            var clear = 0, subject = 0
            for p in stride(from: 3, to: rgba.count, by: 4) {
                if rgba[p] < 16 { clear += 1 }
                if rgba[p] > 200 { subject += 1 }
            }
            return clear > max(4, count / 100) && subject > max(12, count / 300)
        }

        var subjectBounds: CGRect? {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for pixel in 0..<(width * height) where rgba[pixel * 4 + 3] > 8 {
                let x = pixel % width, y = pixel / width
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        static func image(_ rgba: [UInt8], width: Int, height: Int) -> CGImage? {
            guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }
}
