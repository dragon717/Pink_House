//
//  AIDeduplicationService.swift
//  裙子股市 - AI语义去重服务
//
//  使用MiniMax 2.5进行文本分析，Qwen-3-VL进行视觉去重
//

import Foundation
import SwiftData
import UIKit

/// AI去重服务 - 解决同商品不同文案的识别问题
@MainActor
final class AIDeduplicationService {
    static let shared = AIDeduplicationService()
    
    // MARK: - 配置
    
    /// MiniMax API配置
    private let miniMaxAPIKey = "YOUR_MINIMAX_API_KEY"
    private let miniMaxBaseURL = "https://api.minimax.chat/v1/text/chatcompletion_v2"
    
    /// Qwen-VL API配置
    private let qwenAPIKey = "YOUR_QWEN_API_KEY"
    private let qwenBaseURL = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    
    /// 语义相似度阈值
    private let semanticSimilarityThreshold = 0.85
    
    /// 视觉相似度阈值
    private let visualSimilarityThreshold = 0.90
    
    private init() {}
    
    // MARK: - 主入口
    
    /// 对新抓取的商品进行AI去重处理
    /// 流程：1.内存索引检查 -> 2.文本清洗 -> 3.语义哈希生成 -> 4.相似度检查 -> 5.视觉验证（可选）
    func processNewItem(_ item: LolitaItem) async -> DeduplicationResult {
        print("🤖 AI处理商品: \(item.rawTitle)")
        
        // 0. 首先检查内存索引（O(1)快速去重）
        if let cachedDuplicate = await checkCacheForDuplicate(item) {
            print("📦 内存索引命中重复: \(cachedDuplicate.platformID)")
            // 更新现有记录的价格
            await updateExistingItem(cachedDuplicate, with: item)
            return .duplicate(existingItemID: cachedDuplicate.platformID)
        }
        
        // 1. 使用MiniMax进行文本清洗和结构化
        let structuredData = await analyzeTextWithMiniMax(item)
        
        // 更新商品信息
        item.cleanedName = structuredData.name
        item.brand = structuredData.brand
        item.itemType = structuredData.itemType
        item.color = structuredData.color
        item.sentimentScore = structuredData.sentimentScore
        item.isLolitaRelated = structuredData.isLolitaRelated
        
        // 2. 生成语义哈希
        let semanticHash = generateSemanticHash(from: structuredData)
        item.semanticHash = semanticHash
        
        // 3. 再次检查内存索引（使用生成的语义哈希）
        let cacheDuplicates = SkirtIndexCache.shared.findBySemanticHash(semanticHash)
            .filter { $0.platformID != item.platformID && !$0.isDeleted }
        
        if let cachedItem = cacheDuplicates.first {
            print("📦 语义哈希命中重复: \(cachedItem.platformID)")
            // 更新缓存和数据库
            await updateCachedItem(cachedItem, with: item)
            return .duplicate(existingItemID: cachedItem.platformID)
        }
        
        // 4. 检查是否已存在相似商品（数据库查询作为fallback）
        let existingItems = await findSimilarItems(semanticHash: semanticHash, item: item)
        
        if let similarItem = existingItems.first {
            // 5. 如果语义相似，进行视觉验证
            if let imageURL = item.mainImageURL {
                let isVisualMatch = await verifyVisualSimilarity(
                    newImageURL: imageURL,
                    existingItem: similarItem
                )
                
                if isVisualMatch {
                    // 确定是同一商品，合并信息
                    await mergeItem(item, into: similarItem)
                    // 更新内存索引
                    SkirtIndexCache.shared.updateCache(with: similarItem)
                    return .duplicate(existingItemID: similarItem.platformID)
                }
            }
            
            // 语义相似但视觉不同，可能是不同颜色/版本
            return .similarButDifferent(similarItemID: similarItem.platformID)
        }
        
        // 新商品 - 添加到内存索引
        SkirtIndexCache.shared.updateCache(with: item)
        return .newItem
    }
    
    // MARK: - 内存索引快速去重
    
    /// 检查内存索引中是否存在重复 - O(1)复杂度
    private func checkCacheForDuplicate(_ item: LolitaItem) async -> SkirtIndexEntry? {
        // 1. 检查PlatformID（完全相同的商品）
        if let existing = SkirtIndexCache.shared.findByPlatformID(item.platformID) {
            return existing
        }
        
        // 2. 如果已有语义哈希，检查语义哈希
        if let semanticHash = item.semanticHash, !semanticHash.isEmpty {
            let duplicates = SkirtIndexCache.shared.findBySemanticHash(semanticHash)
                .filter { $0.platformID != item.platformID && !$0.isDeleted }
            return duplicates.first
        }
        
        return nil
    }
    
    /// 更新内存索引中的现有商品
    private func updateCachedItem(_ cachedItem: SkirtIndexEntry, with newItem: LolitaItem) async {
        guard let context = SkirtMarketPersistence.shared.mainContext else { return }
        
        // 查询数据库中的完整记录（使用字符串匹配避免谓词捕获问题）
        let targetPlatformID = cachedItem.platformID
        let descriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { item in
                item.platformID == targetPlatformID
            }
        )
        
        if let existingItem = try? context.fetch(descriptor).first {
            // 保留更低的价格
            if newItem.currentPrice < existingItem.currentPrice {
                existingItem.currentPrice = newItem.currentPrice
            }
            existingItem.lastUpdated = Date()
            try? context.save()
            
            // 更新内存索引
            SkirtIndexCache.shared.updateCache(with: existingItem)
        }
    }
    
    /// 更新现有商品信息
    private func updateExistingItem(_ cachedItem: SkirtIndexEntry, with newItem: LolitaItem) async {
        guard let context = SkirtMarketPersistence.shared.mainContext else { return }
        
        // 使用字符串匹配避免谓词捕获问题
        let targetPlatformID = cachedItem.platformID
        let descriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { item in
                item.platformID == targetPlatformID
            }
        )
        
        if let existingItem = try? context.fetch(descriptor).first {
            // 更新价格（保留最低价格）
            if newItem.currentPrice < existingItem.currentPrice {
                existingItem.currentPrice = newItem.currentPrice
            }
            existingItem.lastUpdated = Date()
            try? context.save()
            
            // 更新内存索引
            SkirtIndexCache.shared.updateCache(with: existingItem)
        }
    }
    
    /// 批量处理商品（用于后台任务）
    /// 优化流程：先使用内存缓存快速去重，再对剩余商品调用AI分析
    func processItemsBatch(_ items: [LolitaItem]) async -> BatchDeduplicationResult {
        print("🔄 开始批量处理 \(items.count) 个商品...")
        
        // 0. 确保索引缓存已刷新
        await SkirtIndexCache.shared.refreshCache()
        
        var results: [DeduplicationResult] = []
        var duplicates = 0
        var newItems = 0
        var cacheHits = 0
        var aiProcessed = 0
        
        // 第一阶段：使用内存缓存快速去重（O(1)复杂度）
        var itemsNeedAIAnalysis: [LolitaItem] = []
        
        for item in items {
            // 快速检查内存索引
            if let cachedDuplicate = await checkCacheForDuplicate(item) {
                // 缓存命中，直接标记为重复
                await updateExistingItem(cachedDuplicate, with: item)
                results.append(.duplicate(existingItemID: cachedDuplicate.platformID))
                duplicates += 1
                cacheHits += 1
                continue
            }
            
            // 未命中，需要AI分析
            itemsNeedAIAnalysis.append(item)
        }
        
        print("📊 快速去重完成: \(cacheHits) 个缓存命中, \(itemsNeedAIAnalysis.count) 个需要AI分析")
        
        // 第二阶段：对剩余商品调用AI分析
        for item in itemsNeedAIAnalysis {
            let result = await processNewItem(item)
            results.append(result)
            aiProcessed += 1
            
            switch result {
            case .duplicate:
                duplicates += 1
            case .newItem:
                newItems += 1
            case .similarButDifferent:
                newItems += 1  // 相似但不同也算新商品
            }
            
            // 添加延迟避免API限流
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        }
        
        print("✅ 批量处理完成: 总计\(items.count)个, 重复\(duplicates)个, 新增\(newItems)个, 缓存命中\(cacheHits)个")
        
        return BatchDeduplicationResult(
            totalProcessed: items.count,
            duplicatesFound: duplicates,
            newItems: newItems,
            cacheHits: cacheHits,
            aiProcessed: aiProcessed,
            details: results
        )
    }
    
    // MARK: - MiniMax文本分析
    
    /// 使用MiniMax 2.5分析商品文本
    private func analyzeTextWithMiniMax(_ item: LolitaItem) async -> StructuredItemData {
        let prompt = createMiniMaxPrompt(item)
        
        do {
            let response = try await callMiniMaxAPI(prompt: prompt)
            return parseMiniMaxResponse(response)
        } catch {
            print("❌ MiniMax API调用失败: \(error)")
            // 返回基于规则的解析结果作为fallback
            return fallbackTextAnalysis(item)
        }
    }
    
    /// 创建MiniMax Prompt
    private func createMiniMaxPrompt(_ item: LolitaItem) -> String {
        return """
        你是一个Lolita时尚专家。请分析以下商品信息，提取结构化数据。
        
        商品标题：\(item.rawTitle)
        平台：\(item.platform.rawValue)
        价格：\(item.currentPrice)元
        
        请提取以下信息并以JSON格式返回：
        {
            "name": "商品标准化名称（去除无关词汇）",
            "brand": "品牌名称（如AP、Baby、古典玩偶等）",
            "itemType": "商品类型（JSK/OP/SK/小物/包/鞋/其他）",
            "color": "颜色",
            "isLolitaRelated": true/false,
            "sentimentKeywords": ["情绪关键词，如'急出'、'退坑'、'求购'等"],
            "urgencyLevel": "急迫程度（high/medium/low）",
            "isForSale": true/false
        }
        
        注意：
        1. 如果内容是"求购"而非"出售"，isForSale设为false
        2. 如果不是Lolita相关商品，isLolitaRelated设为false
        3. 品牌名称请标准化（如"Angelic Pretty"统一为"AP"）
        """
    }
    
    /// 调用MiniMax API
    private func callMiniMaxAPI(prompt: String) async throws -> String {
        let requestBody: [String: Any] = [
            "model": "abab6.5s-chat",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 500
        ]
        
        guard let url = URL(string: miniMaxBaseURL) else {
            throw AIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(miniMaxAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.apiError("HTTP错误")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }
        
        return content
    }
    
    /// 解析MiniMax响应
    private func parseMiniMaxResponse(_ response: String) -> StructuredItemData {
        // 尝试从响应中提取JSON
        if let jsonData = extractJSON(from: response)?.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode(MiniMaxResponse.self, from: jsonData)
                
                return StructuredItemData(
                    name: decoded.name,
                    brand: decoded.brand,
                    itemType: LolitaItemType(rawValue: decoded.itemType),
                    color: decoded.color,
                    isLolitaRelated: decoded.isLolitaRelated,
                    sentimentScore: calculateSentimentScore(from: decoded.sentimentKeywords, urgency: decoded.urgencyLevel),
                    isForSale: decoded.isForSale
                )
            } catch {
                print("⚠️ JSON解析失败: \(error)")
            }
        }
        
        // Fallback：返回空数据
        return StructuredItemData()
    }
    
    /// 从文本中提取JSON
    private func extractJSON(from text: String) -> String? {
        // 查找JSON代码块
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: startRange.upperBound..<text.endIndex) {
            return String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 查找普通JSON对象
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }
        
        return nil
    }
    
    /// 计算情绪分数
    private func calculateSentimentScore(from keywords: [String], urgency: String) -> Double {
        var score = 0.0
        
        // 急出关键词（负值）
        let urgentKeywords = ["急出", "退坑", "刀出", "求回血", "大刀"]
        // 求购关键词（正值，说明需求旺盛）
        let demandKeywords = ["求购", "收", "蹲", "求"]
        
        for keyword in keywords {
            if urgentKeywords.contains(where: { keyword.contains($0) }) {
                score -= 0.3
            }
            if demandKeywords.contains(where: { keyword.contains($0) }) {
                score += 0.3
            }
        }
        
        // 根据急迫程度调整
        switch urgency {
        case "high":
            score -= 0.4
        case "medium":
            score -= 0.2
        default:
            break
        }
        
        // 限制在-1到1之间
        return max(-1.0, min(1.0, score))
    }
    
    /// Fallback文本分析（基于规则）
    private func fallbackTextAnalysis(_ item: LolitaItem) -> StructuredItemData {
        let title = item.rawTitle.lowercased()
        
        // 品牌识别
        var brand: String?
        let brandKeywords = [
            "ap": "AP",
            "angelic pretty": "AP",
            "baby": "Baby",
            "bbd": "Baby",
            "anp": "ANP",
            "alice and the pirates": "ANP",
            "iw": "IW",
            "innocent world": "IW",
            "vm": "VM",
            "victorian maiden": "VM",
            "mm": "MM",
            "mary magdalene": "MM",
            "jej": "JeJ"
        ]
        
        for (keyword, brandName) in brandKeywords {
            if title.contains(keyword) {
                brand = brandName
                break
            }
        }
        
        // 类型识别
        var itemType: LolitaItemType?
        if title.contains("jsk") {
            itemType = .jsk
        } else if title.contains("op") {
            itemType = .op
        } else if title.contains("sk") {
            itemType = .sk
        }
        
        // 颜色识别
        var color: String?
        let colors = ["黑", "白", "粉", "蓝", "红", "紫", "绿", "黄", "生成", " sax ", "若草"]
        for c in colors {
            if title.contains(c) {
                color = c.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // 情绪分析
        var sentimentScore = 0.0
        if title.contains("急出") || title.contains("退坑") {
            sentimentScore = -0.5
        }
        
        // 是否出售
        let isForSale = !title.contains("求购") && !title.contains("收")
        
        return StructuredItemData(
            name: item.rawTitle,
            brand: brand,
            itemType: itemType,
            color: color,
            isLolitaRelated: true,
            sentimentScore: sentimentScore,
            isForSale: isForSale
        )
    }
    
    // MARK: - 语义哈希
    
    /// 生成语义哈希
    private func generateSemanticHash(from data: StructuredItemData) -> String {
        var components: [String] = []
        
        if let brand = data.brand {
            components.append(brand)
        }
        
        if let name = data.name {
            // 提取核心名称（去除尺寸、价格等无关信息）
            let coreName = extractCoreName(name)
            components.append(coreName)
        }
        
        if let type = data.itemType {
            components.append(type.rawValue)
        }
        
        if let color = data.color {
            components.append(color)
        }
        
        // 如果信息不足，使用名称的简化版本
        if components.count < 2, let name = data.name {
            components.append(String(name.prefix(20)))
        }
        
        return components.joined(separator: "_").lowercased()
    }
    
    /// 提取核心名称
    private func extractCoreName(_ name: String) -> String {
        // 去除常见无关词汇
        var coreName = name
        let noiseWords = ["出", "收", "求", "全新", "二手", "九成新", "刀出", "急出", "退坑"]
        for word in noiseWords {
            coreName = coreName.replacingOccurrences(of: word, with: "")
        }
        return coreName.trimmingCharacters(in: .whitespaces).prefix(30).lowercased()
    }
    
    // MARK: - 相似度检查
    
    /// 查找相似商品
    private func findSimilarItems(semanticHash: String, item: LolitaItem) async -> [LolitaItem] {
        guard let context = SkirtMarketPersistence.shared.mainContext else { return [] }
        
        // 1. 精确匹配语义哈希（简化谓词，避免复杂表达式）
        let exactDescriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate {
                $0.semanticHash == semanticHash
            }
        )
        
        // 在内存中过滤精确匹配结果（排除自己、已删除的）
        if let exactMatches = try? context.fetch(exactDescriptor) {
            let filteredMatches = exactMatches.filter { $0.platformID != item.platformID && !$0.isDeleted }
            if !filteredMatches.isEmpty {
                return filteredMatches
            }
        }
        
        // 2. 模糊匹配：检查名称相似度
        // 获取所有商品后在内存中过滤（SwiftData谓词有较多限制）
        let allDescriptor = FetchDescriptor<LolitaItem>()
        
        guard let allItems = try? context.fetch(allDescriptor) else { return [] }
        
        // 在内存中过滤：未删除、排除自己、7天内的数据、计算相似度
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)  // 7天前
        let similarItems = allItems.filter { existingItem in
            // 只查未删除的
            guard !existingItem.isDeleted else { return false }
            // 排除自己
            guard existingItem.platformID != item.platformID else { return false }
            // 只查7天内的数据
            guard existingItem.lastUpdated > cutoffDate else { return false }
            // 计算相似度
            let similarity = calculateTextSimilarity(
                item.cleanedName ?? item.rawTitle,
                existingItem.cleanedName ?? existingItem.rawTitle
            )
            return similarity > semanticSimilarityThreshold
        }
        
        return similarItems
    }
    
    /// 计算文本相似度（编辑距离）
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let s1 = text1.lowercased()
        let s2 = text2.lowercased()
        
        // 如果完全相同
        if s1 == s2 { return 1.0 }
        
        // 计算编辑距离
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        
        guard maxLength > 0 else { return 0 }
        
        return 1.0 - Double(distance) / Double(maxLength)
    }
    
    /// Levenshtein距离算法
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let arr1 = Array(s1)
        let arr2 = Array(s2)
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: arr2.count + 1), count: arr1.count + 1)
        
        for i in 0...arr1.count {
            matrix[i][0] = i
        }
        
        for j in 0...arr2.count {
            matrix[0][j] = j
        }
        
        for i in 1...arr1.count {
            for j in 1...arr2.count {
                let cost = arr1[i-1] == arr2[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // 删除
                    matrix[i][j-1] + 1,      // 插入
                    matrix[i-1][j-1] + cost  // 替换
                )
            }
        }
        
        return matrix[arr1.count][arr2.count]
    }
    
    // MARK: - 视觉验证
    
    /// 使用Qwen-3-VL验证视觉相似度
    private func verifyVisualSimilarity(newImageURL: String, existingItem: LolitaItem) async -> Bool {
        // 如果现有商品没有图片，跳过视觉验证
        guard let existingImageURL = existingItem.mainImageURL else {
            return true  // 信任语义匹配
        }
        
        do {
            // 下载图片
            guard let newImage = try? await downloadImage(from: newImageURL),
                  let existingImage = try? await downloadImage(from: existingImageURL) else {
                return false
            }
            
            // 调用Qwen-VL进行视觉比对
            let isMatch = try await callQwenVLForComparison(newImage: newImage, existingImage: existingImage)
            return isMatch
            
        } catch {
            print("❌ 视觉验证失败: \(error)")
            return false
        }
    }
    
    /// 下载图片
    private func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let image = UIImage(data: data) else {
            throw AIError.invalidImage
        }
        
        return image
    }
    
    /// 调用Qwen-VL进行图片比对
    private func callQwenVLForComparison(newImage: UIImage, existingImage: UIImage) async throws -> Bool {
        // 将图片转为Base64
        guard let newImageData = newImage.jpegData(compressionQuality: 0.8),
              let existingImageData = existingImage.jpegData(compressionQuality: 0.8) else {
            throw AIError.invalidImage
        }
        
        let newImageBase64 = newImageData.base64EncodedString()
        let existingImageBase64 = existingImageData.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "model": "qwen-vl-max",
            "input": [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "这两张图片展示的是同一件Lolita裙子吗？请回答'是'或'否'，并简要说明理由。"
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/jpeg;base64,\(newImageBase64)"
                                ]
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/jpeg;base64,\(existingImageBase64)"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        guard let url = URL(string: qwenBaseURL) else {
            throw AIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(qwenAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.apiError("HTTP错误")
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let choices = output["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }
        
        // 判断是否为同一商品
        return content.contains("是") && !content.contains("否")
    }
    
    // MARK: - 商品合并
    
    /// 合并重复商品信息
    private func mergeItem(_ newItem: LolitaItem, into existingItem: LolitaItem) async {
        // 保留更低的价格
        if newItem.currentPrice < existingItem.currentPrice {
            existingItem.currentPrice = newItem.currentPrice
        }
        
        // 更新其他信息（如果新数据更完整）
        if existingItem.mainImageURL == nil {
            existingItem.mainImageURL = newItem.mainImageURL
        }
        
        // 更新最后修改时间
        existingItem.lastUpdated = Date()
        
        // 标记新商品为删除（软删除）
        newItem.isDeleted = true
        newItem.deletedAt = Date()
        newItem.deleteReason = "重复商品，已合并到 \(existingItem.platformID)"
        
        // 保存
        if let context = SkirtMarketPersistence.shared.mainContext {
            try? context.save()
        }
        
        print("🔄 合并商品: \(newItem.platformID) -> \(existingItem.platformID)")
    }
}

// MARK: - 数据模型

/// 结构化商品数据
struct StructuredItemData {
    var name: String?
    var brand: String?
    var itemType: LolitaItemType?
    var color: String?
    var isLolitaRelated: Bool
    var sentimentScore: Double
    var isForSale: Bool
    
    init(
        name: String? = nil,
        brand: String? = nil,
        itemType: LolitaItemType? = nil,
        color: String? = nil,
        isLolitaRelated: Bool = true,
        sentimentScore: Double = 0,
        isForSale: Bool = true
    ) {
        self.name = name
        self.brand = brand
        self.itemType = itemType
        self.color = color
        self.isLolitaRelated = isLolitaRelated
        self.sentimentScore = sentimentScore
        self.isForSale = isForSale
    }
}

/// MiniMax API响应结构
struct MiniMaxResponse: Codable {
    let name: String
    let brand: String?
    let itemType: String
    let color: String?
    let isLolitaRelated: Bool
    let sentimentKeywords: [String]
    let urgencyLevel: String
    let isForSale: Bool
}

/// 去重结果
enum DeduplicationResult {
    case newItem                    // 新商品
    case duplicate(existingItemID: String)  // 重复商品
    case similarButDifferent(similarItemID: String)  // 相似但不同
}

/// 批量去重结果
struct BatchDeduplicationResult {
    let totalProcessed: Int
    let duplicatesFound: Int
    let newItems: Int
    let cacheHits: Int           // 缓存命中数（新增）
    let aiProcessed: Int         // AI实际处理数（新增）
    let details: [DeduplicationResult]
    
    /// 缓存命中率
    var cacheHitRate: Double {
        guard totalProcessed > 0 else { return 0 }
        return Double(cacheHits) / Double(totalProcessed)
    }
    
    /// AI调用节省率
    var aiSavingsRate: Double {
        guard totalProcessed > 0 else { return 0 }
        return Double(cacheHits) / Double(totalProcessed)
    }
}

/// AI错误类型
enum AIError: Error {
    case invalidURL
    case apiError(String)
    case invalidResponse
    case invalidImage
    case rateLimited
}

// MARK: - 使用示例

/*
// 在任务执行流程中集成AI去重
func processFetchedItems(_ items: [LolitaItem]) async {
    for item in items {
        let result = await AIDeduplicationService.shared.processNewItem(item)
        
        switch result {
        case .newItem:
            print("✅ 新商品: \(item.displayName)")
        case .duplicate(let existingID):
            print("🔄 重复商品，已合并到: \(existingID)")
        case .similarButDifferent(let similarID):
            print("⚠️ 相似商品: \(similarID)")
        }
    }
}

// 批量处理
func batchProcessItems(_ items: [LolitaItem]) async {
    let result = await AIDeduplicationService.shared.processItemsBatch(items)
    print("处理完成: \(result.totalProcessed) 个商品")
    print("发现重复: \(result.duplicatesFound) 个")
    print("新增商品: \(result.newItems) 个")
}
*/
