import SwiftUI
import UIKit

// MARK: - 每日打卡视图
struct DailyCheckInView: View {
    @StateObject private var checkInManager = DailyCheckInManager.shared
    @StateObject private var greetingManager = DailyGreetingManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var showCelebration = false
    @State private var isSharing = false // 分享加载状态
    
    // 选中的日期（用于查看往日穿搭色）
    @State private var selectedDate: Date = Date()
    @State private var selectedDateOutfit: TodayOutfitColor?
    @State private var isLoadingSelectedDate = false
    
    // 本周签到展开状态
    @State private var isWeekCheckInExpanded = false
    
    // 星期名称
    private let weekDays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                checkInBackground
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 顶部标题区域
                        headerSection
                            .padding(.top, 20)
                        
                        // 七日签到卡片
                        weekCheckInCard
                        
                        // 穿搭色区域（今日或选中的往日）
                        outfitColorSection
                        
                        // 打卡按钮
                        checkInButton
                            .padding(.horizontal, 40)
                            .padding(.top, 20)
                        
                        // 分享按钮（打卡后才显示）
                        if checkInManager.hasCheckedInToday {
                            shareButton
                                .padding(.horizontal, 40)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
                
                // 庆祝动画
                if showCelebration {
                    CheckInCelebrationView {
                        withAnimation {
                            showCelebration = false
                        }
                    }
                    .transition(.opacity)
                }
                
                // 猫爪加载遮罩（分享时显示）
                if isSharing {
                    ShareLoadingOverlay(message: "正在准备分享...")
                        .transition(.opacity)
                }
            }
            .navigationTitle("每日打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
        .task {
            // 加载问候语
            _ = await greetingManager.getCurrentGreeting()
            
            // 如果已打卡但穿搭色为空，加载今日穿搭色
            if checkInManager.hasCheckedInToday && checkInManager.todayOutfitColor == nil {
                await checkInManager.loadTodayOutfitColor()
            }
            // 未打卡时，穿搭色已在 App 启动时预加载，这里只处理预加载失败的情况
            else if !checkInManager.hasCheckedInToday && checkInManager.todayOutfitColor == nil {
                // 仅在预加载失败时重新尝试
                if checkInManager.preloadError != nil {
                    await checkInManager.fetchTodayOutfitColorFromCloudKit()
                }
            }

            // 请求位置权限
            LocationService.shared.requestAuthorization()
        }
    }
    
    // MARK: - 背景
    private var checkInBackground: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [
                    Color.pink.opacity(0.1),
                    Color.purple.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 装饰性圆形
            Circle()
                .fill(Color.pink.opacity(0.08))
                .frame(width: 300, height: 300)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(Color.purple.opacity(0.06))
                .frame(width: 200, height: 200)
                .offset(x: 150, y: 100)
        }
    }
    
    // MARK: - 顶部标题区域
    private var headerSection: some View {
        VStack(spacing: 12) {
            // 日期显示
            Text(todayDateString)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            // 问候语卡片（可展开查看完整3条）
            greetingCard
            
            // 连续打卡天数
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("连续打卡 \(checkInManager.consecutiveDays) 天")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 问候语卡片（显示一句文艺哲理问候）
    private var greetingCard: some View {
        VStack(spacing: 12) {
            // 问候语内容（仅一句）
            if greetingManager.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let greeting = greetingManager.currentGreeting,
                      let firstMessage = greeting.messages.first {
                Text(firstMessage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            } else {
                // 默认问候语
                Text("• 岁月漫长，然而值得等待。")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }
            
            // 来源标签
            if let source = greetingManager.currentGreeting?.source {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: source == "ai" ? "sparkles" : "pawprint.fill")
                            .font(.caption)
                        Text(source == "ai" ? "AI生成" : (source == "cloudkit" ? "云端同步" : "萌宠推荐"))
                            .font(.caption)
                    }
                    .foregroundColor(source == "ai" ? .purple : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(source == "ai" ? Color.purple.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.pink.opacity(0.3), .purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - 七日签到卡片（可点击查看往日穿搭色，可展开为日历）
    private var weekCheckInCard: some View {
        VStack(spacing: 16) {
            // 标题栏（带展开按钮）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isWeekCheckInExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("本周签到")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text("累计 \(checkInManager.totalDays) 天")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    // 展开/折叠图标
                    Image(systemName: isWeekCheckInExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }

            if isWeekCheckInExpanded {
                // 展开状态：显示自定义日历组件，支持打勾标记
                CustomCalendarView(
                    selectedDate: $selectedDate,
                    checkInManager: checkInManager,
                    onDateSelected: { date in
                        loadOutfitForSelectedDate()
                    }
                )
            } else {
                // 折叠状态：显示本周七日格子
                HStack(spacing: 8) {
                    ForEach(0..<7) { index in
                        let date = getDateForWeekday(index)
                        let isSelected = Calendar.current.isDate(selectedDate, inSameDayAs: date)
                        let isToday = isToday(weekday: index)
                        let isCheckedIn = checkInManager.weekCheckIns[index]

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDate = date
                                loadOutfitForSelectedDate()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(weekDays[index])
                                    .font(.system(size: 12))
                                    .foregroundColor(isToday ? .pink : .secondary)

                                ZStack {
                                    Circle()
                                        .fill(isCheckedIn ? Color.pink.opacity(0.2) : Color.clear)
                                        .frame(width: 36, height: 36)

                                    if isCheckedIn {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.pink)
                                    } else {
                                        Text("\(Calendar.current.component(.day, from: date))")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }

                                    // 选中边框
                                    if isSelected {
                                        Circle()
                                            .stroke(Color.pink, lineWidth: 2)
                                            .frame(width: 36, height: 36)
                                    }
                                }
                            }
                        }
                        .disabled(date > Date()) // 禁用未来日期
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [.pink.opacity(0.3), .purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 根据星期索引获取日期
    private func getDateForWeekday(_ index: Int) -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // 转换为周一=0, 周日=6
        let todayIndex = (weekday + 5) % 7
        let daysOffset = index - todayIndex
        return calendar.date(byAdding: .day, value: daysOffset, to: today) ?? today
    }
    
    // MARK: - 穿搭色区域（今日或选中的往日）
    private var outfitColorSection: some View {
        VStack(spacing: 20) {
            // 标题行
            HStack {
                let isToday = Calendar.current.isDateInToday(selectedDate)
                Text(isToday ? "今日穿搭色" : "\(formatDate(selectedDate))穿搭色")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                // 推荐者标签
                let outfit = isToday ? checkInManager.todayOutfitColor : selectedDateOutfit
                if let outfit = outfit {
                    HStack(spacing: 4) {
                        Image(systemName: outfit.source == "ai" ? "sparkles" : "pawprint.fill")
                            .font(.caption)
                        Text("\(outfit.petName ?? "萌宠")推荐")
                            .font(.caption)
                    }
                    .foregroundColor(outfit.source == "ai" ? .purple : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(outfit.source == "ai" ? Color.purple.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                }
            }

            // 加载状态
            if isLoadingSelectedDate {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("加载中...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if let outfit = Calendar.current.isDateInToday(selectedDate) ? checkInManager.todayOutfitColor : selectedDateOutfit {
                // 天气位置信息
                HStack(spacing: 12) {
                    // 位置
                    if let location = outfit.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption)
                            Text(location)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 天气
                    if let weather = outfit.weather {
                        HStack(spacing: 4) {
                            Image(systemName: weatherIcon(for: weather))
                                .font(.caption)
                            Text(weather)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 温度
                    if let temp = outfit.temperature {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer")
                                .font(.caption)
                            Text("\(Int(temp))°C")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 季节
                    if let season = outfit.season {
                        HStack(spacing: 4) {
                            Image(systemName: "leaf.fill")
                                .font(.caption)
                            Text(season)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                // 颜色展示
                HStack(spacing: 12) {
                    ForEach(outfit.colors, id: \.self) { colorInfo in
                        if let hex = colorInfo.hex {
                            ColorCard(colorName: colorInfo.name, hexColor: hex)
                        } else {
                            ColorCard(colorName: colorInfo.name)
                        }
                    }
                }

                // 小物搭配建议
                if !outfit.accessories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkle")
                                .foregroundColor(.pink)
                            Text("小物搭配")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text(outfit.accessories)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.pink.opacity(0.05))
                    )
                }
            } else if Calendar.current.isDateInToday(selectedDate) {
                // 今日加载中
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在为你推荐今日穿搭色...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else {
                // 往日无数据
                VStack(spacing: 16) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("该日期暂无穿搭色记录")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)

                    // AI 生成按钮
                    Button {
                        generateOutfitForSelectedDate()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("AI生成穿搭色")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.pink)
                        )
                    }
                }
                .padding(.vertical, 30)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }

    // MARK: - 格式化日期（MM月dd日）
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateFormat = "MM月dd日"
        return formatter.string(from: date)
    }

    // MARK: - 加载选中日期的穿搭色
    private func loadOutfitForSelectedDate() {
        Task {
            isLoadingSelectedDate = true
            selectedDateOutfit = nil

            let isToday = Calendar.current.isDateInToday(selectedDate)

            if isToday {
                // 今日穿搭色由 manager 管理
                selectedDateOutfit = nil
            } else {
                // 往日穿搭色：先查本地，再查 CloudKit
                if let localRecord = checkInManager.getRecord(for: selectedDate) {
                    // 本地有记录
                    let colorInfos = zip(localRecord.colors, localRecord.colorHexes).map { name, hex in
                        if let hex = hex {
                            return ColorInfo(name: name, hex: hex)
                        } else {
                            return ColorInfo(name: name)
                        }
                    }
                    selectedDateOutfit = TodayOutfitColor(
                        colors: colorInfos,
                        accessories: localRecord.accessories,
                        description: "",
                        source: localRecord.isAIGenerated ? "ai" : "local",
                        weather: localRecord.weather,
                        location: localRecord.location,
                        temperature: localRecord.temperature,
                        season: localRecord.season,
                        petName: localRecord.petName
                    )
                } else {
                    // 本地没有，查 CloudKit
                    if let cloudOutfit = await checkInManager.fetchOutfitColor(for: selectedDate) {
                        selectedDateOutfit = cloudOutfit
                    }
                }
            }

            isLoadingSelectedDate = false
        }
    }

    // MARK: - 为选中日期生成穿搭色
    private func generateOutfitForSelectedDate() {
        Task {
            isLoadingSelectedDate = true
            if let outfit = await checkInManager.generateAndUploadOutfitForDate(selectedDate) {
                selectedDateOutfit = outfit
            }
            isLoadingSelectedDate = false
        }
    }
    
    // MARK: - 天气图标映射
    private func weatherIcon(for weather: String) -> String {
        switch weather {
        case "晴": return "sun.max.fill"
        case "多云": return "cloud.sun.fill"
        case "阴": return "cloud.fill"
        case "小雨", "中雨": return "cloud.rain.fill"
        case "大雨": return "cloud.heavyrain.fill"
        case "雷雨": return "cloud.bolt.rain.fill"
        case "雪": return "snowflake"
        case "雾": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
    
    // MARK: - 打卡按钮
    private var checkInButton: some View {
        Button {
            performCheckIn()
        } label: {
            HStack(spacing: 8) {
                if checkInManager.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: checkInManager.hasCheckedInToday ? "checkmark.circle.fill" : "hand.tap.fill")
                    Text(checkInManager.hasCheckedInToday ? "今日已打卡" : "立即打卡")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: checkInManager.hasCheckedInToday 
                                ? [Color.green, Color.green.opacity(0.8)]
                                : [Color.pink, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: (checkInManager.hasCheckedInToday ? Color.green : Color.pink).opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .disabled(checkInManager.hasCheckedInToday || checkInManager.isLoading)
    }
    
    // MARK: - 分享按钮（支持今日或往日穿搭）
    private var shareButton: some View {
        Button {
            Task {
                await generateShareImageAsync()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                let isToday = Calendar.current.isDateInToday(selectedDate)
                Text(isToday ? "分享今日穿搭" : "分享穿搭色")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.pink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .stroke(Color.pink, lineWidth: 2)
            )
        }
        .disabled(isSharing)
    }


    
    // MARK: - 执行打卡（使用快速打卡，优先用户体验）
    private func performCheckIn() {
        Task {
            // 使用快速打卡方法，立即响应用户
            if let _ = await checkInManager.performQuickCheckIn() {
                await MainActor.run {
                    withAnimation {
                        showCelebration = true
                    }
                }
            }
        }
    }
    
    // MARK: - 异步生成分享图片（支持今日或往日穿搭）
    private func generateShareImageAsync() async {
        await MainActor.run { isSharing = true }

        // 确定要分享的穿搭色和日期
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let outfitToShare = isToday ? checkInManager.todayOutfitColor : selectedDateOutfit
        let dateToShare = selectedDate
        let consecutiveDaysToShare = isToday ? checkInManager.consecutiveDays : nil

        // 在后台线程生成图片
        let image = await Task.detached(priority: .userInitiated) {
            let renderer = ImageRenderer(content: CheckInShareCardView(
                outfit: outfitToShare,
                date: dateToShare,
                consecutiveDays: consecutiveDaysToShare
            ))
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage
        }.value

        await MainActor.run { isSharing = false }

        guard let image = image else { return }

        await MainActor.run {
            shareImage = image
            showShareSheet = true
        }
    }
    
    // MARK: - 辅助方法
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateFormat = "MM月dd日 EEEE"
        return formatter.string(from: Date())
    }
    
    private func isToday(weekday: Int) -> Bool {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        // 转换为周一为0的索引
        let todayIndex = (today + 5) % 7
        return weekday == todayIndex
    }
}

// MARK: - 打卡庆祝动画
struct CheckInCelebrationView: View {
    let onComplete: () -> Void
    
    @State private var showContent = false
    @State private var scale = 0.5
    
    var body: some View {
        ZStack {
            // 背景
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 成功图标
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .fill(Color.pink)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(scale)
                
                // 文字
                VStack(spacing: 8) {
                    Text("打卡成功！")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("今日穿搭色已解锁")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // 按钮
                Button {
                    onComplete()
                } label: {
                    Text("知道了")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.pink)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.white)
                        )
                }
                .padding(.top, 16)
            }
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showContent = true
                scale = 1.0
            }
        }
    }
}

// MARK: - 打卡分享卡片（支持今日或往日穿搭）
struct CheckInShareCardView: View {
    let outfit: TodayOutfitColor?
    let date: Date
    let consecutiveDays: Int?

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.97),
                    Color(red: 0.98, green: 0.92, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                // 顶部标题
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                    Text("少女心愿衣橱")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.pink)
                }

                // 日期
                Text(shareDateString)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                // 穿搭色展示
                if let outfit = outfit {
                    VStack(spacing: 16) {
                        // 标题根据是否是今日动态变化
                        Text(isToday ? "今日穿搭色" : "穿搭色推荐")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)

                        // 萌宠推荐标签
                        HStack(spacing: 4) {
                            Image(systemName: outfit.source == "ai" ? "sparkles" : "pawprint.fill")
                                .font(.caption)
                            Text("\(outfit.petName ?? "萌宠")推荐")
                                .font(.caption)
                        }
                        .foregroundColor(outfit.source == "ai" ? .purple : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(outfit.source == "ai" ? Color.purple.opacity(0.1) : Color.orange.opacity(0.1))
                        )

                        HStack(spacing: 16) {
                            ForEach(outfit.colors, id: \.self) { colorInfo in
                                let color = colorInfo.color
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 60, height: 60)
                                        .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)

                                    Text(colorInfo.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                }
                            }
                        }

                        // 小物搭配
                        VStack(alignment: .leading, spacing: 8) {
                            Text("小物搭配")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)

                            Text(outfit.accessories)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // 连续打卡（仅今日显示）
                if let consecutiveDays = consecutiveDays {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("连续打卡 \(consecutiveDays) 天")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }

                // 底部标语
                Text("记录每一天的美好")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(30)
        }
        .frame(width: 320, height: 520)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var shareDateString: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        if isToday {
            formatter.dateFormat = "yyyy年MM月dd日"
        } else {
            formatter.dateFormat = "yyyy年MM月dd日 EEEE"
        }
        return formatter.string(from: date)
    }

}

// MARK: - 日历日期项（用于ForEach）
struct CalendarDayItem: Identifiable {
    let id = UUID()
    let date: Date?
    let index: Int
}

// MARK: - 自定义日历视图（支持打勾标记）
struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    @ObservedObject var checkInManager: DailyCheckInManager
    let onDateSelected: (Date) -> Void
    
    @State private var currentMonth: Date
    
    private let calendar = Calendar.current
    private let weekDays = ["日", "一", "二", "三", "四", "五", "六"]
    
    init(selectedDate: Binding<Date>, checkInManager: DailyCheckInManager, onDateSelected: @escaping (Date) -> Void) {
        self._selectedDate = selectedDate
        self.checkInManager = checkInManager
        self.onDateSelected = onDateSelected
        
        // 获取选中日期所在月份的第一天
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        let monthStart = calendar.date(from: components) ?? selectedDate.wrappedValue
        self._currentMonth = State(initialValue: monthStart)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 月份导航栏
            HStack {
                Button {
                    withAnimation {
                        currentMonth = previousMonth()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.pink)
                        .padding(8)
                }
                
                Spacer()
                
                // 月份标题按钮，点击回到今天
                Button {
                    withAnimation {
                        let today = Date()
                        selectedDate = today
                        currentMonth = getFirstDayOfMonth(for: today)
                    }
                } label: {
                    Text(monthYearString)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        currentMonth = nextMonth()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pink)
                        .padding(8)
                }
                .disabled(isCurrentMonth)
            }
            
            // 星期标题
            HStack {
                ForEach(weekDays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // 日期网格 - 使用计算属性确保数据更新时刷新
            calendarGrid
        }
        .onAppear {
            syncMonthToSelectedDate()
        }
        .onChange(of: selectedDate) { _, _ in
            syncMonthToSelectedDate()
        }
        // 监听刷新触发器，强制刷新视图
        .onChange(of: checkInManager.refreshTrigger) { _, _ in
            // 刷新触发器变化时，视图会自动重新计算
        }
    }
    
    // 日历网格 - 使用计算属性确保每次刷新时都重新计算
    private var calendarGrid: some View {
        let items = calendarDayItems
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(items) { item in
                if let date = item.date {
                    CalendarDayCellView(
                        date: date,
                        selectedDate: $selectedDate,
                        checkInManager: checkInManager,
                        onTap: { onDateSelected(date) }
                    )
                } else {
                    Color.clear
                        .frame(height: 36)
                }
            }
        }
    }
    
    // 计算属性：获取日历日期项数组
    private var calendarDayItems: [CalendarDayItem] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }
        
        let firstDayOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let emptyDays = firstWeekday - 1
        
        guard let daysInMonthCount = calendar.range(of: .day, in: .month, for: currentMonth)?.count else {
            return []
        }
        
        var items: [CalendarDayItem] = []
        
        // 添加空白天数
        for index in 0..<emptyDays {
            items.append(CalendarDayItem(date: nil, index: index))
        }
        
        // 添加日期
        for day in 1...daysInMonthCount {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                items.append(CalendarDayItem(date: date, index: emptyDays + day - 1))
            }
        }
        
        return items
    }
    
    // 月份年份字符串
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateFormat = "yyyy年MM月"
        return formatter.string(from: currentMonth)
    }
    
    // 是否当前月份（禁用下个月按钮）
    private var isCurrentMonth: Bool {
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: Date())
        let displayedMonthComponents = calendar.dateComponents([.year, .month], from: currentMonth)
        return currentMonthComponents == displayedMonthComponents
    }
    
    // 获取月份的第一天
    private func getFirstDayOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
    
    // 上一个月
    private func previousMonth() -> Date {
        calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    
    // 下一个月
    private func nextMonth() -> Date {
        calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
    
    // 同步月份到选中日期
    private func syncMonthToSelectedDate() {
        let selectedComponents = calendar.dateComponents([.year, .month], from: selectedDate)
        let currentComponents = calendar.dateComponents([.year, .month], from: currentMonth)
        
        if selectedComponents.year != currentComponents.year ||
           selectedComponents.month != currentComponents.month {
            if let newMonth = calendar.date(from: selectedComponents) {
                withAnimation {
                    currentMonth = newMonth
                }
            }
        }
    }
}

// MARK: - 日历日期单元格视图
struct CalendarDayCellView: View {
    let date: Date
    @Binding var selectedDate: Date
    @ObservedObject var checkInManager: DailyCheckInManager
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    // 计算属性：是否选中
    private var isSelected: Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }
    
    // 计算属性：是否今天
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    // 计算属性：是否已打卡 - 每次刷新时重新计算
    private var isCheckedIn: Bool {
        checkInManager.hasCheckIn(on: date)
    }
    
    // 计算属性：是否未来日期
    private var isFuture: Bool {
        date > Date()
    }
    
    var body: some View {
        Button {
            if !isFuture {
                selectedDate = date
                onTap()
            }
        } label: {
            ZStack {
                // 背景圆圈（打卡时显示粉色背景）
                if isCheckedIn {
                    Circle()
                        .fill(Color.pink.opacity(0.2))
                        .frame(width: 36, height: 36)
                }
                
                // 选中边框
                if isSelected {
                    Circle()
                        .stroke(Color.pink, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
                
                // 内容：打勾或日期数字
                if isCheckedIn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.pink)
                } else {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 14))
                        .foregroundColor(textColor)
                }
            }
            .frame(height: 36)
        }
        .disabled(isFuture)
    }
    
    private var textColor: Color {
        if isFuture {
            return .secondary.opacity(0.3)
        } else if isToday {
            return .pink
        } else {
            return .primary
        }
    }
}

// MARK: - Date 扩展
extension Date {
    /// 获取当天的开始时间（00:00:00）
    var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }
}

// MARK: - 预览
#Preview {
    DailyCheckInView()
}
