import Foundation
import SwiftUI
import Combine
import CloudKit
import CoreLocation

// MARK: - 打卡记录
struct CheckInRecord: Codable, Identifiable {
    let id: String
    let date: Date
    let colors: [String] // 今日穿搭色名称数组（保持兼容）
    let colorHexes: [String?] // 颜色 hex 值数组（AI生成时会有）
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
    let colors: [ColorInfo] // 颜色数组，包含名称和可选的 hex 值
    let accessories: String // 小物搭配建议
    let description: String // 描述
    let source: String // 来源：cloudkit/pet/local/ai
    let weather: String? // 天气信息
    let location: String? // 位置信息
    let temperature: Double? // 温度
    let season: String? // 季节
    let petName: String? // 萌宠推荐者名字
    
    /// 获取颜色名称数组（用于兼容旧代码）
    var colorNames: [String] {
        return colors.map { $0.name }
    }
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
            colors: outfitColor.colorNames,
            colorHexes: outfitColor.colors.map { $0.hex },
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
            // 将颜色和 hex 值组合成 ColorInfo 数组
            let colorInfos: [ColorInfo] = zip(todayRecord.colors, todayRecord.colorHexes).map { name, hex in
                if let hex = hex {
                    return ColorInfo(name: name, hex: hex)
                } else {
                    return ColorInfo(name: name)
                }
            }
            todayOutfitColor = TodayOutfitColor(
                colors: colorInfos,
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

    // MARK: - 获取指定日期的本地打卡记录
    func getRecord(for date: Date) -> CheckInRecord? {
        let records = loadAllRecords()
        return records.first { record in
            Calendar.current.isDate(record.date, inSameDayAs: date)
        }
    }

    // MARK: - 公共方法：从 CloudKit 获取今日穿搭色（用于未打卡时预览）
    func fetchTodayOutfitColorFromCloudKit() async {
        // 1. 首先尝试从 CloudKit 获取
        if let cloudKitColor = await fetchFromCloudKit() {
            todayOutfitColor = cloudKitColor
            print("✅ [DailyCheckInManager] 从 CloudKit 获取到今日穿搭色")
            return
        }

        // 2. 如果 CloudKit 没有，调用 AI 生成（或本地算法）
        print("☁️ [DailyCheckInManager] CloudKit 无今日穿搭色，准备生成...")

        // 确保 AI 配置已加载
        PetAIService.shared.ensureConfiguration(
            role: .kitten,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: ""
        )

        let season = LocationService.shared.getCurrentSeason()
        let weather = currentWeather
        let location = currentLocation

        // 调用 AI 生成穿搭色
        if let aiResponse = await PetAIService.shared.generateTodayOutfitColors(
            season: season,
            weather: weather,
            location: location
        ) {
            // 将 AI 生成的颜色转换为 ColorInfo 数组
            let colorInfos = aiResponse.colors.map { ColorInfo(name: $0.name, hex: $0.hex) }
            let aiOutfit = TodayOutfitColor(
                colors: colorInfos,
                accessories: aiResponse.accessories,
                description: aiResponse.description,
                source: "ai",
                weather: weather?.condition.rawValue,
                location: location.isEmpty ? nil : location,
                temperature: weather?.temperature,
                season: season.displayName,
                petName: PetDataManager.shared.status.displayName
            )

            // 上传到 CloudKit 公共数据库
            await uploadToCloudKit(
                colors: aiResponse.colors,
                accessories: aiResponse.accessories,
                description: aiResponse.description
            )

            todayOutfitColor = aiOutfit
            print("✅ [DailyCheckInManager] AI 生成并上传今日穿搭色")
        } else {
            // AI 生成失败，使用本地算法
            print("⚠️ [DailyCheckInManager] AI 生成失败，使用本地算法")
            let localOutfit = await generateLocally()
            todayOutfitColor = localOutfit
        }
    }

    // MARK: - 获取今日穿搭色（内部方法，用于打卡时）
    private func fetchTodayOutfitColor() async -> TodayOutfitColor {
        // 1. 首先尝试从CloudKit获取
        if let cloudKitColor = await fetchFromCloudKit() {
            return cloudKitColor
        }
        
        // 2. 如果CloudKit没有，调用AI生成
        print("☁️ [DailyCheckInManager] CloudKit无今日穿搭色，准备调用AI生成...")

        // 确保 AI 配置已加载
        PetAIService.shared.ensureConfiguration(
            role: .kitten,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: ""
        )

        // 获取当前季节、天气和位置
        let season = LocationService.shared.getCurrentSeason()
        let weather = currentWeather
        let location = currentLocation

        // 调用AI生成穿搭色
        if let aiResponse = await PetAIService.shared.generateTodayOutfitColors(
            season: season,
            weather: weather,
            location: location
        ) {
            // 将AI生成的颜色转换为 ColorInfo 数组（包含名称和 hex）
            let colorInfos = aiResponse.colors.map { ColorInfo(name: $0.name, hex: $0.hex) }
            let aiOutfit = TodayOutfitColor(
                colors: colorInfos,
                accessories: aiResponse.accessories,
                description: aiResponse.description,
                source: "ai",
                weather: weather?.condition.rawValue,
                location: location.isEmpty ? nil : location,
                temperature: weather?.temperature,
                season: season.displayName,
                petName: PetDataManager.shared.status.displayName
            )

            // 上传到CloudKit公共数据库，供其他设备使用
            await uploadToCloudKit(
                colors: aiResponse.colors,
                accessories: aiResponse.accessories,
                description: aiResponse.description
            )

            return aiOutfit
        }
        
        // 3. 如果AI生成失败，回退到本地智能算法生成
        print("⚠️ [DailyCheckInManager] AI生成失败，使用本地算法生成")
        return await generateLocally()
    }
    
    // MARK: - 获取指定日期的穿搭色（用于测试补卡）
    func fetchOutfitColor(for date: Date) async -> TodayOutfitColor? {
        let targetDate = Calendar.current.startOfDay(for: date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: targetDate)

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

            // 尝试获取颜色详情（包含 hex 值）
            var colorInfos: [ColorInfo] = []
            if let colorDetailsString = record["colorDetails"] as? String,
               let colorDetailsData = colorDetailsString.data(using: .utf8),
               let colorDetails = try? JSONSerialization.jsonObject(with: colorDetailsData, options: []) as? [[String: String]] {
                // 有详细的 hex 信息（JSON 字符串格式）
                colorInfos = colorDetails.map { detail in
                    if let hex = detail["hex"] {
                        return ColorInfo(name: detail["name"] ?? "", hex: hex)
                    } else {
                        return ColorInfo(name: detail["name"] ?? "")
                    }
                }
            } else {
                // 只有颜色名称
                colorInfos = colors.map { name in
                    ColorInfo(name: name)
                }
            }

            return TodayOutfitColor(
                colors: colorInfos,
                accessories: accessories,
                description: record["description"] as? String ?? "",
                source: "cloudkit",
                weather: record["weather"] as? String,
                location: record["province"] as? String,
                temperature: record["temperature"] as? Double,
                season: nil,
                petName: nil
            )
        } catch {
            print("☁️ [DailyCheckInManager] CloudKit无 \(dateString) 的穿搭色记录")
            return nil
        }
    }

    // MARK: - 为指定日期生成并上传穿搭色（AI生成，失败时使用本地算法）
    func generateAndUploadOutfitForDate(_ date: Date) async -> TodayOutfitColor? {
        let targetDate = Calendar.current.startOfDay(for: date)

        // 1. 先尝试从 CloudKit 获取
        if let existingOutfit = await fetchOutfitColor(for: targetDate) {
            print("✅ [DailyCheckInManager] 从CloudKit获取到 \(targetDate) 的穿搭色")
            return existingOutfit
        }

        // 2. CloudKit 没有，调用 AI 生成
        print("☁️ [DailyCheckInManager] CloudKit无 \(targetDate) 的穿搭色，准备调用AI生成...")

        // 确保 AI 配置已加载
        PetAIService.shared.ensureConfiguration(
            role: .kitten,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: ""
        )

        // 获取当前季节（根据日期计算）
        let season = getSeason(for: targetDate)

        // 调用AI生成穿搭色
        if let aiResponse = await PetAIService.shared.generateTodayOutfitColors(
            season: season,
            weather: nil,
            location: ""
        ) {
            // 将AI生成的颜色转换为 ColorInfo 数组
            let colorInfos = aiResponse.colors.map { ColorInfo(name: $0.name, hex: $0.hex) }
            let aiOutfit = TodayOutfitColor(
                colors: colorInfos,
                accessories: aiResponse.accessories,
                description: aiResponse.description,
                source: "ai",
                weather: nil,
                location: nil,
                temperature: nil,
                season: season.displayName,
                petName: PetDataManager.shared.status.displayName
            )

            // 上传到 CloudKit 公共数据库
            await uploadOutfitToCloudKit(
                for: targetDate,
                colors: aiResponse.colors,
                accessories: aiResponse.accessories,
                description: aiResponse.description
            )

            return aiOutfit
        }

        // 3. AI 生成失败，使用本地算法生成
        print("⚠️ [DailyCheckInManager] AI生成失败，使用本地算法生成穿搭色")
        return generateLocallyForDate(targetDate, season: season)
    }

    // MARK: - 为指定日期本地生成穿搭色
    private func generateLocallyForDate(_ date: Date, season: Season) -> TodayOutfitColor {
        let petName = PetDataManager.shared.status.displayName

        // 根据季节选择颜色
        let seasonColors = season.recommendedColors
        var selectedColors: [String] = []
        selectedColors.append(seasonColors.randomElement()!)
        selectedColors.append(trendyColors2025.randomElement()!)
        selectedColors.append(seasonColors.randomElement()!)

        // 去重
        selectedColors = Array(Set(selectedColors)).prefix(3).map { $0 }

        // 生成搭配建议
        let accessories = generateAccessoriesAdvice(season: season, weather: nil)

        // 生成描述
        let description = generateDescription(season: season, weather: nil, colors: selectedColors)

        // 本地生成的颜色只有名称，没有 hex 值
        let colorInfos = selectedColors.map { ColorInfo(name: $0) }

        return TodayOutfitColor(
            colors: colorInfos,
            accessories: accessories,
            description: description,
            source: "pet",
            weather: nil,
            location: nil,
            temperature: nil,
            season: season.displayName,
            petName: petName
        )
    }

    // MARK: - 根据日期获取季节
    private func getSeason(for date: Date) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5:
            return .spring
        case 6...8:
            return .summer
        case 9...11:
            return .autumn
        default:
            return .winter
        }
    }

    // MARK: - 上传指定日期的穿搭色到 CloudKit
    private func uploadOutfitToCloudKit(for date: Date, colors: [OutfitColorDetail], accessories: String, description: String) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        // 获取当前省份
        let province = LocationService.shared.currentProvince

        let recordID = CKRecord.ID(recordName: "outfit_\(province)_\(dateString)")
        let record = CKRecord(recordType: "DailyOutfitColor", recordID: recordID)

        // 设置记录字段
        record["colors"] = colors.map { $0.name } as CKRecordValue
        
        // 将 colorDetails 转换为 JSON 字符串存储（CloudKit 不支持直接存储字典数组）
        let colorDetailsArray = colors.map { ["name": $0.name, "hex": $0.hex] }
        if let colorDetailsData = try? JSONSerialization.data(withJSONObject: colorDetailsArray, options: []),
           let colorDetailsString = String(data: colorDetailsData, encoding: .utf8) {
            record["colorDetails"] = colorDetailsString as CKRecordValue
        }
        
        record["accessories"] = accessories as CKRecordValue
        record["description"] = description as CKRecordValue
        record["date"] = date as CKRecordValue
        record["province"] = province as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        let database = container.publicCloudDatabase

        do {
            let savedRecord = try await database.save(record)
            print("✅ [DailyCheckInManager] 穿搭色已成功上传到CloudKit: \(savedRecord.recordID.recordName)")
        } catch {
            print("❌ [DailyCheckInManager] 上传到CloudKit失败: \(error)")
        }
    }

    // MARK: - 从CloudKit获取今日穿搭色
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
            
            // 尝试获取颜色详情（包含 hex 值）
            var colorInfos: [ColorInfo] = []
            if let colorDetailsString = record["colorDetails"] as? String,
               let colorDetailsData = colorDetailsString.data(using: .utf8),
               let colorDetails = try? JSONSerialization.jsonObject(with: colorDetailsData, options: []) as? [[String: String]] {
                // 有详细的 hex 信息（JSON 字符串格式）
                colorInfos = colorDetails.map { detail in
                    if let hex = detail["hex"] {
                        return ColorInfo(name: detail["name"] ?? "", hex: hex)
                    } else {
                        return ColorInfo(name: detail["name"] ?? "")
                    }
                }
            } else {
                // 只有颜色名称，从 AppColorMap 查找 hex
                colorInfos = colors.map { name in
                    // 尝试从映射表中找到对应的 hex（如果有的话）
                    ColorInfo(name: name)
                }
            }
            
            return TodayOutfitColor(
                colors: colorInfos,
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
    
    // MARK: - 上传穿搭色到CloudKit公共数据库
    private func uploadToCloudKit(colors: [OutfitColorDetail], accessories: String, description: String) async {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        // 获取当前省份
        let province = LocationService.shared.currentProvince
        
        let recordID = CKRecord.ID(recordName: "outfit_\(province)_\(dateString)")
        let record = CKRecord(recordType: "DailyOutfitColor", recordID: recordID)
        
        // 设置记录字段
        record["colors"] = colors.map { $0.name } as CKRecordValue
        
        // 将 colorDetails 转换为 JSON 字符串存储（CloudKit 不支持直接存储字典数组）
        let colorDetailsArray = colors.map { ["name": $0.name, "hex": $0.hex] }
        if let colorDetailsData = try? JSONSerialization.data(withJSONObject: colorDetailsArray, options: []),
           let colorDetailsString = String(data: colorDetailsData, encoding: .utf8) {
            record["colorDetails"] = colorDetailsString as CKRecordValue
        }
        
        record["accessories"] = accessories as CKRecordValue
        record["description"] = description as CKRecordValue
        record["date"] = today as CKRecordValue
        record["province"] = province as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        
        // 如果有天气信息，也一并保存
        if let weather = currentWeather {
            record["weather"] = weather.condition.rawValue as CKRecordValue
            record["temperature"] = weather.temperature as CKRecordValue
        }
        
        let database = container.publicCloudDatabase
        
        do {
            let savedRecord = try await database.save(record)
            print("✅ [DailyCheckInManager] 穿搭色已成功上传到CloudKit: \(savedRecord.recordID.recordName)")
        } catch {
            print("❌ [DailyCheckInManager] 上传到CloudKit失败: \(error)")
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
        
        // 本地生成的颜色只有名称，没有 hex 值
        let colorInfos = selectedColors.map { ColorInfo(name: $0) }
        
        return TodayOutfitColor(
            colors: colorInfos,
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

// MARK: - AI穿搭色响应结构
struct OutfitColorAIResponse: Codable {
    let colors: [OutfitColorDetail]
    let accessories: String
    let description: String
}

// MARK: - 颜色详情（包含名称和十六进制值）
struct OutfitColorDetail: Codable {
    let name: String
    let hex: String
}

// MARK: - PetAIService扩展 - 生成穿搭色
extension PetAIService {
    /// 调用AI生成今日穿搭色，返回颜色名称、十六进制值和搭配建议
    /// 如果API Key为空或AI调用失败，返回nil，调用方应使用本地生成作为回退
    func generateTodayOutfitColors(season: Season, weather: WeatherData?, location: String) async -> OutfitColorAIResponse? {
        // 检查API Key是否可用
        guard PetAIService.shared.isAPIKeyAvailable else {
            print("⚠️ [DailyCheckInManager] API Key为空，跳过AI生成，使用本地算法")
            return nil
        }

        // 构建提示词
        let weatherInfo = weather != nil ? "天气：\(weather!.condition.rawValue)，温度：\(Int(weather!.temperature))°C" : "天气未知"
        let locationInfo = location.isEmpty ? "位置未知" : "位置：\(location)"

        let prompt = """
        请为Lolita风格穿搭推荐今日穿搭色。

        当前信息：
        - 季节：\(season.displayName)
        - \(weatherInfo)
        - \(locationInfo)

        请严格按照以下JSON格式返回（不要包含任何其他文字）：
        {
          "colors": [
            {"name": "颜色名称1", "hex": "#RRGGBB"},
            {"name": "颜色名称2", "hex": "#RRGGBB"},
            {"name": "颜色名称3", "hex": "#RRGGBB"}
          ],
          "accessories": "小物搭配建议（50字以内）",
          "description": "整体风格描述（20字以内）"
        }

        要求：
        1. 颜色名称使用中文，要优雅有诗意，符合Lolita风格
        2. 十六进制格式必须是 #RRGGBB
        3. 推荐3个颜色，要协调搭配
        4. 考虑季节、天气因素
        5. 只返回JSON，不要其他文字
        """

        // 发送请求给AI（禁用语音播报）
        let response = await sendMessage(prompt, enableVoice: false)

        // 检查响应是否包含错误信息
        if response.text.contains("配置错误") || response.text.contains("API Key") {
            print("⚠️ [DailyCheckInManager] AI服务配置错误，使用本地算法")
            return nil
        }

        // 解析JSON响应
        guard let jsonData = response.text.data(using: .utf8) else {
            print("❌ [DailyCheckInManager] AI响应无法转换为数据")
            return nil
        }

        do {
            let aiResponse = try JSONDecoder().decode(OutfitColorAIResponse.self, from: jsonData)
            print("✅ [DailyCheckInManager] AI生成穿搭色成功: \(aiResponse.colors.map { $0.name })")
            return aiResponse
        } catch {
            print("❌ [DailyCheckInManager] AI响应JSON解析失败: \(error)")
            print("响应内容: \(response.text)")
            return nil
        }
    }
}
