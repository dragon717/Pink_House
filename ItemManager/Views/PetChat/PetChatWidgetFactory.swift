import Foundation

enum PetChatWidgetFactory {
    static func weatherGuidanceWidgets(
        weather: WeatherData?,
        selection: WeatherWardrobeSelection
    ) -> [PetWidgetData] {
        let actions = PetWidgetData(
            type: .quickOptions,
            title: actionTitle(weather, selection: selection),
            subtitle: weatherSubtitle(weather),
            options: [
                PetWidgetOption(title: "更防雨", command: "weather_guidance:rain", icon: "cloud.rain"),
                PetWidgetOption(title: "更甜美", command: "weather_guidance:sweet", icon: "heart"),
                PetWidgetOption(title: "先安慰我", command: "mood_support", icon: "sparkles")
            ]
        )
        return [actions]
    }

    private static func actionTitle(_ weather: WeatherData?, selection: WeatherWardrobeSelection) -> String {
        if let weather {
            return "\(weather.city)这套先这样，要不要继续微调？"
        }

        if !selection.combinedItems.isEmpty {
            return "这套先给你摆在上面啦，要不要继续微调？"
        }

        return "想换一种："
    }

    private static func weatherSubtitle(_ weather: WeatherData?) -> String {
        guard let weather else { return "先按稳妥方案推荐。" }
        let feelsLike = Int(weather.feelsLikeTemperature.rounded())
        if feelsLike >= 24, weather.windSpeed < 4 {
            return "体感约\(feelsLike)°C，通常不用特地带外套。"
        }
        return "体感约\(feelsLike)°C，风速\(String(format: "%.1f m/s", weather.windSpeed))。"
    }
}
