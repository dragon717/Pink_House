import Foundation

struct PetThemeConversationResult {
    let reply: String
    let shouldAnimate: Bool
    let widgets: [PetWidgetData]
}

enum PetThemeConversationEngine {
    private static let themeActionVerbs = [
        "切", "切到", "切成", "切换", "换", "换成", "改", "改成", "改为",
        "变成", "开启", "启用", "使用", "应用", "恢复", "还原", "重置", "保存"
    ]

    private static let themeDomainKeywords = [
        "主题", "配色", "界面", "皮肤", "气泡", "聊天皮肤", "聊天气泡", "气泡颜色"
    ]

    static func handleIfNeeded(
        userText: String,
        themeManager: ThemeManager
    ) -> PetThemeConversationResult? {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        if isRestoreDefaultIntent(lower) {
            themeManager.captureThemeSnapshot()
            themeManager.restoreDefaultThemeSet()
            return PetThemeConversationResult(
                reply: "（挥挥魔杖）已帮你恢复默认主题：莫妮卡粉 + 经典皮肤，界面会更柔和耐看喵~",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if isRestoreLastIntent(lower) {
            guard themeManager.restoreLastThemeSnapshot() else {
                return PetThemeConversationResult(
                    reply: "（翻翻魔法记录）我这边还没有上一套主题快照喵，要不要先切一次主题，我再帮你记住？",
                    shouldAnimate: false,
                    widgets: themeActionWidgets(themeManager: themeManager)
                )
            }
            return PetThemeConversationResult(
                reply: "（轻轻挥杖）已经帮你恢复到上一次的主题状态啦，不喜欢的话还可以继续撤回喵~",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if isMagicSkinIntent(lower) {
            themeManager.captureThemeSnapshot()
            themeManager.petChatSkinTheme = .magic
            return PetThemeConversationResult(
                reply: "（亮晶晶）萌宠对话已切到魔法皮肤啦，用户气泡和萌宠气泡会一起跟着这套皮肤走喵~",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if isClassicSkinIntent(lower) {
            themeManager.captureThemeSnapshot()
            themeManager.petChatSkinTheme = .classic
            return PetThemeConversationResult(
                reply: "（轻轻点头）已切回经典皮肤，视觉更简洁稳重喵。",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if isMagicThemeIntent(lower) {
            themeManager.captureThemeSnapshot()
            themeManager.switchColorSchemeMode(to: .magic)
            if themeManager.petChatSkinTheme != .magic {
                themeManager.petChatSkinTheme = .magic
            }
            return PetThemeConversationResult(
                reply: "（转圈施法）已开启魔法配色，衣橱/日历/来财会使用统一的魔法语义色板喵~",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if isCustomThemeIntent(lower) {
            themeManager.captureThemeSnapshot()
            themeManager.switchColorSchemeMode(to: .custom)
            return PetThemeConversationResult(
                reply: "（认真记笔记）已切到客制化配色，你现在改的颜色会按当前方案直接生效。",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if isSaveThemeIntent(lower) {
            let themeName = extractThemeName(from: text) ?? "我的主题\(Int(Date().timeIntervalSince1970) % 10_000)"
            themeManager.captureThemeSnapshot()
            let saved = themeManager.saveCurrentThemeAsSet(named: themeName)
            return PetThemeConversationResult(
                reply: "（把小本本举给你看）已经帮你保存为「\(saved.name)」，之后一句话叫我切换就好啦~",
                shouldAnimate: false,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        if let matchedName = matchThemeName(from: text, candidates: themeManager.availableThemeSetNames()) {
            themeManager.captureThemeSnapshot()
            guard themeManager.applyThemeSet(named: matchedName) else {
                return nil
            }
            return PetThemeConversationResult(
                reply: "（眼睛发亮）收到！已经切到「\(matchedName)」主题啦，要不要我顺便把萌宠皮肤也一起调整？",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        }

        return nil
    }

    static func handleQuickAction(
        command: String,
        themeManager: ThemeManager
    ) -> PetThemeConversationResult? {
        switch command {
        case "theme_save_current":
            let themeName = "聊天主题\(Int(Date().timeIntervalSince1970) % 10_000)"
            themeManager.captureThemeSnapshot()
            let saved = themeManager.saveCurrentThemeAsSet(named: themeName)
            return PetThemeConversationResult(
                reply: "（把丝带系好）这套配色已经替你存成「\(saved.name)」啦，下次一句话就能切回来喵~",
                shouldAnimate: false,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        case "theme_restore_last":
            guard themeManager.restoreLastThemeSnapshot() else {
                return PetThemeConversationResult(
                    reply: "（翻翻魔法记录）我这边还没有上一套主题快照喵，要不要先切一次主题，我再帮你记住？",
                    shouldAnimate: false,
                    widgets: themeActionWidgets(themeManager: themeManager)
                )
            }
            return PetThemeConversationResult(
                reply: "（轻轻挥杖）已经恢复到上一次的主题状态啦~",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        case "theme_restore_default":
            themeManager.captureThemeSnapshot()
            themeManager.restoreDefaultThemeSet()
            return PetThemeConversationResult(
                reply: "（拍拍裙摆）已经帮你回到默认主题：莫妮卡粉 + 经典皮肤喵~",
                shouldAnimate: true,
                widgets: themeActionWidgets(themeManager: themeManager)
            )
        default:
            return nil
        }
    }

    private static func isMagicThemeIntent(_ lower: String) -> Bool {
        hasExplicitThemeAction(lower) && containsAny(lower, ["魔法配色", "魔法主题"])
    }

    private static func isCustomThemeIntent(_ lower: String) -> Bool {
        hasExplicitThemeAction(lower) &&
        containsAny(lower, ["客制化配色", "自定义配色", "自定义主题", "客制化主题"])
    }

    private static func isMagicSkinIntent(_ lower: String) -> Bool {
        hasExplicitThemeAction(lower) &&
        containsAny(lower, ["魔法皮肤", "魔法气泡", "萌宠魔法皮肤"])
    }

    private static func isClassicSkinIntent(_ lower: String) -> Bool {
        hasExplicitThemeAction(lower) &&
        containsAny(lower, ["经典皮肤", "默认皮肤", "经典气泡"])
    }

    private static func isRestoreDefaultIntent(_ lower: String) -> Bool {
        containsAny(lower, ["恢复默认主题", "还原默认主题", "重置主题", "恢复默认气泡", "还原默认气泡"])
    }

    private static func isRestoreLastIntent(_ lower: String) -> Bool {
        containsAny(lower, ["恢复上一次", "恢复上个主题", "恢复上一套主题", "撤回主题", "撤回配色"])
    }

    private static func isSaveThemeIntent(_ lower: String) -> Bool {
        containsAny(lower, ["保存"]) && containsAny(lower, ["主题", "配色", "皮肤", "气泡"])
    }

    private static func hasExplicitThemeAction(_ lower: String) -> Bool {
        containsAny(lower, themeActionVerbs) && containsAny(lower, themeDomainKeywords)
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
        guard hasExplicitThemeAction(lower) else {
            return nil
        }
        return candidates.first(where: { candidate in
            let key = candidate.lowercased()
            return lower.contains(key)
        })
    }

    private static func themeActionWidgets(themeManager: ThemeManager) -> [PetWidgetData] {
        var options = [
            PetWidgetOption(title: "保存这套配色", command: "theme_save_current", icon: "square.and.arrow.down.fill")
        ]

        if themeManager.canRestoreLastThemeSnapshot {
            options.append(
                PetWidgetOption(title: "恢复上一次", command: "theme_restore_last", icon: "arrow.uturn.backward.circle.fill")
            )
        }

        options.append(
            PetWidgetOption(title: "恢复默认", command: "theme_restore_default", icon: "arrow.counterclockwise.circle.fill")
        )

        return [
            PetWidgetData(
                type: .quickOptions,
                title: "主题操作",
                options: options
            )
        ]
    }
}
