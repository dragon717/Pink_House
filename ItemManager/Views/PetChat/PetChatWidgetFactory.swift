import Foundation

enum PetChatWidgetFactory {
    static func weatherGuidanceWidgets(
        weather: WeatherData?,
        selection: WeatherWardrobeSelection
    ) -> [PetWidgetData] {
        let weatherCard = PetWidgetData(
            type: .weatherCard,
            title: weatherTitle(weather),
            subtitle: weatherSubtitle(weather),
            metrics: weatherMetrics(weather)
        )

        let recommendationCard = PetWidgetData(
            type: .insightCard,
            title: "衣橱命中",
            subtitle: """
            裙子：\(names(selection.dresses, fallback: "未命中"))
            鞋子：\(names(selection.shoes, fallback: "未命中"))
            伞具：\(names(selection.umbrellas, fallback: "未命中"))
            """
        )

        let actions = PetWidgetData(
            type: .quickOptions,
            title: "继续告诉我你的偏好：",
            options: [
                PetWidgetOption(title: "A. 更防雨一点", command: "ask:请按雨天优先再给我一套更稳妥的穿搭。", icon: "cloud.rain"),
                PetWidgetOption(title: "B. 更甜美一点", command: "ask:请保留天气因素，改成更甜美的搭配。", icon: "heart"),
                PetWidgetOption(title: "C. 先安慰我再推荐", command: "mood_support", icon: "sparkles")
            ]
        )

        let container = PetWidgetData(
            type: .container,
            title: "天气穿搭面板",
            subtitle: "可继续微调风格",
            children: [weatherCard, recommendationCard, actions]
        )

        return [container]
    }

    private static func weatherTitle(_ weather: WeatherData?) -> String {
        guard let weather else { return "天气卡片（未获取到实时天气）" }
        return "\(weather.city) \(weather.condition.rawValue)"
    }

    private static func weatherSubtitle(_ weather: WeatherData?) -> String {
        guard let weather else { return "先按稳妥方案推荐，稍后可重试天气查询。" }
        return "体感参考：\(Int(weather.temperature))°C，穿搭会优先兼顾舒适和场景。"
    }

    private static func weatherMetrics(_ weather: WeatherData?) -> [PetWidgetMetric] {
        guard let weather else {
            return [
                PetWidgetMetric(name: "温度", value: "--"),
                PetWidgetMetric(name: "湿度", value: "--"),
                PetWidgetMetric(name: "风速", value: "--")
            ]
        }
        return [
            PetWidgetMetric(name: "温度", value: "\(Int(weather.temperature))°C"),
            PetWidgetMetric(name: "湿度", value: "\(weather.humidity)%"),
            PetWidgetMetric(name: "风速", value: String(format: "%.1f m/s", weather.windSpeed))
        ]
    }

    private static func names(_ items: [Clothing], fallback: String) -> String {
        guard !items.isEmpty else { return fallback }
        return items.prefix(2).map(\.name).joined(separator: "、")
    }
}
