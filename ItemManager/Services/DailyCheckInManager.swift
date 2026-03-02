import Foundation
import SwiftUI
import Combine
import CloudKit

// MARK: - 打卡记录
struct CheckInRecord: Codable, Identifiable {
    let id: String
    let date: Date
    let colors: [String] // 今日穿搭色
    let accessories: String // 小物搭配建议
    let weather: String? // 天气信息
    let location: String? // 位置信息
    let isAIGenerated: Bool // 是否AI生成
}

// MARK: - 今日穿搭色数据
struct TodayOutfitColor: Codable {
    let colors: [String] // 颜色数组，如 ["樱花粉", "奶油白"]
    let accessories: String // 小物搭配建议
    let description: String // 描述
    let source: String // 来源：cloudkit/ai
}

// MARK: - 每日打卡管理器
final class DailyCheckInManager: ObservableObject {
    static let shared = DailyCheckInManager()
    
    @Published var todayCheckIn: CheckInRecord?
    @Published var consecutiveDays: Int = 0
    @Published var totalDays: Int = 0
    @Published var weekCheckIns: [Bool] = [false, false, false, false, false, false, false] // 本周打卡状态
    @Published var todayOutfitColor: TodayOutfitColor?
    @Published var isLoading = false
    
    private let checkInKey = "dailyCheckIn.records"
    private let lastCheckInDateKey = "dailyCheckIn.lastDate"
    private let consecutiveDaysKey = "dailyCheckIn.consecutiveDays"
    private let totalDaysKey = "dailyCheckIn.totalDays"
    
    private let container = CKContainer(identifier: "iCloud.bugod2.SkirtMarket")
    
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
        // 这里简化处理，实际应该查询历史记录
        // 如果日期是今天且已打卡
        if Calendar.current.isDateInToday(date) {
            return hasCheckedInToday
        }
        // 其他日期需要查询历史记录
        return false
    }
    
    // MARK: - 执行打卡
    func performCheckIn() async -> CheckInRecord? {
        guard !hasCheckedInToday else {
            return nil
        }
        
        await MainActor.run { isLoading = true }
        
        // 1. 获取今日穿搭色
        let outfitColor = await fetchTodayOutfitColor()
        
        // 2. 创建打卡记录
        let record = CheckInRecord(
            id: UUID().uuidString,
            date: Date(),
            colors: outfitColor.colors,
            accessories: outfitColor.accessories,
            weather: nil, // 可以接入天气API
            location: nil, // 可以获取位置
            isAIGenerated: outfitColor.source == "ai"
        )
        
        // 3. 更新数据
        await MainActor.run {
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
        }
        
        // 4. 保存记录
        saveCheckInRecord(record)
        
        return record
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
            await MainActor.run {
                todayOutfitColor = TodayOutfitColor(
                    colors: todayRecord.colors,
                    accessories: todayRecord.accessories,
                    description: "",
                    source: todayRecord.isAIGenerated ? "ai" : "cloudkit"
                )
            }
        } else {
            // 如果没有本地记录，尝试获取
            let outfit = await fetchTodayOutfitColor()
            await MainActor.run {
                todayOutfitColor = outfit
            }
        }
    }
    
    // MARK: - 获取今日穿搭色
    private func fetchTodayOutfitColor() async -> TodayOutfitColor {
        // 1. 首先尝试从CloudKit获取
        if let cloudKitColor = await fetchFromCloudKit() {
            return cloudKitColor
        }
        
        // 2. 如果CloudKit没有，使用AI生成
        return await generateFromAI()
    }
    
    // MARK: - 从CloudKit获取
    private func fetchFromCloudKit() async -> TodayOutfitColor? {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        // 获取当前省份（简化处理，实际应该根据用户位置）
        let province = await getCurrentProvince()
        
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
                source: "cloudkit"
            )
        } catch {
            print("CloudKit获取失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 获取当前省份
    private func getCurrentProvince() async -> String {
        // 简化处理，返回默认省份
        // 实际应该根据用户位置或设置获取
        return "default"
    }
    
    // MARK: - AI生成穿搭色
    private func generateFromAI() async -> TodayOutfitColor {
        // 获取当前日期信息
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let day = calendar.component(.day, from: Date())
        
        // 获取节气/节日信息（简化版）
        let festival = getFestivalOrSolarTerm(month: month, day: day)
        
        // 构建AI提示词
        let prompt = """
        作为Lolita时尚搭配专家，请根据以下信息推荐今日穿搭配色：
        
        日期：\(month)月\(day)日
        \(festival.isEmpty ? "" : "特殊日期：\(festival)")
        
        请推荐：
        1. 1-3种Lolita风格的主色调（使用中文颜色名称，如：樱花粉、奶油白、薰衣草紫）
        2. 适合的小物搭配建议（如：发饰、包包、鞋子等）
        3. 简短的风格描述
        
        请以JSON格式返回：
        {
            "colors": ["颜色1", "颜色2"],
            "accessories": "小物搭配建议",
            "description": "风格描述"
        }
        """
        
        // 调用AI服务（使用项目中已有的AI规范）
        do {
            let response = try await PetAIService.shared.generateOutfitColors(prompt: prompt)
            return TodayOutfitColor(
                colors: response.colors,
                accessories: response.accessories,
                description: response.description,
                source: "ai"
            )
        } catch {
            print("AI生成失败: \(error)")
            // 返回默认推荐
            return getDefaultOutfitColor()
        }
    }
    
    // MARK: - 获取节日/节气
    private func getFestivalOrSolarTerm(month: Int, day: Int) -> String {
        // 简化版节日/节气判断
        let festivals: [String: String] = [
            "2-14": "情人节",
            "3-8": "妇女节",
            "5-1": "劳动节",
            "6-1": "儿童节",
            "10-1": "国庆节",
            "12-25": "圣诞节"
        ]
        
        let key = "\(month)-\(day)"
        return festivals[key] ?? ""
    }
    
    // MARK: - 默认穿搭色
    private func getDefaultOutfitColor() -> TodayOutfitColor {
        let defaultColors = [
            ["樱花粉", "奶油白"],
            ["薰衣草紫", "珍珠白"],
            ["薄荷绿", "浅灰蓝"],
            ["玫瑰红", "香槟金"]
        ]
        
        let randomColors = defaultColors.randomElement()!
        
        return TodayOutfitColor(
            colors: randomColors,
            accessories: "搭配同色系发饰和蕾丝手套，选择珍珠项链增添优雅气质",
            description: "经典优雅的Lolita配色",
            source: "default"
        )
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
