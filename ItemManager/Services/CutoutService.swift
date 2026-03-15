
import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftData
import CryptoKit

enum CutoutError: Error {
    case processingFailed
    case noSubjectFound
    case lowConfidence
}

@MainActor
class CutoutService {
    static let shared = CutoutService()
    
    private init() {}
    
    /// 核心流程：识别主体 -> 抠图 -> 加白边 -> 保存
    /// - Parameters:
    ///   - clothing: 可选关联的服装对象，用于去重检查（同一件衣服同一张图不重复抠）
    func processImage(image: UIImage, category: String, clothing: Clothing? = nil, context: ModelContext) async throws -> CutoutItem {
        // 0. Pre-calculation: Hash Check for Deduplication
        // 计算原始图片哈希用于去重
        // 使用与 ImageManager 一致的压缩参数来确保 Hash 一致性（虽然这里用于 CutoutItem 的去重，逻辑自洽即可）
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            throw CutoutError.processingFailed
        }
        let originalHash = computeHash(data: imageData)
        
        // 检查是否存在相同的抠图记录
        let descriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate { $0.originalImageHash == originalHash })
        if let existingItem = try? context.fetch(descriptor).first {
            // 检查是否是旧格式 (非 PNG)，如果是，则重新处理以修复透明度问题
            if !existingItem.imagePath.lowercased().hasSuffix(".png") {
                print("Existing cutout found but format is not PNG. Reprocessing to ensure transparency...")
                try await reprocessItem(item: existingItem, with: image, context: context)
                
                // 确保关联信息更新
                if let clothing = clothing {
                    if existingItem.linkedClothingID == nil {
                        existingItem.linkedClothingID = clothing.id
                    }
                    existingItem.clothingName = clothing.name
                }
                
                return existingItem
            }
            
            print("Duplicate cutout found for hash: \(originalHash). Skipping processing.")
            
            // 如果传入了 clothing
            if let clothing = clothing {
                // 如果未关联，则建立关联
                if existingItem.linkedClothingID == nil {
                    existingItem.linkedClothingID = clothing.id
                }
                // 总是尝试更新缓存的名字
                existingItem.clothingName = clothing.name
                // try? context.save() // Auto-save usually handles this, or caller saves
            }
            
            return existingItem
        }
        
        // 1. Normalize Orientation (Fix rotation issue)
        let normalizedImage = normalizeOrientation(image)
        
        // 2. 识别并抠图
        var cutoutImage: UIImage
        var confidence: Float
        
        do {
            (cutoutImage, confidence) = try await liftSubject(from: normalizedImage)
        } catch {
            print("Standard liftSubject failed: \(error). Trying fallback methods.")
            // 降级策略 1: 显著性检测 (Saliency) - 适用于主体明确但 Vision 无法识别实例的情况
            if let saliencyResult = try? await liftSubjectUsingSaliency(from: normalizedImage) {
                 cutoutImage = saliencyResult.0
                 confidence = saliencyResult.1
                 print("Saliency fallback succeeded.")
            } else {
                throw error
            }
        }
        
        // 如果置信度过低，再次尝试降级或失败
        if confidence < 0.5 { // Lowered threshold for fallback
             print("Confidence low (\(confidence)). Trying Saliency fallback if not already used.")
             if let saliencyResult = try? await liftSubjectUsingSaliency(from: normalizedImage) {
                 cutoutImage = saliencyResult.0
                 confidence = saliencyResult.1
             } else {
                 throw CutoutError.lowConfidence
             }
        }
        
        // 2.1 自动分类
        var finalCategory = "未分类"
        
        // 1. 尝试标准化传入的分类 (比如将 "JSK" -> "裙装")
        // 如果传入了有效的分类（非空且非默认），尝试基于它进行标准化
        if category != "未分类" && !category.isEmpty {
            if let standardized = standardizeCategory(category) {
                finalCategory = standardized
                print("Standardized category '\(category)' to '\(finalCategory)'")
            } else {
                // 如果传入了奇怪的词无法标准化，仍然走 Vision 识别？
                // 或者保留原词？
                // 为了配合 UI 的固定筛选，建议还是走 Vision 重新识别大类。
                // 但为了不丢信息，如果 Vision 识别出"未分类"，也许可以回退到 standardized 为 nil 的情况...
                // 这里简化策略：无法标准化的词 -> 视为无效分类，走 Vision。
                print("Category '\(category)' not recognized. Falling back to Vision.")
            }
        }
        
        // 只有当需要 Vision 识别时（分类是默认的"未分类"或空的），才调用分类器
        if finalCategory == "未分类" {
            if let recognizedCategory = try? await classifyImage(image: normalizedImage) {
                print("Vision recognized category: \(recognizedCategory)")
                finalCategory = recognizedCategory
            }
        }
        
        // 3. 加白边 (UI 线程处理)
        // 考虑到性能，这里使用较简单的绘制
        let borderedImage = addWhiteBorder(to: cutoutImage, borderWidth: 4.0)
        
        // 4. 保存到文件系统和数据库
        // 使用 PNG 格式以保留透明通道
        guard let savedPath = ImageManager.shared.saveImage(borderedImage, context: context, format: .png) else {
            throw CutoutError.processingFailed
        }
        
        let width = Double(borderedImage.size.width)
        let height = Double(borderedImage.size.height)
        
        let cutoutItem = CutoutItem(
            originalImageHash: originalHash,
            category: finalCategory,
            imagePath: savedPath,
            width: width,
            height: height,
            linkedClothingID: clothing?.id,
            clothingName: clothing?.name
        )
        
        context.insert(cutoutItem)
        return cutoutItem
    }
    
    /// 当删除图片或抠图时，检查并重置关联裙装的“已替换”状态
    /// - Parameters:
    ///   - imagePath: 被删除图片的路径（文件名）
    ///   - context: ModelContext
    func handleCutoutDeletion(imagePath: String, context: ModelContext) {
        // 查找是否是抠图 (根据 imagePath)
        let descriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate { $0.imagePath == imagePath })
        
        do {
            if let cutout = try context.fetch(descriptor).first {
                // 如果找到了 CutoutItem，检查其关联
                if let clothingID = cutout.linkedClothingID {
                    let clothingDesc = FetchDescriptor<Clothing>(predicate: #Predicate { $0.id == clothingID })
                    if let clothing = try context.fetch(clothingDesc).first {
                        // 重置标记
                        if let replacedID = clothing.replacedCutoutID, replacedID == cutout.id {
                            clothing.replacedCutoutID = nil
                            print("CutoutService: Reset replacedCutoutID for clothing '\(clothing.name)' because cutout '\(imagePath)' is being deleted.")
                        }
                    }
                }
            }
        } catch {
            print("CutoutService: Failed to fetch cutout for deletion check: \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func computeHash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalizedImage
    }
    
    private func liftSubject(from image: UIImage) async throws -> (UIImage, Float) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try handler.perform([request])
        
        guard let result = request.results?.first else {
            throw CutoutError.noSubjectFound
        }
        
        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        
        // Convert CVPixelBuffer to CIImage
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        let originalImage = CIImage(cgImage: image.cgImage!)
        
        // Apply mask
        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalImage
        filter.maskImage = maskImage
        filter.backgroundImage = CIImage.empty()
        
        guard let outputImage = filter.outputImage,
              let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent) else {
            throw CutoutError.processingFailed
        }
        
        // 计算置信度 (平均 mask 强度？Vision 不直接提供整体置信度，这里用 mask 覆盖率或假设成功即 1.0)
        // 实际上 VNInstanceMaskObservation 没有 confidence 属性。
        // 我们可以假设如果有结果，置信度尚可。
        // 为了兼容上面的逻辑，我们返回 1.0 (High)
        return (UIImage(cgImage: cgImage), 1.0)
    }
    
    // Fallback using Saliency
    private func liftSubjectUsingSaliency(from image: UIImage) async throws -> (UIImage, Float) {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try handler.perform([request])
        
        guard let result = request.results?.first else {
            throw CutoutError.noSubjectFound
        }
        
        // Saliency returns a heatmap (low res). Need to threshold and upscale.
        // This is a rough fallback.
        // Better: Use Saliency rect to crop? No, we want transparency.
        // Simple implementation: Just treat saliency map as alpha mask (after thresholding)
        
        // For now, let's just return failure to trigger UI warning if Vision fails.
        // Or implement a simple center-crop or "Keep as is" if all else fails?
        // Let's implement a basic mask from saliency.
        
        let pixelBuffer = result.pixelBuffer
        let maskImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Resize mask to match image
        let scaleX = image.size.width / maskImage.extent.width
        let scaleY = image.size.height / maskImage.extent.height
        let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Thresholding
        let thresholdFilter = CIFilter.colorMatrix()
        thresholdFilter.inputImage = scaledMask
        // Boost alpha
        thresholdFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: 5) // Amplify
        
        let originalImage = CIImage(cgImage: image.cgImage!)
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = originalImage
        blendFilter.maskImage = thresholdFilter.outputImage
        blendFilter.backgroundImage = CIImage.empty()
        
        guard let outputImage = blendFilter.outputImage,
              let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent) else {
             throw CutoutError.processingFailed
        }
        
        return (UIImage(cgImage: cgImage), 0.6) // Lower confidence
    }
    
    private func classifyImage(image: UIImage) async throws -> String {
        // 使用 Vision 的 VNClassifyImageRequest
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            return "未分类"
        }
        
        // 过滤高置信度的结果
        let validObservations = observations.filter { $0.confidence > 0.3 }
        
        // 映射英文标签到我们的中文分类
        for observation in validObservations {
            let identifier = observation.identifier.lowercased()
            if let category = mapIdentifierToCategory(identifier) {
                return category
            }
        }
        
        return "未分类"
    }
    
    private func mapIdentifierToCategory(_ id: String) -> String? {
        // 1. 裙装 (Skirts & Dresses)
        let strongDressKeywords = [
            "dress", "skirt", "gown", "frock", "pinafore", "sarong", "kilt"
        ]
        if strongDressKeywords.contains(where: { id.contains($0) }) {
            return "裙装"
        }
        
        // 3. 外套/上衣 (Outerwear & Tops)
        let outerKeywords = [
            "jacket", "coat", "blazer", "cardigan", "sweater", "sweatshirt", "hoodie",
            "shirt", "trench", "overcoat", "parka", "poncho", "cloak",
            "vest", "jersey", "top", "blouse", "tee", "tank", "camisole",
            "pullover", "tunic", "waistcoat", "windbreaker", "bomber", "anorak", "cape",
            "uniform", "lab coat", "suit", "tuxedo", "bathrobe", "pajama", "nightgown",
            "sleeveless", "long sleeve", "short sleeve"
        ]
        if outerKeywords.contains(where: { id.contains($0) }) {
            return "外套"
        }
        
        // 4. 鞋子 (Shoes)
        let shoeKeywords = [
            "shoe", "boot", "sneaker", "sandal", "heel", "loafer", "clog", "moccasin",
            "slipper", "pump", "flat", "wedge", "platform", "stiletto", "oxford",
            "derby", "brogue", "espadrille", "flip-flop", "galoshes", "wellington", "footwear"
        ]
        if shoeKeywords.contains(where: { id.contains($0) }) {
            return "鞋子"
        }
        
        // 5. 袜子 (Socks & Hosiery)
        let sockKeywords = [
            "sock", "stocking", "hosiery", "tights", "legging", "pantyhose", "leg warmer", "anklet"
        ]
        if sockKeywords.contains(where: { id.contains($0) }) {
            return "袜子"
        }
        
        // 6. 包包 (Bags)
        let bagKeywords = [
            "bag", "purse", "handbag", "backpack", "tote", "satchel", "clutch", "wallet",
            "briefcase", "suitcase", "luggage", "pouch"
        ]
        if bagKeywords.contains(where: { id.contains($0) }) {
            return "包包"
        }
        
        // 7. 头饰/配饰 (Headwear & Accessories)
        let accessoryKeywords = [
            "hat", "cap", "bonnet", "beret", "beanie", "helmet", "headband", "hair",
            "bow", "ribbon", "scarf", "glove", "mitten", "belt", "tie", "umbrella",
            "glasses", "sunglasses", "jewelry", "necklace", "earring", "bracelet", "ring",
            "watch", "fan", "mask"
        ]
        if accessoryKeywords.contains(where: { id.contains($0) }) {
            return "配饰"
        }
        
        // 2. 裤子 (Pants & Shorts) - Put lower priority than skirts/dresses
        let pantKeywords = [
            "pant", "trouser", "jean", "denim", "short", "legging", "slack", "chino",
            "bottom", "culotte", "overall", "dungaree", "jumpsuit", "romper"
        ]
        if pantKeywords.contains(where: { id.contains($0) }) {
            return "裤子"
        }
        
        return nil
    }
    
    func standardizeCategory(_ input: String) -> String? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 映射表 (用户输入习惯 -> 标准分类)
        let mapping: [String: String] = [
            "jsk": "裙装", "op": "裙装", "sk": "裙装", "连衣裙": "裙装", "半身裙": "裙装", "背带裙": "裙装",
            "上衣": "外套", "衬衫": "外套", "内搭": "外套", "外套": "外套", "开衫": "外套", "大衣": "外套",
            "鞋": "鞋子", "鞋子": "鞋子", "靴子": "鞋子", "单鞋": "鞋子", "凉鞋": "鞋子",
            "袜": "袜子", "袜子": "袜子", "裤袜": "袜子", "丝袜": "袜子",
            "包": "包包", "包包": "包包", "手提包": "包包", "痛包": "包包",
            "裤": "裤子", "裤子": "裤子", "短裤": "裤子", "长裤": "裤子", "南瓜裤": "裤子",
            "头饰": "配饰", "发带": "配饰", "kc": "配饰", "bn": "配饰", "边夹": "配饰", "帽子": "配饰",
            "小物": "配饰", "配饰": "配饰", "项链": "配饰", "手袖": "配饰", "手套": "配饰", "假发": "配饰"
        ]
        
        // 1. 精确匹配
        if let standard = mapping[normalized] {
            return standard
        }
        
        // 2. 包含匹配 (e.g. "衬衫/雪纺" -> "外套")
        for (key, value) in mapping {
            if normalized.contains(key) {
                return value
            }
        }
        
        return nil
    }
    
    private func addWhiteBorder(to image: UIImage, borderWidth: CGFloat = 4.0) -> UIImage {
        // 1. Define rect
        let rect = CGRect(origin: .zero, size: image.size)
        
        // 2. Setup context
        UIGraphicsBeginImageContextWithOptions(rect.size, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // 3. Draw original image to get the mask/alpha channel
        image.draw(in: rect)
        
        // 4. Create a mask from the alpha channel
        // We want to stroke the edge of the non-transparent area.
        // A simple way is to draw the image slightly larger in white behind, but that blurs details.
        // Better approach for "Sticker Outline":
        // This is complex to do perfectly in CoreGraphics without external libraries.
        // Simplified approach: Draw white shadow/glow behind.
        
        // CLEAR Context for clean start
        context.clear(rect)
        
        // Draw white silhouette with shadow/stroke effect
        context.setShadow(offset: .zero, blur: borderWidth, color: UIColor.white.cgColor)
        // Draw multiple times to make it solid
        image.draw(in: rect)
        image.draw(in: rect)
        image.draw(in: rect)
        
        // Draw original image on top
        context.setShadow(offset: .zero, blur: 0, color: nil)
        image.draw(in: rect)
        
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }
    
    /// 修复缺失的 clothingName
    /// 遍历所有 CutoutItem，如果 clothingName 为空且 linkedClothingID 有效，则填充
    func fixMissingClothingNames(context: ModelContext) {
        do {
            // 只查找 linkedClothingID 不为空的
            // 注意：SwiftData 的 Predicate 支持有限，这里先取所有关联了的，然后在内存中过滤 clothingName 为空的
            // 或者直接遍历所有。由于数据量通常不大（几千个），直接遍历也是可以的。
            // 但为了效率，我们尽量用 Predicate。
            // Predicate 暂不支持 optional check for nil easily inside complex expressions sometimes, but let's try.
            // 简单点：获取所有 CutoutItem
            let descriptor = FetchDescriptor<CutoutItem>()
            let cutouts = try context.fetch(descriptor)
            
            // 获取所有 Clothing
            let clothingDescriptor = FetchDescriptor<Clothing>()
            let allClothing = try context.fetch(clothingDescriptor)
            let clothingMap = Dictionary(uniqueKeysWithValues: allClothing.map { ($0.id, $0) })
            
            var updatedCount = 0
            for cutout in cutouts {
                // 如果名字为空，或者即使不为空我们也想刷新一下（比如改名了）？
                // 用户说 "加载时...存下"，可能是为了补全。
                if let id = cutout.linkedClothingID, let clothing = clothingMap[id] {
                    if cutout.clothingName != clothing.name {
                        cutout.clothingName = clothing.name
                        updatedCount += 1
                    }
                }
            }
            
            if updatedCount > 0 {
                try context.save()
                print("Fixed missing clothing names for \(updatedCount) cutouts.")
            }
        } catch {
            print("Failed to fix missing clothing names: \(error)")
        }
    }
    
    /// 重新处理/重新抠图 (Task 2 功能)
    func reprocessItem(item: CutoutItem, with originalImage: UIImage, context: ModelContext) async throws {
        // 1. 删除旧图片文件
        ImageManager.shared.deleteImage(fileName: item.imagePath, context: context)
        
        // 2. 重新执行 processImage 的核心逻辑
        // 注意：这里我们手动执行，因为 processImage 会创建新 Item。我们想更新现有 Item。
        
        // Normalize
        let normalizedImage = normalizeOrientation(originalImage)
        
        // Cutout
        let (cutoutImage, _) = try await liftSubject(from: normalizedImage)
        
        // Border
        let borderedImage = addWhiteBorder(to: cutoutImage, borderWidth: 4.0)
        
        // Save new image
        // 使用 PNG 格式以保留透明通道
        guard let newPath = ImageManager.shared.saveImage(borderedImage, context: context, format: .png) else {
            throw CutoutError.processingFailed
        }
        
        // Update Item
        item.imagePath = newPath
        item.width = Double(borderedImage.size.width)
        item.height = Double(borderedImage.size.height)
        item.timestamp = Date() // Update timestamp to show as "fresh"
        
        // Try to refine category if it was "未分类"
        if item.category == "未分类" {
            if let newCat = try? await classifyImage(image: normalizedImage) {
                item.category = newCat
            }
        }
        
        try context.save()
    }
}
