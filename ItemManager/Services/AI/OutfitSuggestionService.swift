import Foundation
import SwiftData

// MARK: - 搭配建议响应结构
/// AI返回的搭配建议数据结构
struct OutfitSuggestionResponse {
    let description: String
    let selectedItemIDs: [UUID]
    let style: String
    let occasion: String
    let reasoning: String
}

// MARK: - 搭配建议服务
/// 处理AI搭配建议的完整流程：从LLM响应到创建Outfit
class OutfitSuggestionService {
    static let shared = OutfitSuggestionService()

    private init() {}

    // MARK: - 主要流程

    /// 处理用户的搭配请求
    /// - Parameters:
    ///   - query: 用户输入（如"帮我搭配一套粉色系的出门装"）
    ///   - clothings: 用户衣橱中的所有裙装
    ///   - context: ModelContext用于数据库操作
    /// - Returns: 推荐的裙装列表和响应文本
    func processOutfitRequest(
        query: String,
        clothings: [Clothing],
        context: ModelContext
    ) async throws -> ([Clothing], String, String, String) {
        // 1. 获取衣橱上下文
        let wardrobeContext = WardrobeContextManager.shared.generateWardrobeSummary(clothings: clothings)

        // 2. 调用AI获取搭配建议
        let suggestion = try await fetchOutfitSuggestionFromAI(
            query: query,
            wardrobeContext: wardrobeContext,
            clothings: clothings
        )

        // 3. 获取推荐的裙装
        let selectedClothings = clothings.filter { clothing in
            suggestion.selectedItemIDs.contains(clothing.id)
        }

        guard !selectedClothings.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }

        // 4. 构建响应文本
        let responseText = buildResponseText(suggestion: suggestion, clothings: selectedClothings)

        return (selectedClothings, responseText, suggestion.style, suggestion.occasion)
    }

    /// 快速创建搭配（无需AI，基于规则）
    /// - Parameters:
    ///   - style: 风格（甜美/优雅/哥特等）
    ///   - occasion: 场合（日常/约会/茶会等）
    ///   - clothings: 用户衣橱
    ///   - context: ModelContext
    /// - Returns: 推荐的裙装列表
    func createQuickOutfit(
        style: String,
        occasion: String,
        clothings: [Clothing],
        context: ModelContext
    ) async throws -> [Clothing] {
        // 按类别分组
        let grouped = Dictionary(grouping: clothings) { clothing -> String in
            // 根据名称判断类别
            let name = clothing.name.lowercased()
            if name.contains("jsk") || name.contains("op") || name.contains("sk") || name.contains("裙") {
                return "裙装"
            } else if name.contains("外套") || name.contains("开衫") {
                return "外套"
            } else if name.contains("鞋") || name.contains("靴") {
                return "鞋子"
            } else {
                return "配饰"
            }
        }
        
        // 选择搭配物品（每类选一个）
        var result: [Clothing] = []
        
        // 优先选择裙装
        if let dresses = grouped["裙装"], !dresses.isEmpty {
            result.append(dresses.randomElement()!)
        }
        
        // 选择上衣/外套
        if let tops = grouped["外套"], !tops.isEmpty {
            result.append(tops.randomElement()!)
        }
        
        // 选择鞋子
        if let shoes = grouped["鞋子"], !shoes.isEmpty {
            result.append(shoes.randomElement()!)
        }
        
        // 选择配饰（最多2个）
        if let accessories = grouped["配饰"], !accessories.isEmpty {
            result.append(contentsOf: accessories.prefix(2))
        }
        
        // 如果按名称分类没有结果，随机选择2-4件
        if result.count < 2 {
            result = Array(clothings.shuffled().prefix(min(4, clothings.count)))
        }
        
        guard result.count >= 2 else {
            throw OutfitSuggestionError.insufficientItems
        }
        
        return result
    }

    // MARK: - 私有方法

    /// 从AI获取搭配建议
    private func fetchOutfitSuggestionFromAI(
        query: String,
        wardrobeContext: String,
        clothings: [Clothing]
    ) async throws -> OutfitSuggestionResponse {
        // 构建Prompt
        let prompt = buildOutfitPrompt(query: query, wardrobeContext: wardrobeContext)

        // 调用AI服务
        let aiMessage = await PetAIService.shared.sendMessage(prompt, enableVoice: false)

        // 解析响应
        return try parseAIResponse(aiMessage.text, clothings: clothings)
    }

    /// 构建搭配专用Prompt
    private func buildOutfitPrompt(query: String, wardrobeContext: String) -> String {
        return """
        你是主人的专业Lo裙搭配师，精通Lolita时尚穿搭。

        用户需求：\(query)

        衣橱数据：
        \(wardrobeContext)

        请从【可用单品列表】中选择2-4件单品进行搭配，要求：
        1. 考虑颜色协调性（同色系或互补色）
        2. 考虑场合适配性
        3. 优先选择JSK/OP作为主体
        4. 搭配理由要像闺蜜一样亲切自然

        请严格按以下JSON格式返回（不要包含其他内容）：
        {
          "description": "搭配描述（30字以内，带喵~）",
          "selectedItemIDs": ["物品ID1", "物品ID2", ...],
          "style": "甜美/优雅/哥特/CLA/日常",
          "occasion": "日常/约会/茶会/通勤",
          "reasoning": "搭配理由（50字以内）"
        }

        重要提示：
        - selectedItemIDs必须严格使用【可用单品列表】中提供的ID（UUID格式）
        - 不要编造ID，必须从列表中选择真实存在的物品ID
        - 如果衣橱为空或物品不足，请返回空数组并说明
        - 描述要符合小橘猫角色（带喵~，用括号表示动作）
        """
    }

    /// 解析AI响应
    private func parseAIResponse(_ response: String, clothings: [Clothing]) throws -> OutfitSuggestionResponse {
        // 提取JSON部分
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            throw OutfitSuggestionError.invalidJSONFormat
        }

        let jsonString = String(response[jsonStart...jsonEnd])

        // 解析JSON
        guard let data = jsonString.data(using: .utf8) else {
            throw OutfitSuggestionError.invalidJSONFormat
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let description = json["description"] as? String ?? "为你搭配了一套~喵"
                let idStrings = json["selectedItemIDs"] as? [String] ?? []
                let style = json["style"] as? String ?? "日常"
                let occasion = json["occasion"] as? String ?? "日常"
                let reasoning = json["reasoning"] as? String ?? ""

                // 转换ID字符串为UUID
                let selectedIDs = idStrings.compactMap { UUID(uuidString: $0) }

                // 验证ID是否存在于衣橱中
                let validIDs = selectedIDs.filter { id in
                    clothings.contains { $0.id == id }
                }

                return OutfitSuggestionResponse(
                    description: description,
                    selectedItemIDs: validIDs,
                    style: style,
                    occasion: occasion,
                    reasoning: reasoning
                )
            } else {
                throw OutfitSuggestionError.invalidJSONFormat
            }
        } catch {
            throw OutfitSuggestionError.parseError(error.localizedDescription)
        }
    }

    /// 获取建议对应的CutoutItem
    private func fetchCutoutsForSuggestion(
        suggestion: OutfitSuggestionResponse,
        context: ModelContext
    ) async throws -> [CutoutItem] {
        // 在主线程执行数据库查询
        return try await MainActor.run {
            var result: [CutoutItem] = []

            for clothingID in suggestion.selectedItemIDs {
                // 查找关联的CutoutItem
                let descriptor = FetchDescriptor<CutoutItem>(
                    predicate: #Predicate { $0.linkedClothingID == clothingID }
                )

                if let cutout = try context.fetch(descriptor).first {
                    result.append(cutout)
                }
            }

            return result
        }
    }

    /// 构建响应文本
    private func buildResponseText(suggestion: OutfitSuggestionResponse, clothings: [Clothing]) -> String {
        var text = suggestion.description

        if !suggestion.reasoning.isEmpty {
            text += "\n\n" + suggestion.reasoning
        }

        // 添加物品清单
        if !clothings.isEmpty {
            let names = clothings.map { $0.name }.joined(separator: "、")
            text += "\n\n包含：\(names)"
        }

        return text
    }
}

// MARK: - 错误类型

enum OutfitSuggestionError: Error, LocalizedError {
    case noItemsAvailable
    case insufficientItems
    case invalidJSONFormat
    case parseError(String)
    case aiServiceError(String)

    var errorDescription: String? {
        switch self {
        case .noItemsAvailable:
            return "没有找到推荐的裙装，请检查衣橱数据~"
        case .insufficientItems:
            return "衣橱物品不足，至少需要2件单品才能搭配喵~"
        case .invalidJSONFormat:
            return "AI响应格式不正确，请重试~"
        case .parseError(let message):
            return "解析失败：\(message)"
        case .aiServiceError(let message):
            return "AI服务错误：\(message)"
        }
    }
}

// MARK: - 便捷扩展

extension OutfitSuggestionService {
    /// 检查是否可以进行搭配建议
    /// - Parameter context: ModelContext
    /// - Returns: 是否可以搭配
    func canSuggestOutfit(context: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<CutoutItem>()
            let count = try context.fetch(descriptor).count
            return count >= 2
        } catch {
            return false
        }
    }

    /// 获取可用于搭配的CutoutItem数量
    func availableCutoutCount(context: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<CutoutItem>()
            return try context.fetch(descriptor).count
        } catch {
            return 0
        }
    }
}
