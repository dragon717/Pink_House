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
}
