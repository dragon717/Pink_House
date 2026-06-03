import Foundation

enum AIResponseMode {
    case humanized
    case raw
}

enum PetResponseHumanizer {
    private static let fencedCodePattern = "```(?:json|JSON)?\\s*([\\s\\S]*?)```"
    private static let bracePattern = "\\{[\\s\\S]*\\}"
    
    static func humanize(_ raw: String) -> String {
        let withoutFence = stripCodeFence(raw)
        let trimmed = normalizeSpaces(withoutFence)
        guard !trimmed.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        if let jsonObject = extractJSONObject(from: trimmed),
           let text = narrative(from: jsonObject),
           !text.isEmpty {
            return stripModelNames(in: normalizeSpaces(text))
        }
        
        return stripModelNames(in: cleanupCodeLikeText(trimmed))
    }

    static func humanize(
        _ raw: String,
        persona: PetPersonaProfile,
        recentAssistantReplies: [String]
    ) -> String {
        var output = humanize(raw)
        output = stripForbiddenWords(in: output, persona: persona)
        output = avoidMechanicalRepeat(output, persona: persona, recentAssistantReplies: recentAssistantReplies)
        return normalizeSpaces(output)
    }
    
    private static func stripCodeFence(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: fencedCodePattern) else {
            return text
        }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return text
    }
    
    private static func extractJSONObject(from text: String) -> Any? {
        guard let regex = try? NSRegularExpression(pattern: bracePattern) else {
            return nil
        }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range(at: 0), in: text) else {
            return nil
        }
        
        let candidate = String(text[range])
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    
    private static func narrative(from payload: Any) -> String? {
        if let dict = payload as? [String: Any] {
            return narrativeFromDict(dict)
        }
        if let array = payload as? [[String: Any]], let first = array.first {
            return narrativeFromDict(first)
        }
        return nil
    }

    // 使用不同的方法名避免递归调用歧义
    private static func narrativeFromDict(_ dict: [String: Any]) -> String {
        var parts: [String] = []
        
        if let primary = firstString(in: dict, keys: [
            "response", "answer", "message", "description", "content", "summary", "text"
        ]) {
            parts.append(primary)
        }
        
        if let emotion = firstString(in: dict, keys: ["emotion", "emotion_support", "mood_support"]) {
            parts.append("我也在乎你的心情：%@".appLocalized(emotion))
        }
        
        if let advice = firstString(in: dict, keys: ["advice", "reasoning", "tips"]) {
            parts.append(advice)
        }
        
        let style = firstString(in: dict, keys: ["style", "风格"])
        let occasion = firstString(in: dict, keys: ["occasion", "场景"])
        if style != nil || occasion != nil {
            let styleText = style.map { "风格%@".appLocalized($0) } ?? nil
            let occasionText = occasion.map { "场景%@".appLocalized($0) } ?? nil
            let combo = [styleText, occasionText].compactMap { $0 }.joined(separator: localizedClauseSeparator)
            if !combo.isEmpty {
                parts.append("如果你愿意，我们可以先按%@来细化。".appLocalized(combo))
            }
        }
        
        if let list = firstStringList(in: dict, keys: ["recommendations", "items", "steps", "suggestions"]) {
            let concise = list.prefix(3).joined(separator: localizedListSeparator)
            if !concise.isEmpty {
                parts.append("我先给你这几条：%@。".appLocalized(concise))
            }
        }
        
        if parts.isEmpty {
            // 兜底：拼接可读的字符串值，过滤 id/code 字段。
            let fallback = dict
                .filter { !isTechnicalKey($0.key) }
                .compactMap { valueAsReadableText($0.value) }
                .filter { !$0.isEmpty }
                .prefix(3)
                .joined(separator: localizedSentenceSeparator)
            return fallback
        }
        
        return parts.joined(separator: "\n")
    }
    
    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let clean = normalizeSpaces(value)
                if !clean.isEmpty {
                    return clean
                }
            }
        }
        return nil
    }
    
    private static func firstStringList(in dict: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let value = dict[key] as? [String] {
                return value.map { normalizeSpaces($0) }.filter { !$0.isEmpty }
            }
        }
        return nil
    }
    
    private static func valueAsReadableText(_ value: Any) -> String? {
        if let text = value as? String {
            return normalizeSpaces(text)
        }
        if let list = value as? [String] {
            return list.prefix(3).joined(separator: localizedListSeparator)
        }
        return nil
    }
    
    private static func isTechnicalKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower.contains("id") || lower.contains("json") || lower.contains("code")
    }
    
    private static func cleanupCodeLikeText(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "\"", with: "")
        output = output.replacingOccurrences(of: "```", with: "")
        
        // 把常见 key:value 样式转成自然中文断句。
        let replacements: [(String, String)] = [
            ("response:", ""),
            ("answer:", ""),
            ("message:", ""),
            ("description:", ""),
            ("reasoning:", "原因：".appLocalized),
            ("advice:", "建议：".appLocalized)
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        
        return normalizeSpaces(output)
    }
    
    private static func normalizeSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var localizedClauseSeparator: String {
        "，".appLocalized
    }

    private static var localizedListSeparator: String {
        "、".appLocalized
    }

    private static var localizedSentenceSeparator: String {
        "。".appLocalized
    }
    
    private static func stripModelNames(in text: String) -> String {
        var output = text
        let blocked = [
            "DeepSeek", "deepseek",
            "Minimax", "MiniMax",
            "OpenAI", "openai",
            "Claude", "claude",
            "Gemini", "gemini",
            "大模型", "模型建议"
        ]
        for token in blocked {
            output = output.replacingOccurrences(of: token, with: "")
        }
        return normalizeSpaces(output)
    }

    private static func stripForbiddenWords(in text: String, persona: PetPersonaProfile) -> String {
        var output = text
        for token in persona.forbiddenWords where !token.isEmpty {
            output = output.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        return normalizeSpaces(output)
    }

    private static func avoidMechanicalRepeat(
        _ text: String,
        persona: PetPersonaProfile,
        recentAssistantReplies: [String]
    ) -> String {
        let normalizedCurrent = normalizeSpaces(text)
        guard !normalizedCurrent.isEmpty else { return normalizedCurrent }

        let recent = recentAssistantReplies
            .suffix(4)
            .map { normalizeSpaces($0) }

        let duplicated = recent.contains { old in
            old == normalizedCurrent || old.hasPrefix(normalizedCurrent) || normalizedCurrent.hasPrefix(old)
        }

        guard duplicated, let suffix = persona.warmthSuffixes.randomElement() else {
            return normalizedCurrent
        }

        if normalizedCurrent.contains(suffix) {
            return normalizedCurrent
        }
        return "\(normalizedCurrent) \(suffix)"
    }
}
