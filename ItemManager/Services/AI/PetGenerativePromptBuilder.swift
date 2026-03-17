import Foundation

enum PetGenerativePromptBuilder {
    static func buildPrompt(
        userQuery: String,
        wardrobeContextBlock: String?
    ) -> String {
        var parts: [String] = []
        parts.append("用户原始问题：\(userQuery)")

        if let wardrobeContextBlock, !wardrobeContextBlock.isEmpty {
            parts.append(wardrobeContextBlock)
        }

        parts.append(outputProtocol)
        return parts.joined(separator: "\n\n")
    }

    private static let outputProtocol = """
    【输出协议（必须遵守）】
    1) 仅输出 JSON 对象，不要 Markdown，不要代码块。
    2) JSON 结构固定：
    {"text":"...","widgets":[{"type":"quick_options","title":"...","options":[{"title":"A. ...","command":"..."},{"title":"B. ...","command":"..."},{"title":"C. ...","command":"..."}]}]}
    3) text 要口语化、拟人化，可撒娇安抚；严禁出现模型名、服务商名或“JSON对象”等技术词。
    4) widgets 最多 2 个；每个 options 最多 3 个；command 仅可用：
       outfit_suggest / weather_guidance / search_prompt / mood_support / ask:具体问题
    5) 若本轮与衣橱无关，不要编造衣橱数据；若与穿搭相关，优先基于给定候选单品给建议。
    """
}
