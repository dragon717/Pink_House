import XCTest
@testable import ItemManager

final class PetChatGuidanceEngineTests: XCTestCase {
    func testWardrobeContextAttachmentHeuristics() {
        XCTAssertFalse(WardrobeContextManager.shared.shouldAttachWardrobeContext(for: "你好，今天心情不错"))
        XCTAssertTrue(WardrobeContextManager.shared.shouldAttachWardrobeContext(for: "帮我搭配一套约会穿搭"))
    }

    func testWardrobeContextAttachmentByModule() {
        XCTAssertFalse(
            WardrobeContextManager.shared.shouldAttachWardrobeContext(
                for: .mood,
                query: "我现在有点焦虑，先安慰我"
            )
        )
        XCTAssertTrue(
            WardrobeContextManager.shared.shouldAttachWardrobeContext(
                for: .weather,
                query: "今天天气怎么样"
            )
        )
    }
    
    func testRelevantWardrobeJSONContainsNameAndFeaturesOnly() {
        let clothing = Clothing(name: "草莓JSK", types: "JSK", colors: "粉色", accessories: "发带")
        clothing.tags = [Tag(name: "甜系")]
        clothing.accessoryItems = [AccessoryItem(name: "草莓发夹", price: 29)]
        
        let json = WardrobeContextManager.shared.generateRelevantItemsJSON(
            query: "帮我找粉色裙子",
            clothings: [clothing],
            maxItems: 5
        )
        
        XCTAssertTrue(json.contains("\"name\""))
        XCTAssertTrue(json.contains("\"features\""))
        XCTAssertTrue(json.contains("甜系"))
        XCTAssertFalse(json.contains("\"id\""))
        XCTAssertFalse(json.contains("\"query\""))
        XCTAssertFalse(json.contains("价格"))
    }

    func testWeatherQueryPrefersDressOuterwearShoeUmbrellaContext() {
        let outerwear = Clothing(name: "奶油云朵罩衫", types: "罩衫")
        outerwear.tags = [Tag(name: "薄针织")]
        let dress = Clothing(name: "莓莓JSK", types: "JSK")
        let shoe = Clothing(name: "奶油玛丽珍鞋", types: "鞋")
        let umbrella = Clothing(name: "透明雨伞", types: "配饰")
        let unrelated = Clothing(name: "发卡收纳盒", types: "杂物")

        let json = WardrobeContextManager.shared.generateRelevantItemsJSON(
            query: "今天下雨，帮我看天气穿搭",
            clothings: [outerwear, dress, shoe, umbrella, unrelated],
            maxItems: 5
        )

        XCTAssertTrue(json.contains("罩衫") || json.contains("薄针织"))
        XCTAssertTrue(json.contains("JSK"))
        XCTAssertTrue(json.contains("玛丽珍"))
        XCTAssertTrue(json.contains("雨伞"))
    }

    func testRequestedOuterwearOutfitQueryKeepsOuterwearInCandidateJSON() {
        let cardigan = Clothing(name: "奶油云朵开衫", types: "针织开衫", colors: "米白")
        cardigan.tags = [Tag(name: "通勤披肩")]

        let jsk = Clothing(name: "草莓JSK", types: "JSK", colors: "粉色")
        let op = Clothing(name: "铃兰OP", types: "OP", colors: "蓝色")
        let brooch = Clothing(name: "兔兔胸针", types: "小物")
        let socks = Clothing(name: "花边袜", types: "小物")

        let json = WardrobeContextManager.shared.generateRelevantItemsJSON(
            query: "帮我来一套开衫穿搭",
            clothings: [jsk, op, brooch, socks, cardigan],
            maxItems: 3
        )

        XCTAssertTrue(json.contains("奶油云朵开衫"))
        XCTAssertTrue(json.contains("草莓JSK") || json.contains("铃兰OP"))
    }
    
    func testHumanizerRemovesJSONCodeStyle() {
        let raw = """
        ```json
        {
          "message": "DeepSeek建议：今天这套会很温柔",
          "style": "甜美",
          "occasion": "约会",
          "recommendations": ["奶白JSK", "玛丽珍鞋", "透明雨伞"]
        }
        ```
        """
        
        let text = PetResponseHumanizer.humanize(raw)
        
        XCTAssertTrue(text.contains("今天这套会很温柔"))
        XCTAssertTrue(text.contains("风格甜美"))
        XCTAssertFalse(text.contains("DeepSeek"))
        XCTAssertFalse(text.contains("{"))
        XCTAssertFalse(text.contains("```"))
    }

    func testHumanizerWithPersonaFiltersTechnicalWords() {
        let persona = PetPersonaRegistry.profile(for: .kitten, petName: "奶茶")
        let text = PetResponseHumanizer.humanize(
            "我是AI助手，DeepSeek建议你先休息。",
            persona: persona,
            recentAssistantReplies: []
        )

        XCTAssertFalse(text.localizedCaseInsensitiveContains("ai"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("deepseek"))
    }

    func testHumanizerStripsProviderNamesInRawText() {
        let text = PetResponseHumanizer.humanize("OpenAI和Gemini都建议你早点休息。")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("openai"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("gemini"))
    }
    
    func testPickWeatherOutfitItemsFindsDressShoeUmbrella() {
        let outerwear = Clothing(name: "奶油针织开衫", types: "外套")
        let dress = Clothing(name: "花嫁JSK", types: "JSK")
        let shoe = Clothing(name: "复古玛丽珍鞋", types: "鞋子")
        let umbrella = Clothing(name: "透明雨伞", types: "配饰")
        
        let result = PetChatGuidanceEngine.pickWeatherOutfitItems(from: [outerwear, dress, shoe, umbrella])
        
        XCTAssertTrue(result.outerwears.contains(where: { $0.id == outerwear.id }))
        XCTAssertTrue(result.dresses.contains(where: { $0.id == dress.id }))
        XCTAssertTrue(result.shoes.contains(where: { $0.id == shoe.id }))
        XCTAssertTrue(result.umbrellas.contains(where: { $0.id == umbrella.id }))
        XCTAssertEqual(result.combinedItems.count, 4)
    }

    func testPickWeatherOutfitItemsMatchesOuterwearFromTagsAndType() {
        let outerwear = Clothing(name: "奶油云朵", types: "罩衫")
        outerwear.tags = [Tag(name: "薄针织"), Tag(name: "春日外搭")]
        outerwear.note = "早晚降温时穿"
        let dress = Clothing(name: "铃兰JSK", types: "JSK")

        let result = PetChatGuidanceEngine.pickWeatherOutfitItems(from: [outerwear, dress])

        XCTAssertTrue(result.outerwears.contains(where: { $0.id == outerwear.id }))
    }

    func testSemanticProfileInfersLengthMaterialSeasonAndOccasion() {
        let clothing = Clothing(name: "古典茶会OP", types: "OP", colors: "酒红", length: "108cm")
        clothing.tags = [Tag(name: "秋冬"), Tag(name: "茶会")]
        clothing.note = "羊毛感长款，很适合正式场合"

        let profile = ClothingSemanticAnalyzer.profile(for: clothing)

        XCTAssertEqual(profile.category, .dress)
        XCTAssertEqual(profile.length, .long)
        XCTAssertTrue(profile.materials.contains(.wool))
        XCTAssertTrue(profile.seasons.contains(.winter) || profile.seasons.contains(.autumn))
        XCTAssertTrue(profile.occasions.contains("茶会") || profile.occasions.contains("正式"))
    }

    func testWeatherSelectionPrefersRainSafeShoesInRain() {
        let dress = Clothing(name: "莓果JSK", types: "JSK", colors: "粉色")
        let rainBoots = Clothing(name: "防水雨靴", types: "鞋子", colors: "黑色")
        rainBoots.note = "雨天稳妥"
        let suedeShoes = Clothing(name: "奶白麂皮玛丽珍", types: "鞋子", colors: "白色")
        suedeShoes.note = "晴天穿更合适"
        let umbrella = Clothing(name: "透明晴雨伞", types: "配饰")

        let weather = WeatherData(
            temperature: 16,
            apparentTemperature: 14,
            condition: .moderateRain,
            humidity: 88,
            windSpeed: 5.0,
            city: "上海",
            updateTime: Date()
        )

        let result = PetChatGuidanceEngine.pickWeatherOutfitItems(
            from: [dress, rainBoots, suedeShoes, umbrella],
            weather: weather
        )

        XCTAssertEqual(result.shoes.first?.id, rainBoots.id)
    }
    
    func testBuildWeatherAdviceContainsFeelsLikeAndOuterwearHint() {
        let outerwear = Clothing(name: "奶油开衫", types: "外套")
        let dress = Clothing(name: "薄荷JSK", types: "JSK")
        let weather = WeatherData(
            temperature: 11,
            apparentTemperature: 9,
            condition: .moderateRain,
            humidity: 80,
            windSpeed: 4.1,
            city: "上海",
            updateTime: Date()
        )
        let selection = WeatherWardrobeSelection(outerwears: [outerwear], dresses: [dress], shoes: [], umbrellas: [])
        
        let text = PetChatGuidanceEngine.buildWeatherAdvice(weather: weather, selection: selection)
        
        XCTAssertTrue(text.contains("中雨"))
        XCTAssertTrue(text.contains("体感大约9°C"))
        XCTAssertTrue(text.contains("风速4.1m/s"))
        XCTAssertTrue(text.contains("外套"))
        XCTAssertTrue(text.contains("奶油开衫"))
        XCTAssertTrue(text.contains("薄荷JSK"))
    }

    func testWardrobeContextBlockIsCappedForPerformance() {
        var clothings: [Clothing] = []
        for index in 0..<40 {
            let item = Clothing(
                name: "测试裙装\(index)",
                types: "JSK",
                colors: "粉色,白色",
                accessories: "发带,胸针,手袖,袜子,包包"
            )
            clothings.append(item)
        }

        let block = WardrobeContextManager.shared.buildWardrobeContextBlockIfNeeded(
            query: "帮我搭一套明天出门穿搭",
            clothings: clothings,
            maxItems: 12
        )

        XCTAssertNotNil(block)
        XCTAssertLessThanOrEqual(block?.count ?? 0, 2400)
    }

    func testSearchResolutionLearnsUserTagsForGenericOuterwearQuery() {
        let cardigan = Clothing(name: "奶油云朵开衫", types: "针织开衫", colors: "米白")
        cardigan.tags = [Tag(name: "通勤披肩"), Tag(name: "奶油针织")]
        cardigan.note = "秋天外搭用"

        let jsk = Clothing(name: "草莓JSK", types: "JSK", colors: "粉色")

        let resolution = WardrobeContextManager.shared.resolveSearch(
            query: "帮我找外套上衣",
            clothings: [cardigan, jsk]
        )

        XCTAssertTrue(resolution.results.contains(where: { $0.id == cardigan.id }))
        XCTAssertTrue(resolution.matchedTerms.contains(where: { $0.contains("开衫") || $0.contains("披肩") || $0.contains("针织") }))
        XCTAssertTrue(resolution.suggestedPrompt.contains("标签"))
    }

    func testSearchResolutionCanUseLengthAndSemanticHints() {
        let longDress = Clothing(name: "古典长OP", types: "OP", colors: "酒红", length: "108cm")
        longDress.tags = [Tag(name: "秋冬"), Tag(name: "茶会")]
        longDress.note = "羊毛感长款"
        let shortDress = Clothing(name: "夏日短JSK", types: "JSK", colors: "蓝色", length: "88cm")
        shortDress.note = "轻薄春夏"

        let resolution = WardrobeContextManager.shared.resolveSearch(
            query: "帮我找秋冬长款茶会裙",
            clothings: [shortDress, longDress]
        )

        XCTAssertEqual(resolution.results.first?.id, longDress.id)
    }

    func testWardrobeContextBlockIncludesVocabularyLearning() {
        let cardigan = Clothing(name: "奶油云朵开衫", types: "针织开衫")
        cardigan.tags = [Tag(name: "通勤披肩")]

        let block = WardrobeContextManager.shared.buildWardrobeContextBlockIfNeeded(
            query: "帮我找外套上衣",
            clothings: [cardigan],
            maxItems: 6
        )

        XCTAssertTrue(block?.contains("用户衣橱词汇偏好") == true)
        XCTAssertTrue(block?.contains("通勤披肩") == true || block?.contains("针织开衫") == true)
    }

    func testOutfitHarmonyReplacesClashingShoesWithNeutralOption() {
        let dress = Clothing(name: "夜空JSK", types: "JSK", colors: "蓝色")
        let purpleShoes = Clothing(name: "葡萄玛丽珍", types: "鞋子", colors: "紫色")
        let whiteShoes = Clothing(name: "奶油玛丽珍", types: "鞋子", colors: "白色")

        let result = OutfitColorHarmonyEngine.refineSelection(
            [dress, purpleShoes],
            within: [dress, purpleShoes, whiteShoes]
        )

        XCTAssertTrue(result.contains(where: { $0.id == dress.id }))
        XCTAssertTrue(result.contains(where: { $0.id == whiteShoes.id }))
        XCTAssertFalse(result.contains(where: { $0.id == purpleShoes.id }))
    }

    func testOutfitHarmonyKeepsNonNeutralFamiliesWithinTwo() {
        let dress = Clothing(name: "草莓JSK", types: "JSK", colors: "粉色")
        let blueOuterwear = Clothing(name: "海盐开衫", types: "开衫", colors: "蓝色")
        let redAccessory = Clothing(name: "莓果发带", types: "发带", colors: "红色")
        let blackShoes = Clothing(name: "夜色玛丽珍", types: "鞋子", colors: "黑色")
        let whiteAccessory = Clothing(name: "奶油手袖", types: "手袖", colors: "白色")

        let result = OutfitColorHarmonyEngine.refineSelection(
            [dress, blueOuterwear, redAccessory, blackShoes],
            within: [dress, blueOuterwear, redAccessory, blackShoes, whiteAccessory]
        )

        XCTAssertLessThanOrEqual(
            OutfitColorHarmonyEngine.dominantNonNeutralFamilyNames(in: result).count,
            2
        )
    }
}
