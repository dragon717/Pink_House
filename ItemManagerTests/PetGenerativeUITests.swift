import XCTest
@testable import ItemManager

final class PetGenerativeUITests: XCTestCase {
    func testParserParsesFencedJSONEnvelope() {
        let raw = """
        ```json
        {
          "text": "先试试这三个方向吧~",
          "widgets": [
            {
              "type": "quick_options",
              "title": "快速选择",
              "options": [
                { "title": "A. 帮我搭一套", "command": "outfit_suggest" },
                { "title": "B. 看天气穿搭", "command": "weather_guidance" }
              ]
            }
          ]
        }
        ```
        """

        let render = PetGenerativeUIParser.buildRenderableContent(
            rawText: raw,
            fallbackDisplayText: "fallback",
            userQuery: "你好"
        )

        XCTAssertTrue(render.text.contains("先试试这三个方向"))
        XCTAssertEqual(render.widgets.count, 1)
        XCTAssertEqual(render.widgets.first?.type, .quickOptions)
        XCTAssertEqual(render.widgets.first?.options.count, 2)
    }

    func testParserFallsBackToSuggestedWidgets() {
        let render = PetGenerativeUIParser.buildRenderableContent(
            rawText: "今天也要开心喵~",
            fallbackDisplayText: "今天也要开心喵~",
            userQuery: "帮我搭配一套出门穿搭"
        )

        XCTAssertEqual(render.widgets.count, 1)
        XCTAssertEqual(render.widgets.first?.type, .quickOptions)
        XCTAssertEqual(render.widgets.first?.options.count, 3)
        XCTAssertTrue(render.widgets.first?.options.first?.title.contains("A.") == true)
    }

    func testParserSupportsGuiAliasField() {
        let raw = """
        {
          "message": "这就来帮你安排~",
          "gui": [
            {
              "type": "quick_options",
              "actions": [
                { "text": "A. 帮我搭一套", "action": "outfit_suggest" },
                { "text": "B. 看天气穿搭", "action": "weather_guidance" },
                { "text": "C. 帮我找裙子", "action": "search_prompt" }
              ]
            }
          ]
        }
        """

        let render = PetGenerativeUIParser.buildRenderableContent(
            rawText: raw,
            fallbackDisplayText: "fallback",
            userQuery: "你好"
        )

        XCTAssertEqual(render.widgets.count, 1)
        XCTAssertEqual(render.widgets.first?.options.count, 3)
        XCTAssertEqual(render.widgets.first?.options[0].command, "outfit_suggest")
    }

    func testOnboardingWidgetsContainABCInteraction() {
        let widgets = PetWidgetSuggestionBuilder.onboardingWidgets()

        XCTAssertEqual(widgets.count, 1)
        XCTAssertEqual(widgets.first?.options.count, 3)
        XCTAssertEqual(widgets.first?.options[0].command, "outfit_suggest")
        XCTAssertEqual(widgets.first?.options[1].command, "weather_guidance")
        XCTAssertEqual(widgets.first?.options[2].command, "search_prompt")
    }

    func testPromptBuilderContainsStableProtocol() {
        let prompt = PetGenerativePromptBuilder.buildPrompt(
            userQuery: "帮我搭一套明天上班穿的",
            wardrobeContextBlock: "以下是衣橱摘要（仅供参考）：..."
        )

        XCTAssertTrue(prompt.contains("用户原始问题"))
        XCTAssertTrue(prompt.contains("输出协议"))
        XCTAssertTrue(prompt.contains("\"widgets\""))
        XCTAssertTrue(prompt.contains("outfit_suggest"))
    }

    func testPromptBuilderSupportsPersonaAndModule() {
        let persona = PetPersonaRegistry.profile(for: .kitten, petName: "奶茶")
        let prompt = PetGenerativePromptBuilder.buildPrompt(
            input: .init(
                userQuery: "我今天有点焦虑",
                wardrobeContextBlock: nil,
                persona: persona,
                module: .mood,
                recentAssistantReplies: ["别急，我陪你慢慢来喵~"]
            )
        )

        XCTAssertTrue(prompt.contains("你正在扮演"))
        XCTAssertTrue(prompt.contains("角色卡"))
        XCTAssertTrue(prompt.contains("模块目标"))
        XCTAssertTrue(prompt.contains("可用本地工具"))
        XCTAssertTrue(prompt.contains("宠物状态约束"))
        XCTAssertTrue(prompt.contains("避免重复句式"))
    }

    func testWeatherWidgetFactoryBuildsContainerWithChildren() {
        let dress = Clothing(name: "薄荷JSK", types: "JSK")
        let shoe = Clothing(name: "玛丽珍鞋", types: "鞋")
        let umbrella = Clothing(name: "透明雨伞", types: "配饰")
        let selection = WeatherWardrobeSelection(dresses: [dress], shoes: [shoe], umbrellas: [umbrella])
        let weather = WeatherData(
            temperature: 21,
            condition: .lightRain,
            humidity: 70,
            windSpeed: 2.6,
            city: "上海",
            updateTime: Date()
        )

        let widgets = PetChatWidgetFactory.weatherGuidanceWidgets(weather: weather, selection: selection)

        XCTAssertEqual(widgets.count, 1)
        XCTAssertEqual(widgets.first?.type, .container)
        XCTAssertEqual(widgets.first?.children.count, 3)
        XCTAssertEqual(widgets.first?.children.first?.type, .weatherCard)
    }

    func testIntentRouterDetectsMoodAndOutfit() {
        XCTAssertEqual(PetChatIntentRouter.detect(from: "我有点焦虑，先安慰我"), .moodSupport)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "帮我搭配一套出门穿搭"), .outfitSuggestion)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "刚刚搭配的三件衣服价格多少"), .lastOutfitPrice)
    }

    func testRecentAssistantRepliesHelperFiltersUserMessages() {
        let messages = [
            ChatMessage(text: "你好", isUser: true),
            ChatMessage(text: "喵~我在", isUser: false),
            ChatMessage(text: "今天下雨吗", isUser: true),
            ChatMessage(text: "有小雨，记得带伞", isUser: false)
        ]

        let replies = PetGenerativePromptBuilder.recentAssistantReplies(
            from: messages,
            isUser: \.isUser,
            text: \.text
        )

        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies.first, "喵~我在")
        XCTAssertEqual(replies.last, "有小雨，记得带伞")
    }

    func testActionSanitizerRejectsUnknownIdentifier() {
        let invalid = PetConversationToolbox.sanitizeActionIdentifier("random_unknown_action", role: .kitten)
        let valid = PetConversationToolbox.sanitizeActionIdentifier("happy_cat", role: .kitten)

        XCTAssertNil(invalid)
        XCTAssertEqual(valid, "happy_cat")
    }

    func testMemoryStoreRecordsLatestOutfitPriceSummary() {
        let first = Clothing(name: "薄荷JSK", price: 699)
        let second = Clothing(name: "奶白玛丽珍", price: 399)
        let third = Clothing(name: "透明雨伞", price: 129)

        PetConversationMemoryStore.shared.recordOutfitSelection(
            clothings: [first, second, third],
            role: .kitten
        )

        let summary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: .kitten)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("薄荷JSK") == true)
        XCTAssertTrue(summary?.contains("合计") == true)
    }

    func testChatMessageDecodesLegacyTimestampString() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "text": "历史消息",
          "isUser": false,
          "timestamp": "2026-03-19T10:00:00Z"
        }
        """
        let data = Data(json.utf8)
        let message = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(message.text, "历史消息")
    }

    func testPromptIncludesOutfitPriceHintWhenAsked() {
        let a = Clothing(name: "奶白JSK", price: 500)
        let b = Clothing(name: "玛丽珍", price: 300)
        let c = Clothing(name: "透明伞", price: 100)
        PetConversationMemoryStore.shared.recordOutfitSelection(
            clothings: [a, b, c],
            role: .kitten
        )

        let persona = PetPersonaRegistry.profile(for: .kitten, petName: "奶茶")
        let prompt = PetGenerativePromptBuilder.buildPrompt(
            input: .init(
                userQuery: "刚刚搭配的三件衣服价格多少",
                wardrobeContextBlock: nil,
                persona: persona,
                module: .wardrobe,
                recentAssistantReplies: []
            )
        )

        XCTAssertTrue(prompt.contains("最近搭配价格快照"))
        XCTAssertTrue(prompt.contains("合计"))
    }

    func testThemeConversationEngineSwitchesMagicThemeAndSkin() {
        let manager = ThemeManager.shared
        let originalConfig = manager.themeColorConfig
        let originalSkin = manager.petChatSkinTheme
        defer {
            manager.themeColorConfig = originalConfig
            manager.petChatSkinTheme = originalSkin
        }

        let result = PetThemeConversationEngine.handleIfNeeded(
            userText: "帮我切换成魔法配色",
            themeManager: manager
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(manager.colorSchemeMode, .magic)
        XCTAssertEqual(manager.petChatSkinTheme, .magic)
        XCTAssertTrue(result?.shouldAnimate == true)
    }

    func testThemeConversationEngineCanSaveThemeSet() {
        let manager = ThemeManager.shared
        let originalConfig = manager.themeColorConfig
        defer { manager.themeColorConfig = originalConfig }

        let uniqueName = "单测主题_\(Int(Date().timeIntervalSince1970))"
        let result = PetThemeConversationEngine.handleIfNeeded(
            userText: "请把这套主题保存，命名为\(uniqueName)",
            themeManager: manager
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(manager.availableThemeSetNames().contains(uniqueName))
    }
}
