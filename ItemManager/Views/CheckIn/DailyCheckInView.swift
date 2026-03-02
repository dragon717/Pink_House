import SwiftUI

// MARK: - 每日打卡视图
struct DailyCheckInView: View {
    @StateObject private var checkInManager = DailyCheckInManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var showCelebration = false
    
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
                        
                        // 今日穿搭色推荐
                        if let outfit = checkInManager.todayOutfitColor {
                            outfitColorSection(outfit: outfit)
                        }
                        
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
            
            // 问候语
            Text(greeting)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
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
    
    // MARK: - 七日签到卡片
    private var weekCheckInCard: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Text("本周签到")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("累计 \(checkInManager.totalDays) 天")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // 七日格子
            HStack(spacing: 8) {
                ForEach(0..<7) { index in
                    DayCell(
                        day: weekDays[index],
                        isCheckedIn: checkInManager.weekCheckIns[index],
                        isToday: isToday(weekday: index)
                    )
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
    
    // MARK: - 今日穿搭色区域
    private func outfitColorSection(outfit: TodayOutfitColor) -> some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Text("今日穿搭色")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 来源标签
                HStack(spacing: 4) {
                    Image(systemName: outfit.source == "ai" ? "sparkles" : "cloud.fill")
                        .font(.caption)
                    Text(outfit.source == "ai" ? "AI推荐" : "云端推荐")
                        .font(.caption)
                }
                .foregroundColor(outfit.source == "ai" ? .purple : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(outfit.source == "ai" ? Color.purple.opacity(0.1) : Color.blue.opacity(0.1))
                )
            }
            
            // 颜色展示
            HStack(spacing: 12) {
                ForEach(outfit.colors, id: \.self) { color in
                    ColorCard(colorName: color)
                }
            }
            
            // 小物搭配建议
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
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
    
    // MARK: - 分享按钮
    private var shareButton: some View {
        Button {
            generateShareImage()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("分享今日穿搭")
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
    }
    
    // MARK: - 执行打卡
    private func performCheckIn() {
        Task {
            if let _ = await checkInManager.performCheckIn() {
                await MainActor.run {
                    withAnimation {
                        showCelebration = true
                    }
                }
            }
        }
    }
    
    // MARK: - 生成分享图片
    private func generateShareImage() {
        let renderer = ImageRenderer(content: CheckInShareCardView(
            outfit: checkInManager.todayOutfitColor,
            consecutiveDays: checkInManager.consecutiveDays
        ))
        renderer.scale = UIScreen.main.scale
        
        if let uiImage = renderer.uiImage {
            shareImage = uiImage
            showShareSheet = true
        }
    }
    
    // MARK: - 辅助方法
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 EEEE"
        return formatter.string(from: Date())
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早安，少女"
        case 12..<18: return "午安，少女"
        default: return "晚安，少女"
        }
    }
    
    private func isToday(weekday: Int) -> Bool {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        // 转换为周一为0的索引
        let todayIndex = (today + 5) % 7
        return weekday == todayIndex
    }
}

// MARK: - 日期格子
struct DayCell: View {
    let day: String
    let isCheckedIn: Bool
    let isToday: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            Text(day)
                .font(.system(size: 12))
                .foregroundColor(isToday ? .pink : .secondary)
            
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)
                
                if isCheckedIn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else if isToday {
                    Circle()
                        .stroke(Color.pink, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var backgroundColor: Color {
        if isCheckedIn {
            return .pink
        } else if isToday {
            return .pink.opacity(0.1)
        } else {
            return .gray.opacity(0.1)
        }
    }
}

// MARK: - 颜色卡片
struct ColorCard: View {
    let colorName: String
    
    // 颜色映射
    private var color: Color {
        let colorMap: [String: Color] = [
            "樱花粉": Color(red: 1.0, green: 0.71, blue: 0.76),
            "奶油白": Color(red: 1.0, green: 0.98, blue: 0.94),
            "薰衣草紫": Color(red: 0.9, green: 0.8, blue: 1.0),
            "珍珠白": Color(red: 0.98, green: 0.97, blue: 0.95),
            "薄荷绿": Color(red: 0.7, green: 0.95, blue: 0.85),
            "浅灰蓝": Color(red: 0.75, green: 0.85, blue: 0.95),
            "玫瑰红": Color(red: 1.0, green: 0.4, blue: 0.5),
            "香槟金": Color(red: 0.95, green: 0.9, blue: 0.7),
            "浅金色": Color(red: 0.95, green: 0.9, blue: 0.75)
        ]
        return colorMap[colorName] ?? .pink
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 50, height: 50)
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
            
            Text(colorName)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
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

// MARK: - 打卡分享卡片
struct CheckInShareCardView: View {
    let outfit: TodayOutfitColor?
    let consecutiveDays: Int
    
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
                Text(todayDateString)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                // 穿搭色展示
                if let outfit = outfit {
                    VStack(spacing: 16) {
                        Text("今日穿搭色")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 16) {
                            ForEach(outfit.colors, id: \.self) { color in
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(colorFromName(color))
                                        .frame(width: 60, height: 60)
                                        .shadow(color: colorFromName(color).opacity(0.4), radius: 8, x: 0, y: 4)
                                    
                                    Text(color)
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
                
                // 连续打卡
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("连续打卡 \(consecutiveDays) 天")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // 底部标语
                Text("记录每一天的美好")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(30)
        }
        .frame(width: 320, height: 480)
    }
    
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: Date())
    }
    
    private func colorFromName(_ name: String) -> Color {
        let colorMap: [String: Color] = [
            "樱花粉": Color(red: 1.0, green: 0.71, blue: 0.76),
            "奶油白": Color(red: 1.0, green: 0.98, blue: 0.94),
            "薰衣草紫": Color(red: 0.9, green: 0.8, blue: 1.0),
            "珍珠白": Color(red: 0.98, green: 0.97, blue: 0.95),
            "薄荷绿": Color(red: 0.7, green: 0.95, blue: 0.85),
            "浅灰蓝": Color(red: 0.75, green: 0.85, blue: 0.95),
            "玫瑰红": Color(red: 1.0, green: 0.4, blue: 0.5),
            "香槟金": Color(red: 0.95, green: 0.9, blue: 0.7),
            "浅金色": Color(red: 0.95, green: 0.9, blue: 0.75)
        ]
        return colorMap[name] ?? .pink
    }
}

// MARK: - 预览
#Preview {
    DailyCheckInView()
}
