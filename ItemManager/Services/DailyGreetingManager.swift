import Foundation
import CloudKit
import Combine

// MARK: - 每日问候语管理器
@MainActor
final class DailyGreetingManager: ObservableObject {
    static let shared = DailyGreetingManager()
    
    // 当前时间段的问候语
    @Published var currentGreeting: DailyGreeting?
    @Published var isLoading = false
    
    // 缓存的问候语（按日期+时间段缓存）
    private var greetingCache: [String: DailyGreeting] = [:]
    
    // CloudKit 容器
    private let container = CKContainer(identifier: "iCloud.bugod2.SkirtMarket")
    
    // UserDefaults 键
    private let greetingCacheKey = "dailyGreeting.cache"
    private let lastGreetingDateKey = "dailyGreeting.lastDate"
    private let lastTimeOfDayKey = "dailyGreeting.lastTimeOfDay"
    
    private init() {
        // 加载缓存
        loadCachedGreeting()
        
        // 检查是否需要更新问候语（时间段变化或日期变化）
        checkAndUpdateGreeting()
    }
    
    // MARK: - 获取当前问候语（主入口）
    func getCurrentGreeting() async -> DailyGreeting? {
        // 如果当前问候语有效且时间段未变化，直接返回
        if let greeting = currentGreeting,
           isGreetingValid(greeting) {
            return greeting
        }
        
        // 需要获取新的问候语
        await fetchOrGenerateGreeting()
        return currentGreeting
    }
    
    // MARK: - 检查并更新问候语
    private func checkAndUpdateGreeting() {
        Task {
            await fetchOrGenerateGreeting()
        }
    }
    
    // MARK: - 判断问候语是否有效（同日期同时间段）
    private func isGreetingValid(_ greeting: DailyGreeting) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // 检查是否是同一天
        guard calendar.isDate(greeting.date, inSameDayAs: now) else {
            return false
        }
        
        // 检查是否是同一时间段
        let currentTimeOfDay = TimeOfDay.current
        return greeting.timeOfDay == currentTimeOfDay
    }
    
    // MARK: - 获取或生成问候语
    private func fetchOrGenerateGreeting() async {
        let now = Date()
        let timeOfDay = TimeOfDay.current
        let cacheKey = generateCacheKey(date: now, timeOfDay: timeOfDay)
        
        isLoading = true
        defer { isLoading = false }
        
        // 1. 先检查内存缓存
        if let cached = greetingCache[cacheKey] {
            currentGreeting = cached
            print("✅ [DailyGreetingManager] 从内存缓存获取问候语")
            return
        }
        
        // 2. 从 CloudKit 公共数据库获取
        if let cloudGreeting = await fetchFromCloudKit(date: now, timeOfDay: timeOfDay) {
            currentGreeting = cloudGreeting
            greetingCache[cacheKey] = cloudGreeting
            saveGreetingToCache(cloudGreeting)
            print("✅ [DailyGreetingManager] 从 CloudKit 获取问候语")
            return
        }
        
        // 3. CloudKit 没有，调用 AI 生成
        print("☁️ [DailyGreetingManager] CloudKit 无问候语，准备调用 AI 生成...")
        
        // 确保 AI 配置已加载
        PetAIService.shared.ensureConfiguration(
            role: .kitten,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: ""
        )
        
        if let aiResponse = await PetAIService.shared.generateDailyGreeting(timeOfDay: timeOfDay) {
            let aiGreeting = DailyGreeting(
                id: UUID().uuidString,
                date: now,
                timeOfDay: timeOfDay,
                messages: aiResponse.formattedMessages,
                source: "ai",
                createdAt: Date()
            )
            
            // 上传到 CloudKit 供其他设备使用
            await uploadToCloudKit(greeting: aiGreeting)
            
            currentGreeting = aiGreeting
            greetingCache[cacheKey] = aiGreeting
            saveGreetingToCache(aiGreeting)
            print("✅ [DailyGreetingManager] AI 生成并上传问候语")
            return
        }
        
        // 4. AI 生成失败，使用本地模板（根据日期选择，确保每天不同）
        print("⚠️ [DailyGreetingManager] AI 生成失败，使用本地模板")
        let localMessages = GreetingTemplates.template(for: now, timeOfDay: timeOfDay)
        let localGreeting = DailyGreeting(
            id: UUID().uuidString,
            date: now,
            timeOfDay: timeOfDay,
            messages: localMessages,
            source: "local",
            createdAt: Date()
        )
        
        currentGreeting = localGreeting
        greetingCache[cacheKey] = localGreeting
        saveGreetingToCache(localGreeting)
    }
    
    // MARK: - 从 CloudKit 获取问候语（按周存储，每天显示不同）
    private func fetchFromCloudKit(date: Date, timeOfDay: TimeOfDay) async -> DailyGreeting? {
        let calendar = Calendar.current
        
        // 获取当前周的起始日期（周一）作为周标识
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.year, from: date)
        let weekString = "\(year)-W\(weekOfYear)"
        
        // 构建记录 ID：greeting_周_时间段（一周只生成一次，包含7条）
        let recordID = CKRecord.ID(recordName: "greeting_\(weekString)_\(timeOfDay.rawValue)")
        let database = container.publicCloudDatabase
        
        do {
            let record = try await database.record(for: recordID)
            
            guard let messages = record["messages"] as? [String],
                  let source = record["source"] as? String,
                  let createdAt = record["createdAt"] as? Date else {
                return nil
            }
            
            // 根据星期几选择当天的问候语（0=周日, 1=周一...）
            let weekday = calendar.component(.weekday, from: date)
            let dayIndex = (weekday + 5) % 7  // 转换为 0=周一, 6=周日
            let todayMessage = messages.indices.contains(dayIndex) ? [messages[dayIndex]] : [messages.first!]
            
            return DailyGreeting(
                id: recordID.recordName,
                date: date,
                timeOfDay: timeOfDay,
                messages: todayMessage,
                source: source,
                createdAt: createdAt
            )
        } catch {
            print("☁️ [DailyGreetingManager] CloudKit 无问候语记录: \(recordID.recordName)")
            return nil
        }
    }
    
    // MARK: - 上传问候语到 CloudKit（按周存储7条）
    private func uploadToCloudKit(greeting: DailyGreeting) async {
        let calendar = Calendar.current
        
        // 获取当前周的起始日期（周一）作为周标识
        let weekOfYear = calendar.component(.weekOfYear, from: greeting.date)
        let year = calendar.component(.year, from: greeting.date)
        let weekString = "\(year)-W\(weekOfYear)"
        
        let recordID = CKRecord.ID(recordName: "greeting_\(weekString)_\(greeting.timeOfDay.rawValue)")
        let record = CKRecord(recordType: "DailyGreeting", recordID: recordID)
        
        // 设置记录字段（存储一周的7条问候语）
        record["messages"] = greeting.messages as CKRecordValue
        record["source"] = greeting.source as CKRecordValue
        record["date"] = greeting.date as CKRecordValue
        record["timeOfDay"] = greeting.timeOfDay.rawValue as CKRecordValue
        record["createdAt"] = greeting.createdAt as CKRecordValue
        
        let database = container.publicCloudDatabase
        
        do {
            let savedRecord = try await database.save(record)
            print("✅ [DailyGreetingManager] 问候语已上传到 CloudKit: \(savedRecord.recordID.recordName)")
        } catch {
            print("❌ [DailyGreetingManager] 上传到 CloudKit 失败: \(error)")
        }
    }
    
    // MARK: - 生成缓存键
    private func generateCacheKey(date: Date, timeOfDay: TimeOfDay) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        return "\(dateString)_\(timeOfDay.rawValue)"
    }
    
    // MARK: - 保存问候语到本地缓存
    private func saveGreetingToCache(_ greeting: DailyGreeting) {
        let cacheKey = generateCacheKey(date: greeting.date, timeOfDay: greeting.timeOfDay)
        
        if let data = try? JSONEncoder().encode(greeting) {
            UserDefaults.standard.set(data, forKey: "\(greetingCacheKey).\(cacheKey)")
        }
        
        // 保存最后获取的日期和时间段
        UserDefaults.standard.set(greeting.date, forKey: lastGreetingDateKey)
        UserDefaults.standard.set(greeting.timeOfDay.rawValue, forKey: lastTimeOfDayKey)
    }
    
    // MARK: - 加载缓存的问候语
    private func loadCachedGreeting() {
        let now = Date()
        let timeOfDay = TimeOfDay.current
        let cacheKey = generateCacheKey(date: now, timeOfDay: timeOfDay)
        
        guard let data = UserDefaults.standard.data(forKey: "\(greetingCacheKey).\(cacheKey)"),
              let greeting = try? JSONDecoder().decode(DailyGreeting.self, from: data) else {
            return
        }
        
        // 检查缓存是否有效
        if isGreetingValid(greeting) {
            currentGreeting = greeting
            greetingCache[cacheKey] = greeting
            print("✅ [DailyGreetingManager] 从本地缓存加载问候语")
        }
    }
    
    // MARK: - 强制刷新问候语（用于调试或用户手动刷新）
    func refreshGreeting() async {
        // 清除当前缓存
        let now = Date()
        let timeOfDay = TimeOfDay.current
        let cacheKey = generateCacheKey(date: now, timeOfDay: timeOfDay)
        greetingCache.removeValue(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "\(greetingCacheKey).\(cacheKey)")
        
        // 重新获取
        await fetchOrGenerateGreeting()
    }
    
    // MARK: - 获取问候语标题（用于UI显示）
    /// 直接返回第一条诗意问候语，去掉•符号
    func getGreetingTitle() -> String {
        guard let greeting = currentGreeting else {
            // 默认根据时间段返回诗意问候
            return getDefaultPoeticGreeting()
        }
        
        // 直接返回第一条问候语的完整内容（去掉•符号）
        let primary = greeting.primaryMessage
        
        return primary.isEmpty ? getDefaultPoeticGreeting() : primary
    }
    
    /// 获取默认诗意问候语（无数据时使用）
    private func getDefaultPoeticGreeting() -> String {
        switch TimeOfDay.current {
        case .dawn:
            return "星光还在值班，月亮说该你接班了"
        case .morning:
            return "晨光为你铺好了路，今天也要闪闪发光"
        case .noon:
            return "正午的阳光最烈，但你的笑容更耀眼"
        case .afternoon:
            return "下午的时光，适合发呆，适合想你"
        case .evening:
            return "今夜星光为你守护"
        case .night:
            return "我把思念装进梦里了，等你去打开"
        }
    }
}

// MARK: - PetAIService 扩展 - 生成每日问候语
extension PetAIService {
    /// 调用 AI 生成每日问候语
    /// 如果 API Key 为空或 AI 调用失败，返回 nil，调用方应使用本地模板作为回退
    func generateDailyGreeting(timeOfDay: TimeOfDay) async -> GreetingAIResponse? {
        // 检查 API Key 是否可用
        guard PetAIService.shared.isAPIKeyAvailable else {
            print("⚠️ [DailyGreetingManager] API Key 为空，跳过 AI 生成，使用本地模板")
            return nil
        }
        
        // 构建提示词 - 生成7条，一周每天不同
        let prompt = """
        请为少女心愿衣橱 APP 生成7条文艺、优雅、有哲理的问候语，对应一周的7天，每天一句都不同。
        
        当前时间段：\(timeOfDay.displayName)（\(timeOfDay.greetingPrefix)）
        
        要求：
        1. 每条内容都要文艺、优雅、有哲理，像一句优美的诗句
        2. 每条字数控制在10-30字之间，精炼有韵味
        3. 不要出现"早安/午安/晚安/你好"等问候前缀
        4. 可以涉及时光、岁月、星辰、梦境、花开、风起等意象
        5. 要有一定的哲理或意境，让人读后有所感触
        6. 不要出现"少女"称呼，让文字本身传达情感
        7. 7条内容风格要各有特色，不要重复相似
        8. 风格参考："岁月漫长，值得等待"、"心有山海，静而无边"
        
        请严格按照以下 JSON 格式返回（不要包含任何其他文字）：
        {
          "messages": [
            "• 周一的问候语",
            "• 周二的问候语",
            "• 周三的问候语",
            "• 周四的问候语",
            "• 周五的问候语",
            "• 周六的问候语",
            "• 周日的问候语"
          ]
        }
        """
        
        // 发送请求给 AI（禁用语音播报）
        let response = await sendMessage(prompt, enableVoice: false)
        
        // 检查响应是否包含错误信息
        if response.text.contains("配置错误") || response.text.contains("API Key") {
            print("⚠️ [DailyGreetingManager] AI 服务配置错误，使用本地模板")
            return nil
        }
        
        // 解析 JSON 响应
        guard let jsonData = response.text.data(using: .utf8) else {
            print("❌ [DailyGreetingManager] AI 响应无法转换为数据")
            return nil
        }
        
        do {
            let aiResponse = try JSONDecoder().decode(GreetingAIResponse.self, from: jsonData)
            print("✅ [DailyGreetingManager] AI 生成问候语成功")
            return aiResponse
        } catch {
            print("❌ [DailyGreetingManager] AI 响应 JSON 解析失败: \(error)")
            print("响应内容: \(response.text)")
            return nil
        }
    }
}
