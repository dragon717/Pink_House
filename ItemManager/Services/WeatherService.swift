import Foundation
import CoreLocation
import Combine

// MARK: - 天气数据模型
struct WeatherData: Codable {
    let temperature: Double
    let apparentTemperature: Double?
    let condition: WeatherCondition
    let humidity: Int
    let windSpeed: Double
    let city: String
    let updateTime: Date

    init(
        temperature: Double,
        apparentTemperature: Double? = nil,
        condition: WeatherCondition,
        humidity: Int,
        windSpeed: Double,
        city: String,
        updateTime: Date
    ) {
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.city = city
        self.updateTime = updateTime
    }
}

// MARK: - 天气状况枚举
enum WeatherCondition: String, Codable, CaseIterable {
    case sunny = "晴"
    case cloudy = "多云"
    case overcast = "阴"
    case lightRain = "小雨"
    case moderateRain = "中雨"
    case heavyRain = "大雨"
    case thunderstorm = "雷雨"
    case snow = "雪"
    case fog = "雾"
    case unknown = "未知"
    
    var iconName: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.sun.fill"
        case .overcast: return "cloud.fill"
        case .lightRain, .moderateRain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .snow: return "snowflake"
        case .fog: return "cloud.fog.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var localizedDisplayName: String {
        rawValue.appLocalized
    }
    
    var color: String {
        switch self {
        case .sunny: return "sunny"
        case .cloudy, .overcast: return "cloudy"
        case .lightRain, .moderateRain, .heavyRain, .thunderstorm: return "rainy"
        case .snow: return "snowy"
        case .fog: return "foggy"
        case .unknown: return "gray"
        }
    }
    
    // 根据天气推荐的颜色
    var recommendedColors: [String] {
        switch self {
        case .sunny:
            return ["明亮黄", "天空蓝", "珊瑚粉", "薄荷绿", "白色"]
        case .cloudy, .overcast:
            return ["雾霾蓝", "浅灰", "薰衣草紫", "米色", "淡粉"]
        case .lightRain, .moderateRain, .heavyRain, .thunderstorm:
            return ["深蓝", "墨绿", "酒红", "深灰", "藏青"]
        case .snow:
            return ["雪白", "冰蓝", "银白", "淡粉", "浅紫"]
        case .fog:
            return ["米色", "浅灰", "淡粉", "雾霾蓝", "奶油白"]
        case .unknown:
            return ["樱花粉", "奶油白", "薰衣草紫"]
        }
    }
}

// MARK: - 天气服务
@MainActor
class WeatherService: ObservableObject {
    static let shared = WeatherService()
    
    @Published var currentWeather: WeatherData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 使用Open-Meteo免费天气API（无需API Key）
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    
    private init() {}
    
    // MARK: - 获取当前天气
    func fetchWeather(latitude: Double, longitude: Double, city: String = "当前位置") async -> WeatherData? {
        isLoading = true
        defer { isLoading = false }
        
        let urlString = "\(baseURL)?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的URL"
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            
            let weather = WeatherData(
                temperature: response.current.temperature_2m,
                apparentTemperature: response.current.apparent_temperature,
                condition: mapWeatherCode(response.current.weather_code),
                humidity: response.current.relative_humidity_2m,
                windSpeed: response.current.wind_speed_10m,
                city: city,
                updateTime: Date()
            )
            
            self.currentWeather = weather
            return weather
            
        } catch {
            print("获取天气失败: \(error)")
            errorMessage = "获取天气失败"
            return nil
        }
    }
    
    // MARK: - 根据城市名获取天气（使用地理编码）
    func fetchWeatherForCity(_ cityName: String) async -> WeatherData? {
        // 先获取城市坐标
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.geocodeAddressString(cityName)
            guard let location = placemarks.first?.location else {
                errorMessage = "无法找到该城市"
                return nil
            }
            
            return await fetchWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                city: cityName
            )
        } catch {
            print("地理编码失败: \(error)")
            errorMessage = "地理编码失败"
            return nil
        }
    }
    
    // MARK: - 天气代码映射
    private func mapWeatherCode(_ code: Int) -> WeatherCondition {
        // Open-Meteo天气代码映射
        // https://open-meteo.com/en/docs
        switch code {
        case 0: return .sunny
        case 1, 2, 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55: return .lightRain
        case 56, 57: return .lightRain
        case 61, 63, 65: return .moderateRain
        case 66, 67: return .moderateRain
        case 71, 73, 75, 77: return .snow
        case 80, 81, 82: return .heavyRain
        case 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .unknown
        }
    }
}

// MARK: - Open-Meteo API响应模型
struct OpenMeteoResponse: Codable {
    let current: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature_2m: Double
    let apparent_temperature: Double
    let relative_humidity_2m: Int
    let weather_code: Int
    let wind_speed_10m: Double
}

// MARK: - 温度适配建议
extension WeatherData {
    var feelsLikeTemperature: Double {
        if let apparentTemperature {
            return apparentTemperature
        }

        var adjusted = temperature

        if temperature <= 18 {
            adjusted -= min(max(windSpeed - 1.5, 0) * 0.6, 4.0)
        } else if temperature >= 24, humidity >= 70 {
            adjusted += humidity >= 80 ? 1.5 : 0.8
        }

        if windSpeed >= 6 {
            adjusted -= 0.8
        }

        return adjusted
    }

    // 根据温度获取穿搭建议
    var temperatureAdvice: String {
        switch feelsLikeTemperature {
        case ..<0:
            return "极寒天气，建议穿厚实的外套，注意保暖"
        case 0..<10:
            return "天气寒冷，建议穿大衣或厚外套"
        case 10..<20:
            return "天气凉爽，适合穿薄外套或针织衫"
        case 20..<28:
            return "温度适宜，可以穿轻薄的裙装"
        case 28..<35:
            return "天气较热，建议穿清凉透气的衣物"
        default:
            return "天气炎热，注意防暑降温"
        }
    }
    
    // 获取温度对应的季节色系
    var temperatureColors: [String] {
        switch temperature {
        case ..<10:
            return ["深红", "酒红", "焦糖棕", "藏青", "墨绿"]
        case 10..<20:
            return ["枫叶红", "奶茶色", "杏色", "驼色", "橄榄绿"]
        case 20..<28:
            return ["樱花粉", "薄荷绿", "天空蓝", "薰衣草紫", "奶油白"]
        default:
            return ["海洋蓝", "薄荷绿", "珍珠白", "浅粉", "天蓝"]
        }
    }
}
