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
        clothing.accessoryItems = [AccessoryItem(name: "草莓发夹", price: 29)]
        
        let json = WardrobeContextManager.shared.generateRelevantItemsJSON(
            query: "帮我找粉色裙子",
            clothings: [clothing],
            maxItems: 5
        )
        
        XCTAssertTrue(json.contains("\"name\""))
        XCTAssertTrue(json.contains("\"features\""))
        XCTAssertFalse(json.contains("\"id\""))
        XCTAssertFalse(json.contains("\"query\""))
        XCTAssertFalse(json.contains("价格"))
    }

    func testWeatherQueryPrefersDressShoeUmbrellaContext() {
        let dress = Clothing(name: "莓莓JSK", types: "JSK")
        let shoe = Clothing(name: "奶油玛丽珍鞋", types: "鞋")
        let umbrella = Clothing(name: "透明雨伞", types: "配饰")
        let unrelated = Clothing(name: "发卡收纳盒", types: "杂物")

        let json = WardrobeContextManager.shared.generateRelevantItemsJSON(
            query: "今天下雨，帮我看天气穿搭",
            clothings: [dress, shoe, umbrella, unrelated],
            maxItems: 3
        )

        XCTAssertTrue(json.contains("JSK"))
        XCTAssertTrue(json.contains("玛丽珍"))
        XCTAssertTrue(json.contains("雨伞"))
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
        let dress = Clothing(name: "花嫁JSK", types: "JSK")
        let shoe = Clothing(name: "复古玛丽珍鞋", types: "鞋子")
        let umbrella = Clothing(name: "透明雨伞", types: "配饰")
        
        let result = PetChatGuidanceEngine.pickWeatherOutfitItems(from: [dress, shoe, umbrella])
        
        XCTAssertTrue(result.dresses.contains(where: { $0.id == dress.id }))
        XCTAssertTrue(result.shoes.contains(where: { $0.id == shoe.id }))
        XCTAssertTrue(result.umbrellas.contains(where: { $0.id == umbrella.id }))
        XCTAssertEqual(result.combinedItems.count, 3)
    }
    
    func testBuildWeatherAdviceContainsRainHint() {
        let dress = Clothing(name: "薄荷JSK", types: "JSK")
        let weather = WeatherData(
            temperature: 16,
            condition: .moderateRain,
            humidity: 80,
            windSpeed: 3.2,
            city: "上海",
            updateTime: Date()
        )
        let selection = WeatherWardrobeSelection(dresses: [dress], shoes: [], umbrellas: [])
        
        let text = PetChatGuidanceEngine.buildWeatherAdvice(weather: weather, selection: selection)
        
        XCTAssertTrue(text.contains("中雨"))
        XCTAssertTrue(text.contains("降水风险"))
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
}
