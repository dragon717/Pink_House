import Foundation
import SwiftUI
import Combine
import CloudKit
import CoreLocation

// MARK: - 打卡记录
struct CheckInRecord: Codable, Identifiable {
    let id: String
    let date: Date
    let colors: [String] // 今日穿搭色
    let accessories: String // 小物搭配建议
    let weather: String? // 天气信息
    let location: String? // 位置信息
    let temperature: Double? // 温度
    let season: String? // 季节
    let isAIGenerated: Bool // 是否AI生成
    let petName: String? // 萌宠名字（推荐者）
}

// MARK: - 今日穿搭色数据
struct TodayOutfitColor: Codable {
    let colors: [String] // 颜色数组，如 ["樱花粉", "奶油白"]
    let accessories: String // 小物搭配建议
    let description: String // 描述
    let source: String // 来源：cloudkit/pet/local
    let weather: String? // 天气信息
    let location: String? // 位置信息
    let temperature: Double? // 温度
    let season: String? // 季节
    let petName: String? // 萌宠推荐者名字
}

// MARK: - 每日打卡管理器
@MainActor
final class DailyCheckInManager: ObservableObject {
    static let shared = DailyCheckInManager()
    
    @Published var todayCheckIn: CheckInRecord?
    @Published var consecutiveDays: Int = 0
    @Published var totalDays: Int = 0
    @Published var weekCheckIns: [Bool] = [false, false, false, false, false, false, false] // 本周打卡状态
    @Published var todayOutfitColor: TodayOutfitColor?
    @Published var isLoading = false
    
    // 位置天气信息
    @Published var currentWeather: WeatherData?
    @Published var currentLocation: String = ""
    
    private let checkInKey = "dailyCheckIn.records"
    private let lastCheckInDateKey = "dailyCheckIn.lastDate"
    private let consecutiveDaysKey = "dailyCheckIn.consecutiveDays"
    private let totalDaysKey = "dailyCheckIn.totalDays"
    
    private let container = CKContainer(identifier: "iCloud.bugod2.SkirtMarket")
    
    // 2025年Lolita流行色
    private let trendyColors2025 = [
        "莫兰迪粉", "雾霾蓝", "奶油白", "薄荷绿", "浅鹅黄",
        "薰衣草紫", "珊瑚粉", "香槟金", "珍珠白", "樱花粉",
        "焦糖棕", "奶茶色", "枫叶红", "酒红色", "墨绿色"
    ]
    
    private init() {
        loadCheckInData()
        // 如果今日已打卡，加载今日穿搭色
        if hasCheckedInToday {
            Task {
                await loadTodayOutfitColor()
            }
        }
    }
    
    // MARK: - 从磁盘重新加载（用于备份恢复后）
    func reloadFromDisk() {
        print("🔄 DailyCheckInManager: Reloading from disk...")
        loadCheckInData()
        // 重新计算本周打卡状态
        calculateWeekCheckIns()
        // 如果今日已打卡，加载今日记录
        if hasCheckedInToday {
            let records = loadAllRecords()
            todayCheckIn = records.first(where: { Calendar.current.isDateInToday($0.date) })
        } else {
            todayCheckIn = nil
        }
        // 同步更新魔法任务的登录天数进度
        FeatureUnlockManager.shared.updateLoginDays(totalDays)
        print("🔄 DailyCheckInManager: Synced loginDays to FeatureUnlockManager: \(totalDays)")
        // 通知UI更新
        objectWillChange.send()
        print("✅ DailyCheckInManager: Reload complete. Total days: \(totalDays), Consecutive: \(consecutiveDays)")
    }
    
    // MARK: - 检查今日是否已打卡
    var hasCheckedInToday: Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: lastCheckInDateKey) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(lastDate)
    }
    
    // MARK: - 加载打卡数据
    private func loadCheckInData() {
        consecutiveDays = UserDefaults.standard.integer(forKey: consecutiveDaysKey)
        totalDays = UserDefaults.standard.integer(forKey: totalDaysKey)
        
        // 计算本周打卡状态
        calculateWeekCheckIns()
    }
    
    // MARK: - 计算本周打卡状态
    private func calculateWeekCheckIns() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // 调整为周一为第一天
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) else { return }
        
        var weekStatus: [Bool] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: monday) {
                let hasCheckIn = hasCheckIn(on: date)
                weekStatus.append(hasCheckIn)
            }
        }
        weekCheckIns = weekStatus
    }
    
    // MARK: - 检查某天是否打卡
    private func hasCheckIn(on date: Date) -> Bool {
        // 如果日期是今天，使用hasCheckedInToday快速判断
        if Calendar.current.isDateInToday(date) {
            return hasCheckedInToday
        }
        // 其他日期查询历史记录
        let records = loadAllRecords()
        return records.contains { record in
            Calendar.current.isDate(record.date, inSameDayAs: date)
        }
    }
    
    // MARK: - 执行打卡
    func performCheckIn() async -> CheckInRecord? {
        guard !hasCheckedInToday else {
            return nil
        }
        
        isLoading = true
        
        // 1. 获取位置和天气信息
        await fetchLocationAndWeather()
        
        // 2. 获取今日穿搭色
        let outfitColor = await fetchTodayOutfitColor()
        
        // 3. 获取萌宠名字
        let petName = PetDataManager.shared.status.displayName
        
        // 4. 创建打卡记录
        let record = CheckInRecord(
            id: UUID().uuidString,
            date: Date(),
            colors: outfitColor.colors,
            accessories: outfitColor.accessories,
            weather: currentWeather?.condition.rawValue,
            location: currentLocation,
            temperature: currentWeather?.temperature,
            season: LocationService.shared.getCurrentSeason().displayName,
            isAIGenerated: outfitColor.source == "ai",
            petName: petName
        )
        
        // 5. 更新数据
        todayCheckIn = record
        todayOutfitColor = outfitColor
        
        // 更新连续天数
        updateConsecutiveDays()
        
        // 更新总天数
        totalDays += 1
        UserDefaults.standard.set(totalDays, forKey: totalDaysKey)
        
        // 更新魔法任务进度
        FeatureUnlockManager.shared.updateLoginDays(totalDays)
        
        // 保存最后打卡日期
        UserDefaults.standard.set(Date(), forKey: lastCheckInDateKey)
        
        // 重新计算本周打卡状态
        calculateWeekCheckIns()
        
        isLoading = false
        
        // 6. 保存记录
        saveCheckInRecord(record)
        
        return record
    }
    
    // MARK: - 获取位置和天气
    private func fetchLocationAndWeather() async {
        // 获取位置
        let locationService = LocationService.shared
        if let location = await locationService.getCurrentLocation() {
            currentLocation = locationService.currentCity
            
            // 获取天气
            let weather = await WeatherService.shared.fetchWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                city: locationService.currentCity
            )
            currentWeather = weather
        } else {
            currentLocation = locationService.currentCity
        }
    }
    
    // MARK: - 更新连续天数
    private func updateConsecutiveDays() {
        let calendar = Calendar.current
        
        if let lastDate = UserDefaults.standard.object(forKey: lastCheckInDateKey) as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            let today = calendar.startOfDay(for: Date())
            
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(lastDay, inSameDayAs: yesterday) {
                // 昨天打卡了，连续天数+1
                consecutiveDays += 1
            } else if calendar.isDateInToday(lastDate) {
                // 今天已经打卡，不做处理
                return
            } else {
                // 断签了，重置为1
                consecutiveDays = 1
            }
        } else {
            // 首次打卡
            consecutiveDays = 1
        }
        
        UserDefaults.standard.set(consecutiveDays, forKey: consecutiveDaysKey)
    }
    
    // MARK: - 保存打卡记录
    private func saveCheckInRecord(_ record: CheckInRecord) {
        var records = loadAllRecords()
        records.append(record)
        
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: checkInKey)
        }
    }
    
    // MARK: - 加载所有记录
    private func loadAllRecords() -> [CheckInRecord] {
        guard let data = UserDefaults.standard.data(forKey: checkInKey),
              let records = try? JSONDecoder().decode([CheckInRecord].self, from: data) else {
            return []
        }
        return records
    }
    
    // MARK: - 加载今日穿搭色（用于已打卡状态）
    func loadTodayOutfitColor() async {
        // 先从本地记录中查找今日记录
        let records = loadAllRecords()
        if let todayRecord = records.first(where: { Calendar.current.isDateInToday($0.date) }) {
            todayOutfitColor = TodayOutfitColor(
                colors: todayRecord.colors,
                accessories: todayRecord.accessories,
                description: "",
                source: todayRecord.isAIGenerated ? "ai" : "local",
                weather: todayRecord.weather,
                location: todayRecord.location,
                temperature: todayRecord.temperature,
                season: todayRecord.season,
                petName: todayRecord.petName
            )
            currentLocation = todayRecord.location ?? ""
        } else {
            // 如果没有本地记录，尝试获取
            let outfit = await fetchTodayOutfitColor()
            todayOutfitColor = outfit
        }
    }
    
    // MARK: - 获取今日穿搭色
    private func fetchTodayOutfitColor() async -> TodayOutfitColor {
        // 1. 首先尝试从CloudKit获取
        if let cloudKitColor = await fetchFromCloudKit() {
            return cloudKitColor
        }
        
        // 2. 如果CloudKit没有，使用本地智能算法生成（基于位置、天气、季节、流行色）
        return await generateLocally()
    }
    
    // MARK: - 从CloudKit获取
    private func fetchFromCloudKit() async -> TodayOutfitColor? {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        // 获取当前省份
        let province = LocationService.shared.currentProvince
        
        let recordID = CKRecord.ID(recordName: "outfit_\(province)_\(dateString)")
        let database = container.publicCloudDatabase
        
        do {
            let record = try await database.record(for: recordID)
            
            guard let colors = record["colors"] as? [String],
                  let accessories = record["accessories"] as? String else {
                return nil
            }
            
            return TodayOutfitColor(
                colors: colors,
                accessories: accessories,
                description: record["description"] as? String ?? "",
                source: "cloudkit",
                weather: currentWeather?.condition.rawValue,
                location: currentLocation,
                temperature: currentWeather?.temperature,
                season: LocationService.shared.getCurrentSeason().displayName,
                petName: PetDataManager.shared.status.displayName
            )
        } catch {
            print("CloudKit获取失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 本地智能生成穿搭色
    private func generateLocally() async -> TodayOutfitColor {
        let season = LocationService.shared.getCurrentSeason()
        let weather = currentWeather
        let petName = PetDataManager.shared.status.displayName
        
        // 根据多种因素选择颜色
        var selectedColors: [String] = []
        
        // 1. 首先考虑天气
        if let weather = weather {
            let weatherColors = weather.condition.recommendedColors
            selectedColors.append(weatherColors.randomElement()!)
            
            // 温度也影响颜色选择
            let tempColors = weather.temperatureColors
            selectedColors.append(tempColors.randomElement()!)
        }
        
        // 2. 考虑季节
        let seasonColors = season.recommendedColors
        selectedColors.append(seasonColors.randomElement()!)
        
        // 3. 加入2025流行色
        selectedColors.append(trendyColors2025.randomElement()!)
        
        // 去重并限制数量
        selectedColors = Array(Set(selectedColors)).prefix(3).map { $0 }
        
        // 生成搭配建议
        let accessories = generateAccessoriesAdvice(season: season, weather: weather)
        
        // 生成描述
        let description = generateDescription(season: season, weather: weather, colors: selectedColors)
        
        return TodayOutfitColor(
            colors: selectedColors,
            accessories: accessories,
            description: description,
            source: "pet",
            weather: weather?.condition.rawValue,
            location: currentLocation.isEmpty ? nil : currentLocation,
            temperature: weather?.temperature,
            season: season.displayName,
            petName: petName
        )
    }
    
    // MARK: - 生成小物搭配建议
    private func generateAccessoriesAdvice(season: Season, weather: WeatherData?) -> String {
        var advice: [String] = []
        
        // 根据季节
        switch season {
        case .spring:
            advice.append("搭配花朵发饰和蕾丝手套")
        case .summer:
            advice.append("选择草编包和遮阳帽")
        case .autumn:
            advice.append("搭配贝雷帽和围巾")
        case .winter:
            advice.append("选择毛绒耳罩和保暖手套")
        }
        
        // 根据天气
        if let weather = weather {
            switch weather.condition {
            case .sunny:
                advice.append("佩戴太阳镜和防晒伞")
            case .lightRain, .moderateRain, .heavyRain, .thunderstorm:
                advice.append("准备可爱的雨靴和透明雨伞")
            case .snow:
                advice.append("选择保暖的毛绒包包")
            default:
                break
            }
        }
        
        // 通用建议
        let generalAdvice = [
            "珍珠项链增添优雅气质",
            "蝴蝶结发夹点缀发型",
            "蕾丝袜搭配小皮鞋",
            "精致的手提包提升整体感"
        ]
        advice.append(generalAdvice.randomElement()!)
        
        return advice.joined(separator: "，")
    }
    
    // MARK: - 生成描述
    private func generateDescription(season: Season, weather: WeatherData?, colors: [String]) -> String {
        var parts: [String] = []
        
        // 季节描述
        switch season {
        case .spring:
            parts.append("春日")
        case .summer:
            parts.append("夏日")
        case .autumn:
            parts.append("秋日")
        case .winter:
            parts.append("冬日")
        }
        
        // 天气描述
        if let weather = weather {
            parts.append(weather.condition.rawValue)
        }
        
        // 风格描述
        let styles = ["甜美", "优雅", "复古", "清新", "浪漫"]
        parts.append(styles.randomElement()!)
        
        return parts.joined(separator: "") + "的Lolita配色"
    }
}

// MARK: - AI响应结构
struct OutfitColorResponse {
    let colors: [String]
    let accessories: String
    let description: String
}

// MARK: - PetAIService扩展
extension PetAIService {
    func generateOutfitColors(prompt: String) async throws -> OutfitColorResponse {
        // 这里应该调用实际的AI服务
        // 暂时返回模拟数据
        return OutfitColorResponse(
            colors: ["樱花粉", "奶油白", "浅金色"],
            accessories: "搭配粉色蝴蝶结发饰、白色蕾丝手套和珍珠项链",
            description: "甜美优雅的春日樱花配色"
        )
    }
}
