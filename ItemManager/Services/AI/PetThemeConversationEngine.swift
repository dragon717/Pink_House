import Foundation

struct PetThemeConversationResult {
    let reply: String
    let shouldAnimate: Bool
}

enum PetThemeConversationEngine {
    static func handleIfNeeded(
        userText: String,
        themeManager: ThemeManager
    ) -> PetThemeConversationResult? {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        if isRestoreDefaultIntent(lower) {
            themeManager.restoreDefaultThemeSet()
            return PetThemeConversationResult(
                reply: "（挥挥魔杖）已帮你恢复默认主题：莫妮卡粉 + 经典皮肤，界面会更柔和耐看喵~",
                shouldAnimate: true
            )
        }

        if isMagicSkinIntent(lower) {
            themeManager.petChatSkinTheme = .magic
            return PetThemeConversationResult(
                reply: "（亮晶晶）萌宠对话已切到魔法皮肤啦，气泡和引导选项都会变成魔法配色～",
                shouldAnimate: true
            )
        }

        if isClassicSkinIntent(lower) {
            themeManager.petChatSkinTheme = .classic
            return PetThemeConversationResult(
                reply: "（轻轻点头）已切回经典皮肤，视觉更简洁稳重喵。",
                shouldAnimate: true
            )
        }

        if isMagicThemeIntent(lower) {
            themeManager.switchColorSchemeMode(to: .magic)
            if themeManager.petChatSkinTheme != .magic {
                themeManager.petChatSkinTheme = .magic
            }
            return PetThemeConversationResult(
                reply: "（转圈施法）已开启魔法配色，衣橱/日历/来财会使用统一的魔法语义色板喵~",
                shouldAnimate: true
            )
        }

        if isCustomThemeIntent(lower) {
            themeManager.switchColorSchemeMode(to: .custom)
            return PetThemeConversationResult(
                reply: "（认真记笔记）已切到客制化配色，你现在改的颜色会按当前方案直接生效。",
                shouldAnimate: true
            )
        }

        if isSaveThemeIntent(lower) {
            let themeName = extractThemeName(from: text) ?? "我的主题\(Int(Date().timeIntervalSince1970) % 10_000)"
            let saved = themeManager.saveCurrentThemeAsSet(named: themeName)
            return PetThemeConversationResult(
                reply: "（把小本本举给你看）已经帮你保存为「\(saved.name)」，之后一句话叫我切换就好啦~",
                shouldAnimate: false
            )
        }

        if let matchedName = matchThemeName(from: text, candidates: themeManager.availableThemeSetNames()),
           themeManager.applyThemeSet(named: matchedName) {
            return PetThemeConversationResult(
                reply: "（眼睛发亮）收到！已经切到「\(matchedName)」主题啦，要不要我顺便把萌宠皮肤也一起调整？",
                shouldAnimate: true
            )
        }

        return nil
    }

    private static func isMagicThemeIntent(_ lower: String) -> Bool {
        containsAny(lower, ["魔法配色", "魔法主题"]) && containsAny(lower, ["切", "换", "开启", "改", "用"])
    }

    private static func isCustomThemeIntent(_ lower: String) -> Bool {
        containsAny(lower, ["客制化配色", "自定义配色", "自定义主题", "客制化主题"]) &&
        containsAny(lower, ["切", "换", "开启", "改", "用"])
    }

    private static func isMagicSkinIntent(_ lower: String) -> Bool {
        containsAny(lower, ["魔法皮肤", "魔法气泡", "萌宠魔法皮肤"])
    }

    private static func isClassicSkinIntent(_ lower: String) -> Bool {
        containsAny(lower, ["经典皮肤", "默认皮肤", "经典气泡"])
    }

    private static func isRestoreDefaultIntent(_ lower: String) -> Bool {
        containsAny(lower, ["恢复默认", "还原默认", "重置主题", "默认主题"])
    }

    private static func isSaveThemeIntent(_ lower: String) -> Bool {
        containsAny(lower, ["保存"]) && containsAny(lower, ["主题", "配色"])
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func extractThemeName(from text: String) -> String? {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = ["叫", "命名为", "名称是", "名字是", "为"]
        for separator in separators {
            if let range = compact.range(of: separator) {
                let rawValue = compact[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedValue = normalizeThemeName(rawValue)
                if !cleanedValue.isEmpty {
                    return String(cleanedValue.prefix(16))
                }
            }
        }
        return nil
    }

    private static func normalizeThemeName<S: StringProtocol>(_ rawValue: S) -> String {
        var value = String(rawValue)
            .trimmingCharacters(in: CharacterSet(charactersIn: "「」\"'。！？!?，, "))

        for suffix in ["主题", "配色"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "「」\"'。！？!?，, "))
        }

        return value
    }

    private static func matchThemeName(from text: String, candidates: [String]) -> String? {
        let lower = text.lowercased()
        return candidates.first(where: { candidate in
            let key = candidate.lowercased()
            return lower.contains(key)
        })
    }
}
