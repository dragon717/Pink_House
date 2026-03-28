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
            title: "衣橱搭配",
            subtitle: """
            外套：\(names(selection.outerwears, fallback: outerwearFallback(weather)))
            裙子：\(names(selection.dresses, fallback: "无"))
            鞋子：\(names(selection.shoes, fallback: "无"))
            伞具：\(names(selection.umbrellas, fallback: "无"))
            """
        )

        let actions = PetWidgetData(
            type: .quickOptions,
            title: "想换一种：",
            options: [
                PetWidgetOption(title: "更防雨", command: "weather_guidance:rain", icon: "cloud.rain"),
                PetWidgetOption(title: "更甜美", command: "weather_guidance:sweet", icon: "heart"),
                PetWidgetOption(title: "先安慰我", command: "mood_support", icon: "sparkles")
            ]
        )

        let container = PetWidgetData(
            type: .container,
            title: "天气穿搭",
            subtitle: "可继续微调",
            children: [weatherCard, recommendationCard, actions]
        )

        return [container]
    }

    private static func weatherTitle(_ weather: WeatherData?) -> String {
        guard let weather else { return "天气" }
        return "\(weather.city) · \(weather.condition.rawValue)"
    }

    private static func weatherSubtitle(_ weather: WeatherData?) -> String {
        guard let weather else { return "先按稳妥方案推荐。" }
        let feelsLike = Int(weather.feelsLikeTemperature.rounded())
        if feelsLike >= 24, weather.windSpeed < 4 {
            return "体感约\(feelsLike)°C，通常不用特地带外套。"
        }
        return "体感约\(feelsLike)°C，风速\(String(format: "%.1f m/s", weather.windSpeed))。"
    }

    private static func weatherMetrics(_ weather: WeatherData?) -> [PetWidgetMetric] {
        guard let weather else {
            return [
                PetWidgetMetric(name: "气温", value: "--"),
                PetWidgetMetric(name: "体感", value: "--"),
                PetWidgetMetric(name: "湿度", value: "--"),
                PetWidgetMetric(name: "风速", value: "--")
            ]
        }
        return [
            PetWidgetMetric(name: "气温", value: "\(Int(weather.temperature.rounded()))°C"),
            PetWidgetMetric(name: "体感", value: "\(Int(weather.feelsLikeTemperature.rounded()))°C"),
            PetWidgetMetric(name: "湿度", value: "\(weather.humidity)%"),
            PetWidgetMetric(name: "风速", value: String(format: "%.1f m/s", weather.windSpeed))
        ]
    }

    private static func outerwearFallback(_ weather: WeatherData?) -> String {
        guard let weather else { return "建议先找一件薄外套" }
        if weather.feelsLikeTemperature < 18 {
            return "建议优先找一件外套"
        }
        if weather.feelsLikeTemperature >= 24, weather.windSpeed < 4 {
            return "这会儿大概率不用带外套"
        }
        return "可选轻薄开衫"
    }

    private static func names(_ items: [Clothing], fallback: String) -> String {
        guard !items.isEmpty else { return fallback }
        return items.prefix(2).map(\.name).joined(separator: "、")
    }
}
