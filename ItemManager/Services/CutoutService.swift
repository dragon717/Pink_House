
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
            print("Duplicate cutout found for hash: \(originalHash). Skipping processing.")
            
            // 如果传入了 clothing 且现有 item 未关联，则建立关联
            if let clothing = clothing, existingItem.linkedClothingID == nil {
                existingItem.linkedClothingID = clothing.id
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
        
        // 1. 尝试标准化传入的分类 (比如将 "JSK" -> "裙子")
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
                finalCategory = await classifyImage(cutoutImage)
            }
        } else {
            // 2. 如果未指定分类，则使用 Vision 识别
            finalCategory = await classifyImage(cutoutImage)
        }
        
        print("Auto-classified as: \(finalCategory)")
        
        // 3. 添加白边
        let borderedImage = addWhiteBorder(to: cutoutImage)
        
        // 4. 保存图片 (使用 ImageManager 保存为 HEIC 以获得更小的体积和透明度支持)
        // 0.8 的质量通常能提供非常好的视觉效果，且体积远小于 PNG
        guard let fileName = ImageManager.shared.saveImage(borderedImage, context: context, format: .heic(quality: 0.8)) else {
            throw CutoutError.processingFailed
        }
        
        // 5. 创建 CutoutItem
        let item = CutoutItem(
            originalImageHash: originalHash,
            category: finalCategory,
            imagePath: fileName,
            width: Double(borderedImage.size.width),
            height: Double(borderedImage.size.height),
            linkedClothingID: clothing?.id
        )
        
        context.insert(item)
        
        return item
    }
    
    /// 重新抠图：使用提供的原图更新现有的 CutoutItem
    /// - Parameters:
    ///   - item: 需要更新的 CutoutItem
    ///   - image: 原图
    func reprocessItem(item: CutoutItem, with image: UIImage, context: ModelContext) async throws {
        // 1. Normalize
        let normalizedImage = normalizeOrientation(image)
        
        // 2. 识别并抠图
        var cutoutImage: UIImage
        // var confidence: Float // 未使用
        
        do {
            (cutoutImage, _) = try await liftSubject(from: normalizedImage)
        } catch {
            print("Reprocess: Standard liftSubject failed: \(error). Trying fallback.")
            if let saliencyResult = try? await liftSubjectUsingSaliency(from: normalizedImage) {
                 cutoutImage = saliencyResult.0
            } else {
                throw error
            }
        }
        
        // 3. 添加白边
        let borderedImage = addWhiteBorder(to: cutoutImage)
        
        // 4. 保存新图片
        guard let fileName = ImageManager.shared.saveImage(borderedImage, context: context, format: .heic(quality: 0.8)) else {
            throw CutoutError.processingFailed
        }
        
        // 5. 更新 Item
        // 处理旧图片引用计数
        let oldPath = item.imagePath
        if oldPath != fileName {
            ImageManager.shared.deleteImage(fileName: oldPath, context: context)
        } else {
             // 如果文件名相同（内容哈希一致），saveImage 已经增加了引用计数，
             // 我们需要减少一次，因为我们并没有真正增加一个新的引用持有者（只是更新了同一个对象）
             // 或者更准确地说：
             // saveImage: refCount + 1
             // 我们即将用这个 fileName 替换 item.imagePath (如果是同一个值，则相当于没变)
             // 如果是同一个值，refCount 增加了 1，但实际上 item 还是那个 item，只引用一次。
             // 所以如果 fileName == oldPath，我们需要抵消 saveImage 带来的 +1。
             ImageManager.shared.deleteImage(fileName: fileName, context: context)
        }
        
        item.imagePath = fileName
        item.width = Double(borderedImage.size.width)
        item.height = Double(borderedImage.size.height)
        
        // 更新原图哈希
        if let data = image.jpegData(compressionQuality: 0.5) {
             item.originalImageHash = computeHash(data: data)
        }
        
        // 注意：不更新分类 (category)，保留用户可能的手动修改
    }
    
    // MARK: - Classification
    
    /// 将输入的分类字符串标准化为 6 大类
    /// - Parameter input: 用户输入或关联服饰的类型 (e.g. "JSK", "开衫")
    /// - Returns: 标准分类 (e.g. "裙子", "外套")，如果无法映射则返回 nil
    func standardizeCategory(_ input: String) -> String? {
        let standardCategories = ["裙子", "外套", "鞋子", "袜子", "玩偶", "小物"]
        if standardCategories.contains(input) { return input }
        
        let inputLower = input.lowercased()
        
        // 裙子
        if inputLower.contains("jsk") || inputLower.contains("op") || inputLower.contains("sk") || inputLower.contains("裙") || inputLower.contains("dress") || inputLower.contains("frock") || inputLower.contains("pinafore") {
            return "裙子"
        }
        // 外套
        if inputLower.contains("外套") || inputLower.contains("上衣") || inputLower.contains("开衫") || inputLower.contains("衬衫") || inputLower.contains("卫衣") || inputLower.contains("衣") || inputLower.contains("top") || inputLower.contains("shirt") || inputLower.contains("blouse") || inputLower.contains("cardigan") || inputLower.contains("内搭") {
            return "外套"
        }
        // 鞋子
        if inputLower.contains("鞋") || inputLower.contains("靴") {
            return "鞋子"
        }
        // 袜子
        if inputLower.contains("袜") {
            return "袜子"
        }
        // 玩偶
        if inputLower.contains("玩偶") || inputLower.contains("娃娃") || inputLower.contains("公仔") || inputLower.contains("手办") || inputLower.contains("toy") || inputLower.contains("doll") || inputLower.contains("毛绒") || inputLower.contains("熊") {
            return "玩偶"
        }
        // 小物
        if inputLower.contains("包") || inputLower.contains("饰") || inputLower.contains("帽") || inputLower.contains("夹") || inputLower.contains("带") || inputLower.contains("袖") || inputLower.contains("发") || inputLower.contains("小物") || inputLower.contains("acc") || inputLower.contains("项链") || inputLower.contains("戒指") || inputLower.contains("手链") || inputLower.contains("耳") {
            return "小物"
        }
        
        return nil
    }
    
    private func classifyImage(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "未分类" }
        
        let request = VNClassifyImageRequest()
        // Use latest revision for better accuracy if available
        // request.revision = VNClassifyImageRequestRevision2 
        
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            guard let observations = request.results else { return "未分类" }
            
            // Filter by confidence and map
            // We look at the top results
            // 降低置信度阈值，因为很多细分类别置信度可能不高
            let topResults = observations.filter { $0.confidence > 0.1 }.prefix(20)
            
            print("----- Image Classification Results -----")
            for obs in topResults {
                print("ID: \(obs.identifier), Confidence: \(obs.confidence)")
            }
            print("----------------------------------------")
            
            // 收集所有可能的分类
            var candidates: Set<String> = []
            
            for observation in topResults {
                // Check mapping
                if let category = mapIdentifierToCategory(observation.identifier) {
                    print("Mapped '\(observation.identifier)' to '\(category)'")
                    candidates.insert(category)
                }
            }
            
            // 根据优先级返回
            // 用户反馈：玩偶容易被误识别为小物，因此提高玩偶优先级
            if candidates.contains("玩偶") { return "玩偶" }
            if candidates.contains("裙子") { return "裙子" }
            if candidates.contains("外套") { return "外套" }
            if candidates.contains("鞋子") { return "鞋子" }
            if candidates.contains("袜子") { return "袜子" }
            if candidates.contains("小物") { return "小物" }
            
            // Fallback logic: if no specific category matched
            return "未分类"
            
        } catch {
            print("Classification failed: \(error)")
            return "未分类"
        }
    }
    
    private func mapIdentifierToCategory(_ identifier: String) -> String? {
        let id = identifier.lowercased()
        
        // 1. 优先匹配玩偶 (特征非常明显，容易被误判为小物或装饰品)
        let toyKeywords = [
            "toy", "doll", "plush", "teddy", "figurine", "action figure", "puppet",
            "marionette", "stuffed animal", "bear", "rabbit", "bunny", "cat", "dog",
            "animal", "mascot", "robot"
        ]
        // 排除真实的猫狗（如果是为了抠图，通常是玩偶，但 Vision 可能会识别出 'cat'）
        // 这里假设用户拍摄的是物品。
        if toyKeywords.contains(where: { id.contains($0) }) {
            return "玩偶"
        }
        
        // 2. 裙子 (Dresses & Skirts) - 扩展关键词
        // 很多洛丽塔裙子会被识别为 costume, gown, clothing 等
        let dressKeywords = [
            "dress", "skirt", "gown", "sarong", "kimono", "miniskirt", "overskirt",
            "sundress", "cocktail", "evening", "wedding", "ball",
            "chemise", "jumper", "pinafore", "frock", "kilt", "petticoat", "crinoline",
            "costume", "cosplay", "lolita", "victorian", "baroque", "rococo", // 风格词
            "clothing", "apparel", "garment", "wear", "vestment", "outfit", "robe" // 泛指词，通常归为裙子或外套，这里优先裙子尝试
        ]
        
        // 2.1 强匹配裙子 (Specific Types)
        let strongDressKeywords = [
            "dress", "skirt", "gown", "frock", "pinafore", "sarong", "kilt"
        ]
        if strongDressKeywords.contains(where: { id.contains($0) }) {
            return "裙子"
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
        
        // 6. 弱匹配裙子 (泛指词) - 放在具体分类之后，避免把“鞋子”识别成“Clothing”
        let weakDressKeywords = [
            "costume", "clothing", "apparel", "garment", "wear", "vestment", "textile", "fabric", "fashion"
        ]
        // 如果是这些词，且没命中鞋袜小物，大概率是主体衣物。
        // 在洛丽塔/JK制服语境下，主体衣物通常是裙子或套装（归裙子或外套）。
        // 我们可以暂时归为“裙子”（因为用户说裙子容易丢），或者根据是否包含 "top"/"shirt" 区分。
        // 这里做一个偏向性策略：如果是泛指 Clothing，优先归为裙子（因为裙子体积大，容易被识别为整体 Clothing）
        if weakDressKeywords.contains(where: { id.contains($0) }) {
            // 再次检查是否可能是外套？
            // 很难区分。但用户反馈裙子被分错，所以这里给裙子权重。
            return "裙子"
        }
        
        // 7. 小物 (Accessories) - 必须精确匹配
        // 只有明确识别为包、饰品等才算小物
        let accessoryKeywords = [
            "bag", "purse", "wallet", "hat", "cap", "scarf", "glove", "jewelry",
            "necklace", "ring", "earring", "bracelet", "glasses", "sunglasses",
            "watch", "umbrella", "tie", "belt", "accessory", "keychain", "hair",
            "pin", "brooch", "headband", "bow", "ribbon", "fan", "mask", "wig",
            "crown", "tiara", "helmet", "bonnet", "beret", "fedora", "cowboy hat",
            "sombrero", "backpack", "satchel", "tote", "handbag", "clutch", "briefcase",
            "luggage", "suitcase"
        ]
        if accessoryKeywords.contains(where: { id.contains($0) }) {
            return "小物"
        }
        
        return nil
    }
    
    // MARK: - Image Processing
    
    /// 备用抠图引擎：基于显著性检测 (Saliency)
    /// 当标准的主体识别失败时，使用此方法尝试提取画面中最显著的物体
    private func liftSubjectUsingSaliency(from image: UIImage) async throws -> (UIImage, Float) {
        guard let cgImage = image.cgImage else { throw CutoutError.processingFailed }
        
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        // request.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision1
        
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        
        guard let result = request.results?.first else {
             throw CutoutError.noSubjectFound
        }
        
        // Saliency returns a heatmap. We need to threshold it to create a mask.
        let pixelBuffer = result.pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Resize mask to match image size
        let scaleX = CGFloat(cgImage.width) / CGFloat(CVPixelBufferGetWidth(result.pixelBuffer))
        let scaleY = CGFloat(cgImage.height) / CGFloat(CVPixelBufferGetHeight(result.pixelBuffer))
        
        let resizedMask = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Thresholding: Convert soft heatmap to hard binary mask
        // Values usually range 0.0-1.0. Let's pick 0.3 as threshold
        let thresholdFilter = CIFilter.colorMatrix()
        thresholdFilter.inputImage = resizedMask
        // R, G, B, A vectors.
        // We want to boost values > 0.3 to 1.0, and < 0.3 to 0.0.
        // Simplified approach: Contrast boost + Step
        
        // Better approach using CIColorKernel or built-in filters chain
        // 1. Clamp to 0-1 (already is)
        // 2. Apply a steep s-curve or step function.
        // Let's use CIColorControls to maximize contrast
        let contrast = resizedMask.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 10.0,
            kCIInputBrightnessKey: -0.5 // Shift center
        ])
        
        // Use the mask to crop original
        let originalCI = CIImage(cgImage: cgImage)
        
        // Apply mask to alpha channel
        let masked = originalCI.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: contrast,
            kCIInputBackgroundImageKey: CIImage.empty()
        ])
        
        let context = CIContext()
        guard let resultCG = context.createCGImage(masked, from: originalCI.extent) else {
            throw CutoutError.processingFailed
        }
        
        // Saliency is less precise, so we give it a lower confidence score but enough to pass
        return (UIImage(cgImage: resultCG), 0.6)
    }

    // MARK: - Advanced Processing (RMBG)
    
    private func liftSubjectUsingRMBG(from image: UIImage) async throws -> (UIImage, Float) {
        // Try to use RMBG Service
        // This requires RMBG14.mlpackage to be present and compiled
        
        // We use a safe check. If the model throws "missing", we fallback.
        // Since we have a dummy class, it will "run" but return dummy data if not replaced.
        // But for real usage, we assume user replaced it.
        
        do {
            let result = try await RMBGService.shared.process(image: image)
            // RMBG usually works well, we give it high confidence
            return (result, 0.98)
        } catch {
            print("RMBG failed: \(error)")
            throw error
        }
    }

    /// 智能抠图引擎
    private func liftSubject(from image: UIImage) async throws -> (UIImage, Float) {
        // Strategy: 
        // 1. Try RMBG-1.4 (SOTA) if available
        // 2. Fallback to Apple Vision (Native)
        
        // Check if we really have RMBG model (heuristic: check if file exists or just try)
        // For now, let's try calling it. If it fails (e.g. dummy model returns empty), we continue.
        
        do {
             // Uncomment this line when you have the real model!
             // return try await liftSubjectUsingRMBG(from: image)
             
             // For now, stick to Vision as primary until user installs model
             throw CutoutError.processingFailed 
        } catch {
            // Fallthrough to Vision
        }
        
        guard let cgImage = image.cgImage else { throw CutoutError.processingFailed }
        guard let cgImage = image.cgImage else { throw CutoutError.processingFailed }
        
        if #available(iOS 17.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            
            try handler.perform([request])
            
            guard let result = request.results?.first else {
                throw CutoutError.noSubjectFound
            }
            
            // 获取 Mask
            let maskPixelBuffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
            
            let maskImage = maskPixelBuffer
            
            let ciImage = CIImage(cvPixelBuffer: maskImage)
            let context = CIContext()
            guard let maskedCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                throw CutoutError.processingFailed
            }
            
            let finalImage = UIImage(cgImage: maskedCGImage)
            
            // 简单估算置信度 (Vision API 不直接返回整体置信度，这里假设只要识别到了就是高置信度，或者根据 mask 覆盖率等)
            // 实际应用中可能需要更复杂的逻辑
            return (finalImage, 0.95)
            
        } else {
            // Fallback for older iOS versions (iOS 15+)
            // 使用 Person Segmentation 作为降级方案
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])
            
            guard let result = request.results?.first else {
                throw CutoutError.noSubjectFound
            }
            
            let mask = result.pixelBuffer
            // ... 处理 Mask 并应用到原图 ...
            // 这里为了简化，仅在 iOS 17+ 完整实现，旧版本抛出错误或返回原图
            // 实际项目中应实现完整降级
             throw CutoutError.processingFailed
        }
    }
    
    /// 白边生成
    private func addWhiteBorder(to image: UIImage, borderSize: CGFloat = 3.0) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let ciImage = CIImage(cgImage: cgImage)
        
        // 1. 提取 Alpha 通道
        let alpha = ciImage.applyingFilter("CIMaskToAlpha")
        
        // 2. 膨胀 (Morphology Maximum)
        let dilate = alpha.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: borderSize
        ])
        
        // 3. 将膨胀后的区域变成白色
        // 我们可以将膨胀后的 Alpha 作为 Mask，用白色填充
        let white = CIImage(color: .white)
        let borderMask = dilate
        
        let whiteBorder = white.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: borderMask,
            kCIInputBackgroundImageKey: CIImage.empty() // 透明背景
        ])
        
        // 4. 将原图叠加在白边上
        let composite = ciImage.composited(over: whiteBorder)
        
        let context = CIContext()
        if let resultCGImage = context.createCGImage(composite, from: composite.extent) {
            return UIImage(cgImage: resultCGImage)
        }
        
        return image
    }
    
    private func computeHash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
