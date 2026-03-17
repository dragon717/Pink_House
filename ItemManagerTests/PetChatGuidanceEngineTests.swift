import XCTest
@testable import ItemManager

final class PetChatGuidanceEngineTests: XCTestCase {
    func testWardrobeContextAttachmentHeuristics() {
        XCTAssertFalse(WardrobeContextManager.shared.shouldAttachWardrobeContext(for: "你好，今天心情不错"))
        XCTAssertTrue(WardrobeContextManager.shared.shouldAttachWardrobeContext(for: "帮我搭配一套约会穿搭"))
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
}
