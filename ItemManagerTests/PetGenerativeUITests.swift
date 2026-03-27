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
        XCTAssertTrue(prompt.contains("0 或 1 个 [IMAGE:动作ID]"))
    }

    func testWeatherWidgetFactoryBuildsContainerWithChildren() {
        let outerwear = Clothing(name: "奶油开衫", types: "外套")
        let dress = Clothing(name: "薄荷JSK", types: "JSK")
        let shoe = Clothing(name: "玛丽珍鞋", types: "鞋")
        let umbrella = Clothing(name: "透明雨伞", types: "配饰")
        let selection = WeatherWardrobeSelection(outerwears: [outerwear], dresses: [dress], shoes: [shoe], umbrellas: [umbrella])
        let weather = WeatherData(
            temperature: 21,
            apparentTemperature: 20,
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
        XCTAssertTrue(widgets.first?.children[1].subtitle?.contains("外套：奶油开衫") == true)
        XCTAssertEqual(widgets.first?.children.first?.metrics.first?.name, "气温")
    }

    func testIntentRouterDetectsMoodAndOutfit() {
        XCTAssertEqual(PetChatIntentRouter.detect(from: "我有点焦虑，先安慰我"), .moodSupport)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "帮我搭配一套出门穿搭"), .outfitSuggestion)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "刚刚搭配的三件衣服价格多少"), .lastOutfitPrice)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "刚推荐的清单总价是多少"), .lastOutfitPrice)
    }

    func testIntentRouterDetectsFuzzyAdoptionPhrases() {
        XCTAssertEqual(PetChatIntentRouter.detect(from: "领养毛毛"), .secondPetAdoption)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "我想领养一个新宠物"), .secondPetAdoption)
    }

    func testIntentRouterDetectsFuzzySwitchPetPhrases() {
        XCTAssertEqual(PetChatIntentRouter.detect(from: "换一个宠物"), .switchPetCompanion)
        XCTAssertEqual(PetChatIntentRouter.detect(from: "我想换个宠物管家"), .switchPetCompanion)
    }

    func testEmbeddedIntentDetectsMoodByNaturalQuestion() {
        let intent = detectEmbeddedPanelIntent(from: "你现在心情怎么样？", petName: "奶茶")
        guard case .status(let kind)? = intent else {
            XCTFail("Expected mood status intent")
            return
        }
        XCTAssertEqual(kind, .mood)
    }

    func testFuzzyStatusDetectionSupportsEmotionPhrases() {
        let kind = detectFuzzyStatusPanelKind(from: "它今天有点低落吗", petName: "奶茶")
        XCTAssertEqual(kind, .mood)
    }

    func testDirectPlayIntentDetectsYarnBall() {
        let intent = detectDirectPlayIntent(from: "给你玩毛线球")
        XCTAssertEqual(intent?.preferredItemId, "yarnBall")
    }

    func testDirectFeedIntentDetectsEatCannedFoodByNaturalPhrase() {
        let intent = detectDirectFeedIntent(from: "吃猫罐头")
        XCTAssertEqual(intent?.preferredItemId, "cannedFood")
    }

    func testDirectFeedIntentDetectsCatFoodAndRawMeatByNaturalPhrase() {
        XCTAssertEqual(detectDirectFeedIntent(from: "吃猫粮")?.preferredItemId, "catFood")
        XCTAssertEqual(detectDirectFeedIntent(from: "来点生骨肉")?.preferredItemId, "rawMeat")
    }

    func testDirectFeedIntentDetectsDrinkWarmWaterByNaturalPhrase() {
        let intent = detectDirectFeedIntent(from: "喝温水")
        XCTAssertEqual(intent?.preferredItemId, "warmWater")
    }

    func testDirectUseIntentDetectsYarnBallAndEnergyPill() {
        XCTAssertEqual(detectDirectUseIntent(from: "用毛线球")?.preferredItemId, "yarnBall")
        XCTAssertEqual(detectDirectUseIntent(from: "用精力药丸")?.preferredItemId, "energyPill")
    }

    func testResolveDirectPlayItemFallsBackToYarnBall() {
        let item = resolveDirectPlayItem(intent: PetDirectPlayIntent(preferredItemId: "yarnBall"), status: PetStatus())
        XCTAssertEqual(item?.id, "yarnBall")
    }

    func testYarnBallShopGuidanceMentionsBottomLocation() {
        let item = PetConfigManager.shared.getItem(byId: "yarnBall")
        XCTAssertNotNil(item)
        let text = shopGuidanceText(for: item!)
        XCTAssertTrue(text.contains("最下面"))
        XCTAssertTrue(text.contains("最底层"))
    }

    func testIntentRouterDetectsDirectSwitchTargetByDefaultName() {
        var status = PetStatus()
        status.ownedPetIds = [PetCharacter.naicha.id, PetCharacter.maomao.id]
        status.selectedPetId = PetCharacter.naicha.id

        XCTAssertEqual(PetChatIntentRouter.detectSwitchTarget(from: "我要毛毛", status: status), .maomao)
        XCTAssertEqual(PetChatIntentRouter.detectSwitchTarget(from: "切换到奶茶", status: status), .naicha)
    }

    func testIntentRouterDetectsDirectSwitchTargetByCustomName() {
        var status = PetStatus()
        status.ownedPetIds = [PetCharacter.naicha.id, PetCharacter.maomao.id]
        status.selectedPetId = PetCharacter.naicha.id
        status.petNames[PetCharacter.naicha.id] = "可可"
        status.petNames[PetCharacter.maomao.id] = "团子"

        XCTAssertEqual(PetChatIntentRouter.detectSwitchTarget(from: "团子今天在吗", status: status), .maomao)
        XCTAssertNil(PetChatIntentRouter.detectSwitchTarget(from: "今天天气怎么样", status: status))
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
        let cat = PetConversationToolbox.sanitizeActionIdentifier("cat", role: .kitten)
        let dog = PetConversationToolbox.sanitizeActionIdentifier("dog", role: .goldenRetriever)
        let alias = PetConversationToolbox.sanitizeActionIdentifier("happy", role: .goldenRetriever)
        let confused = PetConversationToolbox.sanitizeActionIdentifier("confused", role: .goldenRetriever)
        let playful = PetConversationToolbox.sanitizeActionIdentifier("playful", role: .kitten)
        let sad = PetConversationToolbox.sanitizeActionIdentifier("sad", role: .goldenRetriever)

        XCTAssertNil(invalid)
        XCTAssertEqual(valid, "happy_cat")
        XCTAssertEqual(cat, "cat")
        XCTAssertEqual(dog, "dog")
        XCTAssertEqual(alias, "happy_dog")
        XCTAssertEqual(confused, "curious_dog")
        XCTAssertEqual(playful, "happy_cat")
        XCTAssertEqual(sad, "sleepy_dog")
    }

    func testExpressionMeaningDetectorPrefersSemanticCue() {
        XCTAssertEqual(detectPetChatExpressionMeaning(in: "（歪头）我有点疑惑，再想想"), .confused)
        XCTAssertEqual(detectPetChatExpressionMeaning(in: "（眼睛发亮）太棒啦，我们走吧"), .happy)
        XCTAssertEqual(detectPetChatExpressionMeaning(in: "我有点困，先休息一下"), .sleepy)
    }

    func testPetCharacterExpressionMappingUsesPetSpecificAssets() {
        XCTAssertEqual(PetCharacter.naicha.chatExpressionImageName(for: .confused), "curious_cat")
        XCTAssertEqual(PetCharacter.maomao.chatExpressionImageName(for: .confused), "curious_dog")
        XCTAssertEqual(PetCharacter.naicha.chatExpressionImageName(for: .thinking), "thinking_cat")
        XCTAssertEqual(PetCharacter.maomao.chatExpressionImageName(for: .happy), "happy_dog")
    }

    func testContextualStatusReplyForMoodFeelsConversational() {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.naicha.id
        status.petNames[PetCharacter.naicha.id] = "奶茶"
        status.mood = 42

        let reply = contextualStatusReply(for: .mood, status: status, sourceText: "你现在心情怎么样")
        XCTAssertTrue(reply.message.contains("心情"))
        XCTAssertTrue(reply.message.contains("我"))
        XCTAssertNotNil(reply.subtitle)
    }

    func testPetPanelCopyUsesFirstPersonVoice() {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.naicha.id
        status.petNames[PetCharacter.naicha.id] = "奶茶"
        status.inventory = ["catFood": 2]
        status.meowCoin = 8
        status.fishCoin = 16

        let statusWidget = makeStatusPanelWidget(status: status, kind: .all)
        XCTAssertEqual(statusWidget.title, "我的状态总览")
        XCTAssertTrue(statusWidget.subtitle?.contains("我现在") == true)

        let inventoryWidget = makeInventoryPanelWidget(status: status)
        XCTAssertEqual(inventoryWidget.title, "我的背包")
        XCTAssertTrue(inventoryWidget.subtitle?.contains("我现在有的东西") == true)

        let currencyWidget = makeCurrencyPanelWidget(status: status, kind: .all)
        XCTAssertEqual(currencyWidget.title, "我的货币余额")
        XCTAssertTrue(currencyWidget.subtitle?.contains("我的小金库") == true)
    }

    func testSleepyExpressionRuleSupportsLowEnergyAndTimeOfDay() {
        var status = PetStatus()
        status.energy = 20
        XCTAssertTrue(petChatShouldShowSleepyExpression(status: status))

        let calendar = Calendar(identifier: .gregorian)
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 10))!
        status.energy = 90
        XCTAssertTrue(petChatShouldShowSleepyExpression(status: status, now: lateNight, calendar: calendar))

        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7, minute: 0))!
        status.energy = 50
        XCTAssertTrue(petChatShouldShowSleepyExpression(status: status, now: earlyMorning, calendar: calendar))

        status.energy = 90
        XCTAssertFalse(petChatShouldShowSleepyExpression(status: status, now: earlyMorning, calendar: calendar))
    }

    func testMoodExpressionPrefersSleepyWhenTiredContext() {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.maomao.id
        status.energy = 25
        status.mood = 95

        let imageName = petChatStatusExpressionImageName(status: status, kind: .mood)
        XCTAssertEqual(imageName, PetCharacter.maomao.sleepyImageName)
    }

    func testMemoryStoreRecordsLatestOutfitPriceSummary() {
        let suffix = String(UUID().uuidString.prefix(6))
        let firstName = "薄荷JSK_\(suffix)"
        let first = Clothing(name: firstName, price: 699)
        let second = Clothing(name: "奶白玛丽珍", price: 399)
        let third = Clothing(name: "透明雨伞", price: 129)

        PetConversationMemoryStore.shared.recordOutfitSelection(
            clothings: [first, second, third],
            role: .kitten
        )

        let summary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: .kitten)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains(firstName) == true)
        XCTAssertTrue(summary?.contains("合计") == true)
    }

    func testMemoryStoreOutfitPriceSummaryUsesAllRecommendedItems() {
        let first = Clothing(name: "莓莓JSK", price: 100)
        let second = Clothing(name: "奶油开衫", price: 200)
        let third = Clothing(name: "玛丽珍鞋", price: 300)
        let fourth = Clothing(name: "透明雨伞", price: 400)

        PetConversationMemoryStore.shared.recordOutfitSelection(
            clothings: [first, second, third, fourth],
            role: .goldenRetriever
        )

        let summary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: .goldenRetriever)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("合计¥1000") == true)
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

    func testEmbeddedIntentRoutesBuiltInPanels() {
        let allCurrency = detectEmbeddedPanelIntent(from: "帮我看下全部货币余额", petName: "奶茶")
        guard case .currency(let allKind)? = allCurrency else {
            return XCTFail("Expected currency all intent")
        }
        XCTAssertEqual(allKind, .all)

        let fishCurrency = detectEmbeddedPanelIntent(from: "鱼币还有多少呀", petName: "奶茶")
        guard case .currency(let fishKind)? = fishCurrency else {
            return XCTFail("Expected fish currency intent")
        }
        XCTAssertEqual(fishKind, .fishCoin)

        let moneyCounter = detectEmbeddedPanelIntent(from: "帮我数一下美元钞票", petName: "奶茶")
        guard case .moneyCounter(let currency)? = moneyCounter else {
            return XCTFail("Expected money counter intent")
        }
        XCTAssertEqual(currency, .usd)

        guard case .inventory? = detectEmbeddedPanelIntent(from: "打开背包看看道具", petName: "奶茶") else {
            return XCTFail("Expected inventory intent")
        }
        guard case .shop? = detectEmbeddedPanelIntent(from: "去商店补货", petName: "奶茶") else {
            return XCTFail("Expected shop intent")
        }
        guard case .shop? = detectEmbeddedPanelIntent(from: "带我去商城看看商品", petName: "奶茶") else {
            return XCTFail("Expected mall/shop intent")
        }
        guard case .divination? = detectEmbeddedPanelIntent(from: "今天帮我抽一签", petName: "奶茶") else {
            return XCTFail("Expected divination intent")
        }
    }

    func testOutfitPriceFollowUpContextSuppressesCurrencyPanelAutoTrigger() {
        let dress = Clothing(name: "莓莓JSK", price: 520)
        let shoes = Clothing(name: "奶油玛丽珍", price: 280)
        let suggestion = OutfitSuggestionData(
            clothings: [dress, shoes],
            description: "这套很适合你今天的安排",
            style: "甜美",
            occasion: "出门",
            layoutInfos: nil
        )

        let recentMessages = [
            PetChatMessage(text: "帮我推荐一套今天出门穿搭", isUser: true),
            PetChatMessage(
                text: "安排好了，给你这套搭配～",
                isUser: false,
                type: .outfitSuggestion,
                outfitSuggestion: suggestion
            )
        ]

        XCTAssertTrue(
            shouldTreatAsOutfitPriceFollowUp(
                query: "这一套多少钱",
                recentMessages: recentMessages,
                dialogueTurns: 2
            )
        )

        XCTAssertFalse(
            shouldTreatAsOutfitPriceFollowUp(
                query: "我现在喵币余额还有多少",
                recentMessages: recentMessages,
                dialogueTurns: 2
            )
        )

        XCTAssertNil(
            detectEmbeddedPanelIntent(
                from: "这一套多少钱",
                petName: "奶茶",
                recentMessages: recentMessages
            )
        )

        let currencyIntent = detectEmbeddedPanelIntent(
            from: "鱼币还有多少",
            petName: "奶茶",
            recentMessages: recentMessages
        )
        guard case .currency(let kind)? = currencyIntent else {
            return XCTFail("Expected fish currency intent")
        }
        XCTAssertEqual(kind, .fishCoin)
    }

    func testEmbeddedIntentResolvesEarliestStatusSignal() {
        let firstHydration = detectEmbeddedPanelIntent(from: "它是不是有点渴，也有点低落", petName: "奶茶")
        guard case .status(let firstKind)? = firstHydration else {
            return XCTFail("Expected status intent")
        }
        XCTAssertEqual(firstKind, .hydration)

        let firstMood = detectEmbeddedPanelIntent(from: "它看起来低落，也有点渴", petName: "奶茶")
        guard case .status(let secondKind)? = firstMood else {
            return XCTFail("Expected status intent")
        }
        XCTAssertEqual(secondKind, .mood)
    }

    func testMoodSupportIntentDisambiguatesWithOutfitNeed() {
        let decision = PetChatIntentRouter.decide(from: "我有点焦虑，先安慰我，然后帮我搭一套出门穿搭")
        XCTAssertEqual(decision.primaryIntent, .outfitSuggestion)
        XCTAssertTrue(decision.shouldDisambiguate)
        XCTAssertTrue(decision.candidates.contains(where: { $0.intent == .moodSupport }))
        XCTAssertTrue(decision.candidates.contains(where: { $0.intent == .outfitSuggestion }))
    }

    func testMoodToolboxIncludesEmotionSupportInstruction() {
        let instruction = PetConversationToolbox.buildToolsInstruction(
            module: .mood,
            hasWardrobeContext: false,
            role: .kitten
        )
        XCTAssertTrue(instruction.contains("emotion_support"))
        XCTAssertTrue(instruction.contains("先安抚再建议"))
    }

    func testSleepyExpressionDecisionAcrossTimeSegmentsAndStates() {
        var status = PetStatus()
        let timezone = TimeZone(secondsFromGMT: 8 * 3600)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let cases: [(hour: Int, minute: Int, energy: Double, expected: Bool)] = [
            (2, 0, 90, true),     // 深夜
            (5, 59, 90, true),    // 深夜边界
            (6, 30, 70, false),   // 早晨高精力
            (6, 30, 60, true),    // 早晨低精力
            (7, 59, 64, true),    // 早晨边界
            (8, 0, 64, false),    // 进入白天
            (14, 0, 34, true),    // 白天低精力
            (14, 0, 35, false)    // 白天阈值边界
        ]

        for sample in cases {
            status.energy = sample.energy
            let now = calendar.date(from: DateComponents(
                year: 2026,
                month: 1,
                day: 3,
                hour: sample.hour,
                minute: sample.minute
            ))!
            let actual = petChatShouldShowSleepyExpression(status: status, now: now, calendar: calendar)
            XCTAssertEqual(
                actual,
                sample.expected,
                "hour=\(sample.hour), minute=\(sample.minute), energy=\(sample.energy)"
            )
        }
    }

    func testStatusPanelWidgetReflectsPetStatesAndMoodSupportAction() {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.naicha.id
        status.petNames[PetCharacter.naicha.id] = "奶茶"
        status.hunger = 18
        status.energy = 52
        status.hygiene = 66
        status.mood = 31
        status.intimacy = 42

        let allWidget = makeStatusPanelWidget(status: status, kind: .all)
        XCTAssertEqual(allWidget.type, .statusPanel)
        XCTAssertEqual(allWidget.metrics.count, 5)
        XCTAssertTrue(allWidget.metrics.contains(where: { $0.name == "饱食" && $0.value == "18/100" }))
        XCTAssertTrue(allWidget.metrics.contains(where: { $0.name == "饮水" && $0.value == "52/100" }))
        XCTAssertTrue(allWidget.metrics.contains(where: { $0.name == "清洁" && $0.value == "66/100" }))
        XCTAssertTrue(allWidget.metrics.contains(where: { $0.name == "心情" && $0.value == "31/100" }))
        XCTAssertTrue(allWidget.metrics.contains(where: { $0.name == "亲密度" && $0.value == "♥️♥️♡♡♡" }))

        let moodWidget = makeStatusPanelWidget(status: status, kind: .mood)
        XCTAssertTrue(moodWidget.options.contains(where: { $0.command == "mood_support" }))
    }

    func testShopPanelCopyUsesActualCatItems() {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.naicha.id
        status.petNames[PetCharacter.naicha.id] = "奶茶"

        let widget = makeShopPanelWidget(status: status)
        let intro = shopPanelIntroMessage(status: status)

        XCTAssertTrue(widget.title.contains("奶茶"))
        XCTAssertTrue(widget.subtitle?.contains("猫罐头") == true || widget.subtitle?.contains("冻干") == true || widget.subtitle?.contains("猫条") == true)
        XCTAssertTrue(intro.contains("宠物商店"))
        XCTAssertTrue(intro.contains("好不好喵"))
    }

    func testShopPanelCopyUsesActualDogItemsWithoutInventingBone() {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.maomao.id
        status.petNames[PetCharacter.maomao.id] = "毛毛"

        let widget = makeShopPanelWidget(status: status)
        let intro = shopPanelIntroMessage(status: status)

        XCTAssertTrue(widget.title.contains("毛毛"))
        XCTAssertTrue(widget.subtitle?.contains("生骨肉") == true || widget.subtitle?.contains("鸡胸肉") == true || widget.subtitle?.contains("山羊奶") == true)
        XCTAssertFalse(widget.subtitle?.contains("狗骨头") == true)
        XCTAssertFalse(intro.contains("狗骨头"))
        XCTAssertTrue(intro.contains("好不好汪"))
    }
}
