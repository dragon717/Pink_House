//
//  PetChatView.swift
//  ItemManager
//
//  萌宠对话视图 - 整合AI对话、衣橱统计、查询、搭配色、搜索功能
//

import SwiftUI
import SwiftData

// MARK: - 超时包装函数（使用 PetAIService 中的 TimeoutError）
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // 添加主任务
        group.addTask {
            try await operation()
        }

        // 添加超时任务
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        // 等待第一个完成的任务
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - 消息类型枚举
enum PetChatMessageType {
    case text           // 普通文本
    case wardrobeCard   // 衣橱卡片
    case statistics     // 统计数据
    case colorMatch     // 搭配色推荐
    case searchResults  // 搜索结果
    case thinking       // AI思考中
    case outfitSuggestion // 搭配建议（新增）
}

// MARK: - 搭配建议数据
struct OutfitSuggestionData {
    let outfit: Outfit
    let description: String
    let style: String
    let occasion: String
}

// MARK: - 萌宠对话消息模型
struct PetChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let type: PetChatMessageType
    let timestamp: Date
    var clothing: Clothing?           // 关联的衣橱卡片
    var searchResults: [Clothing]?    // 搜索结果
    var statistics: WardrobeStats?    // 统计数据
    var colorRecommendation: ColorRecommendation?  // 搭配色推荐
    var imageName: String?            // 表情图片名称 (如 happy_cat, sleepy_cat)
    var isAIGenerated: Bool           // 是否AI生成
    var outfitSuggestion: OutfitSuggestionData? // 搭配建议（新增）

    init(text: String, isUser: Bool, type: PetChatMessageType = .text,
         clothing: Clothing? = nil, searchResults: [Clothing]? = nil,
         statistics: WardrobeStats? = nil, colorRecommendation: ColorRecommendation? = nil,
         imageName: String? = nil, isAIGenerated: Bool = false,
         outfitSuggestion: OutfitSuggestionData? = nil) {
        self.text = text
        self.isUser = isUser
        self.type = type
        self.timestamp = Date()
        self.clothing = clothing
        self.searchResults = searchResults
        self.statistics = statistics
        self.colorRecommendation = colorRecommendation
        self.imageName = imageName
        self.isAIGenerated = isAIGenerated
        self.outfitSuggestion = outfitSuggestion
    }
}

// MARK: - 衣橱统计数据
struct WardrobeStats {
    let totalCount: Int
    let totalValue: Decimal
    let mostExpensiveItem: Clothing?
    let depositPlanCount: Int
    let totalDeposit: Decimal
    let totalBalance: Decimal
}

// MARK: - 搭配色推荐
struct ColorRecommendation {
    let primaryColor: String
    let secondaryColor: String
    let accentColor: String
    let description: String
    let reasoning: String
}

// MARK: - AI思考动画视图
struct AIThinkingAnimation: View {
    @State private var dotScales: [CGFloat] = [0.5, 0.5, 0.5]
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.pink.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotScales[index])
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: dotScales[index]
                    )
            }
        }
        .onAppear {
            for i in 0..<3 {
                dotScales[i] = 1.0
            }
        }
    }
}

// MARK: - 现代AI思考指示器
struct ModernAIThinkingView: View {
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 12) {
            // 旋转的圆环动画
            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(0.2), lineWidth: 3)
                    .frame(width: 24, height: 24)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(rotation))
            }
            
            Text("思考中")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            AIThinkingAnimation()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseScale = 1.05
            }
        }
    }
}

// MARK: - 萌宠对话气泡
struct PetChatBubble: View {
    let message: PetChatMessage
    let petName: String
    let onCardTap: (Clothing) -> Void
    let onSearchResultTap: (Clothing) -> Void
    let onOutfitTap: (OutfitSuggestionData) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var showAllResults = false
    @State private var showingReportButton = false
    
    // 获取当前宠物角色
    private var currentPetCharacter: PetCharacter {
        guard let petId = PetDataManager.shared.status.selectedPetId,
              let character = PetCharacter(rawValue: petId) else {
            return .naicha // 默认返回奶茶
        }
        return character
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser {
                // AI头像 - 使用萌宠肖像
                petAvatarView
            } else {
                Spacer()
            }
            
            // 消息内容
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // AI生成标识
                if !message.isUser && message.isAIGenerated {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("AI 生成")
                            .font(.caption2)
                    }
                    .foregroundStyle(.pink.opacity(0.8))
                    .padding(.leading, 4)
                }
                
                switch message.type {
                case .text, .thinking:
                    textBubble
                case .wardrobeCard:
                    if let clothing = message.clothing {
                        wardrobeCardBubble(clothing)
                    } else {
                        textBubble
                    }
                case .statistics:
                    if let stats = message.statistics {
                        statisticsBubble(stats)
                    } else {
                        textBubble
                    }
                case .colorMatch:
                    if let colorRec = message.colorRecommendation {
                        colorMatchBubble(colorRec)
                    } else {
                        textBubble
                    }
                case .searchResults:
                    if let results = message.searchResults {
                        searchResultsBubble(results)
                    } else {
                        textBubble
                    }
                case .outfitSuggestion:
                    if let suggestion = message.outfitSuggestion {
                        outfitSuggestionBubble(suggestion)
                    } else {
                        textBubble
                    }
                }
                
                // 时间戳和举报按钮
                HStack(spacing: 12) {
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.8))
                    
                    // 举报按钮 (长按后显示)
                    if !message.isUser && message.isAIGenerated && showingReportButton {
                        Button(action: {
                            showingReportButton = false
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.bubble")
                                    .font(.caption2)
                                Text("举报")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.pink)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.leading, message.isUser ? 0 : 4)
            }
            
            if message.isUser {
                // 用户头像 - 使用 UserAvatarView
                userAvatarView
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
    }
    
    // 萌宠头像视图 - 使用 happy_cat 表情图片
    private var petAvatarView: some View {
        Image("happy_cat")
            .resizable()
            .scaledToFill()
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.pink.opacity(0.3), lineWidth: 2)
            )
    }
    
    // 用户头像视图 - 使用账户与同步界面的 UserAvatarView
    private var userAvatarView: some View {
        UserAvatarView(
            givenName: AuthenticationManager.shared.givenName,
            familyName: AuthenticationManager.shared.familyName,
            customAvatarPath: AuthenticationManager.shared.customAvatarPath,
            size: 40
        )
    }
    
    // 格式化时间戳为 HH:mm:ss
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    // 文本气泡
    private var textBubble: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            // 表情图片 (仅AI消息且存在图片时显示)
            if !message.isUser, let imageName = message.imageName {
                if let image = UIImage(named: imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(12)
                        .overlay(alignment: .bottomTrailing) {
                            // 印章效果
                            PetStampView()
                                .scaleEffect(0.5)
                                .padding(4)
                        }
                } else {
                    // 图片不存在时显示占位符
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 150, height: 150)
                            .cornerRadius(12)
                        
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text(imageName)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            // 文本内容
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.isUser ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(message.isUser ? Color.pink : Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                )
        }
        .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
        .onLongPressGesture {
            if !message.isUser && message.isAIGenerated {
                withAnimation {
                    showingReportButton = true
                }
            }
        }
    }
    
    // 衣橱卡片气泡
    private func wardrobeCardBubble(_ clothing: Clothing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Button {
                onCardTap(clothing)
            } label: {
                HStack(spacing: 12) {
                    // 图片
                    if let firstImagePath = clothing.imagePaths.first {
                        AsyncLocalImageView(
                            fileName: firstImagePath,
                            displaySize: CGSize(width: 60, height: 60),
                            contentMode: .fill,
                            cornerRadius: 8,
                            placeholderColor: Color.gray.opacity(0.2)
                        )
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "tshirt")
                                    .foregroundStyle(.secondary)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clothing.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        if let brand = clothing.brand {
                            Text(brand.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("¥\(NSDecimalNumber(decimal: clothing.price + clothing.accessoriesPrice).stringValue)")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxWidth: 320, alignment: .leading)
    }
    
    // 统计数据气泡
    private func statisticsBubble(_ stats: WardrobeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            VStack(spacing: 10) {
                statRow(icon: "hanger", title: "总件数", value: "\(stats.totalCount) 件")
                statRow(icon: "yensign.circle", title: "总价值", value: "¥\(NSDecimalNumber(decimal: stats.totalValue).stringValue)")
                
                if let mostExpensive = stats.mostExpensiveItem {
                    statRow(icon: "crown", title: "最贵单品", value: mostExpensive.name)
                }
                
                if stats.depositPlanCount > 0 {
                    statRow(icon: "tag", title: "尾款天使", value: "\(stats.depositPlanCount) 款")
                    statRow(icon: "creditcard", title: "待付尾款", value: "¥\(NSDecimalNumber(decimal: stats.totalBalance).stringValue)")
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxWidth: 320, alignment: .leading)
    }
    
    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.pink)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
    
    // 搭配色推荐气泡
    private func colorMatchBubble(_ colorRec: ColorRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            // 色卡展示
            HStack(spacing: 8) {
                colorCircle(colorRec.primaryColor, label: "主色")
                colorCircle(colorRec.secondaryColor, label: "辅色")
                colorCircle(colorRec.accentColor, label: "点缀")
            }
            
            Text(colorRec.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxWidth: 320, alignment: .leading)
    }
    
    private func colorCircle(_ colorName: String, label: String) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(colorFromName(colorName))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private func colorFromName(_ name: String) -> Color {
        let colorMap: [String: Color] = [
            "粉色": .pink, "红色": .red, "橙色": .orange, "黄色": .yellow,
            "绿色": .green, "蓝色": .blue, "紫色": .purple, "黑色": .black,
            "白色": .white, "灰色": .gray, "棕色": .brown, "米色": Color(red: 0.96, green: 0.91, blue: 0.84)
        ]
        return colorMap[name] ?? .pink
    }
    
    // 搜索结果气泡
    private func searchResultsBubble(_ results: [Clothing]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            VStack(spacing: 8) {
                // 根据展开状态显示不同数量的结果
                ForEach(showAllResults ? results : Array(results.prefix(3))) { clothing in
                    Button {
                        onSearchResultTap(clothing)
                    } label: {
                        HStack(spacing: 10) {
                            if let firstImagePath = clothing.imagePaths.first {
                                AsyncLocalImageView(
                                    fileName: firstImagePath,
                                    displaySize: CGSize(width: 40, height: 40),
                                    contentMode: .fill,
                                    cornerRadius: 6,
                                    placeholderColor: Color.gray.opacity(0.2)
                                )
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "tshirt")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clothing.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                
                                Text("¥\(NSDecimalNumber(decimal: clothing.price).stringValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.pink)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // 展开/收起按钮
                if results.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showAllResults.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showAllResults ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text(showAllResults ? "收起" : "还有 \(results.count - 3) 件...")
                                .font(.caption)
                        }
                        .foregroundStyle(.pink)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .background(Color.pink.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxWidth: 320, alignment: .leading)
    }

    // MARK: - 搭配建议气泡
    private func outfitSuggestionBubble(_ suggestion: OutfitSuggestionData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 描述文本
            Text(suggestion.description)
                .font(.subheadline)
                .foregroundStyle(.primary)

            // 风格标签
            HStack(spacing: 8) {
                Label(suggestion.style, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.pink.opacity(0.1))
                    .clipShape(Capsule())

                Label(suggestion.occasion, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(Capsule())
            }

            // 预览图（使用Outfit的快照或占位符）
            if let snapshotPath = suggestion.outfit.snapshotPath,
               let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // 显示物品缩略图网格
                outfitItemsPreview(suggestion.outfit)
            }

            // 查看详情按钮
            Button {
                onOutfitTap(suggestion)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("查看搭配")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.pink, .pink.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxWidth: 320, alignment: .leading)
    }

    // 搭配物品预览
    private func outfitItemsPreview(_ outfit: Outfit) -> some View {
        let items = outfit.items ?? []
        return HStack(spacing: 8) {
            ForEach(items.prefix(4), id: \.id) { item in
                if let cutout = item.cutout,
                   let image = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "tshirt")
                                .foregroundStyle(.gray)
                        )
                }
            }

            if items.count > 4 {
                Text("+\(items.count - 4)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - 萌宠对话主视图
@available(iOS 18.0, *)
struct PetChatView: View {
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]

    @StateObject private var petAI = PetAIService.shared
    @State private var messages: [PetChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @State private var selectedClothing: Clothing?
    @State private var navigateToDetail = false
    // iOS26搜索栏展开状态（用于控制常用菜单长按交互）
    @State private var isSearchPresented = false

    // 搭配建议相关状态
    @State private var selectedOutfit: Outfit?
    @State private var navigateToOutfitEditor = false

    // 每日问候管理器
    @StateObject private var greetingManager = DailyGreetingManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                // 聊天记录 - 使用overlay放置悬浮按钮
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                messageBubble(for: message)
                            }
                            
                            if isThinking {
                                HStack {
                                    ModernAIThinkingView()
                                        .id("thinking")
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: messages.count) { _ in
                        if let lastId = messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isThinking) { _ in
                        if isThinking {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(petAI.petName)的悄悄话")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "和萌宠对话、搜索裙子..."
            )
            .onSubmit(of: .search) {
                if !searchText.isEmpty {
                    sendMessageFromSearchBar()
                }
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                if let clothing = selectedClothing {
                    ClothingDetailView(clothing: clothing)
                }
            }
            .navigationDestination(isPresented: $navigateToOutfitEditor) {
                if let outfit = selectedOutfit {
                    OOTDEditorView(outfit: outfit)
                }
            }
            .onAppear {
                if messages.isEmpty {
                    loadInitialGreeting()
                }
                // 配置AI服务
                configureAIService()
            }
            .onChange(of: isSearchPresented) { oldValue, newValue in
                // 当iOS26搜索栏展开/收起时，通知常用菜单禁用/启用长按交互
                NotificationCenter.default.post(
                    name: .petChatSearchStateChanged,
                    object: nil,
                    userInfo: ["isSearching": newValue]
                )
            }
            // iOS26+ 悬浮按钮 - 使用 safeAreaInset 确保跟随键盘移动
            .safeAreaInset(edge: .bottom) {
                // 当搜索栏展开时显示按钮在键盘上方
                if isSearchPresented {
                    HStack {
                        // 左侧菜单按钮
                        iOS26LeftFloatingButton
                            .padding(.leading, 16)
                        
                        Spacer()
                        
                        // 右侧发送按钮
                        iOS26RightFloatingButton
                            .padding(.trailing, 16)
                    }
                    .padding(.vertical, 60)
                    .background(.clear) // 透明背景，不遮挡内容
                }
            }
            // 搜索栏收起时的悬浮按钮（原位显示）
            .overlay(alignment: .bottom) {
                if !isSearchPresented {
                    HStack {
                        iOS26LeftFloatingButton
                            .padding(.leading, 16)
                        
                        Spacer()
                        
                        iOS26RightFloatingButton
                            .padding(.trailing, 16)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // iOS26+ 左侧悬浮菜单按钮
    private var iOS26LeftFloatingButton: some View {
        Menu {
            Section("AI搭配") {
                Button {
                    handleOutfitSuggestion("帮我搭配一套")
                } label: {
                    Label("智能搭配", systemImage: "wand.and.stars")
                }

                Menu("快速搭配") {
                    Button {
                        createQuickOutfit(style: "甜美", occasion: "约会")
                    } label: {
                        Label("甜美约会", systemImage: "heart.fill")
                    }

                    Button {
                        createQuickOutfit(style: "优雅", occasion: "茶会")
                    } label: {
                        Label("优雅茶会", systemImage: "cup.and.saucer.fill")
                    }

                    Button {
                        createQuickOutfit(style: "日常", occasion: "出门")
                    } label: {
                        Label("日常出门", systemImage: "bag.fill")
                    }
                }
            }

            Section("快捷功能") {
                Button {
                    handleWardrobeStatistics()
                } label: {
                    Label("统计裙子", systemImage: "chart.pie.fill")
                }

                Button {
                    handleColorMatch()
                } label: {
                    Label("今日搭配色", systemImage: "paintpalette.fill")
                }

                Button {
                    handleDepositPlanQuery()
                } label: {
                    Label("尾款提醒", systemImage: "tag.fill")
                }
            }

            Section("查找") {
                Button {
                    // 设置搜索栏文本为"帮我找"
                    searchText = "帮我找"
                } label: {
                    Label("查找衣柜", systemImage: "magnifyingglass")
                }
            }

            Section("其他") {
                Button {
                    // 随机推荐
                    handleColorMatch()
                } label: {
                    Label("随机推荐", systemImage: "sparkles")
                }

                Button {
                    // 今日运势
                    let fortunes = [
                        "今天很适合穿粉色系的小裙子哦~",
                        "主人今天运气不错，适合买新裙子！",
                        "今天适合整理衣橱，给裙子们拍拍照吧~",
                        "主人今天会遇到心仪的裙子哦，多逛逛吧~"
                    ]
                    let randomFortune = fortunes.randomElement()!
                    let message = PetChatMessage(text: randomFortune, isUser: false)
                    messages.append(message)
                } label: {
                    Label("今日运势", systemImage: "star.fill")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24))
                .foregroundStyle(.pink)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
        }
    }
    
    // iOS26+ 右侧悬浮发送按钮
    private var iOS26RightFloatingButton: some View {
        Button {
            if !searchText.isEmpty {
                sendMessageFromSearchBar()
            }
        } label: {
            Text("发送")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(searchText.isEmpty ? .gray.opacity(0.5) : .pink)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
        }
        .disabled(searchText.isEmpty)
    }
    
    // 从底部输入框发送消息 - 等同于 PetDialogueInputView 的功能
    private func sendMessageFromInput() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        // 清空输入框
        inputText = ""
        
        // 添加用户消息到对话
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图
        processUserIntent(userText)
    }
    
    // 从搜索栏发送消息 - 等同于 PetDialogueInputView 的功能
    private func sendMessageFromSearchBar() {
        let userText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        // 清空搜索栏
        searchText = ""
        
        // 添加用户消息到对话
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图（和底部输入框一样的逻辑）
        processUserIntent(userText)
    }
    
    // 处理来自搜索栏的搜索（菜单中的搜索功能）
    private func handleSearchFromSearchBar(_ query: String) {
        // 添加用户搜索消息
        let userMessage = PetChatMessage(text: "\(query)", isUser: true)
        messages.append(userMessage)
        
        isThinking = true
        
        // 执行搜索
        let results = clothings.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(query) ||
            (clothing.brand?.name.localizedCaseInsensitiveContains(query) ?? false) ||
            clothing.types.localizedCaseInsensitiveContains(query) ||
            (clothing.tags?.contains { $0.name.localizedCaseInsensitiveContains(query) } ?? false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isThinking = false
            
            let responseText: String
            if results.isEmpty {
                responseText = "喵... 没找到相关的裙子呢，要不要看看其他的？"
            } else {
                responseText = "（眼睛发亮）找到\(results.count)件相关的裙子，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: results.isEmpty ? nil : results
            )
            messages.append(message)
            
            // 清空搜索栏
            searchText = ""
        }
    }
    
    // 配置AI服务
    private func configureAIService() {
        let wardrobeContext = WardrobeContextManager.shared.generateWardrobeSummary(clothings: clothings)
        petAI.ensureConfiguration(
            role: .kitten,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: wardrobeContext
        )
    }
    
    // 加载初始问候
    private func loadInitialGreeting() {
        let greeting = greetingManager.getGreetingTitle()
        let welcomeMessage = PetChatMessage(
            text: "\(greeting)喵~ 我是你的专属衣橱管家\(petAI.petName)，有什么可以帮你的吗？",
            isUser: false
        )
        messages.append(welcomeMessage)
    }
    
    // 发送消息
    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        inputText = ""
        
        // 添加用户消息
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图
        processUserIntent(userText)
    }
    
    // 处理用户意图
    private func processUserIntent(_ text: String) {
        let lowercasedText = text.lowercased()

        // 检查是否是统计查询
        if lowercasedText.contains("统计") || lowercasedText.contains("多少") ||
           lowercasedText.contains("价值") || lowercasedText.contains("几件") {
            handleWardrobeStatistics()
            return
        }

        // 检查是否是OOTD/搭配查询（优先于颜色搭配）
        if lowercasedText.contains("ootd") || lowercasedText.contains("造型") ||
           lowercasedText.contains("穿搭") || lowercasedText.contains("怎么穿") ||
           (lowercasedText.contains("搭配") && (lowercasedText.contains("一套") || lowercasedText.contains("出门") || lowercasedText.contains("今天"))) {
            handleOutfitSuggestion(text)
            return
        }

        // 检查是否是搭配色查询
        if lowercasedText.contains("搭配") || lowercasedText.contains("颜色") ||
           lowercasedText.contains("穿什么") || lowercasedText.contains("推荐") {
            handleColorMatch()
            return
        }

        // 检查是否是搜索查询
        if lowercasedText.contains("找") || lowercasedText.contains("搜索") ||
           lowercasedText.contains("有没有") {
            handleSearch(text)
            return
        }

        // 检查是否是尾款查询
        if lowercasedText.contains("尾款") || lowercasedText.contains("定金") ||
           lowercasedText.contains("补款") {
            handleDepositPlanQuery()
            return
        }

        // 默认使用AI对话
        handleAIChat(text)
    }

    // 创建消息气泡视图
    private func messageBubble(for message: PetChatMessage) -> some View {
        PetChatBubble(
            message: message,
            petName: petAI.petName,
            onCardTap: handleClothingTap,
            onSearchResultTap: handleClothingTap,
            onOutfitTap: handleOutfitTap
        )
        .id(message.id)
    }

    // 处理服装点击
    private func handleClothingTap(_ clothing: Clothing) {
        selectedClothing = clothing
        navigateToDetail = true
    }

    // 处理搭配建议点击
    private func handleOutfitTap(_ suggestion: OutfitSuggestionData) {
        selectedOutfit = suggestion.outfit
        navigateToOutfitEditor = true
    }

    // 处理衣橱统计
    private func handleWardrobeStatistics() {
        isThinking = true
        
        // 计算统计数据
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
        let mostExpensiveItem = clothings.max(by: { ($0.price + $0.accessoriesPrice) < ($1.price + $1.accessoriesPrice) })
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }
        
        let stats = WardrobeStats(
            totalCount: totalCount,
            totalValue: totalValue,
            mostExpensiveItem: mostExpensiveItem,
            depositPlanCount: depositPlans.count,
            totalDeposit: totalDeposit,
            totalBalance: totalBalance
        )
        
        // 模拟思考延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isThinking = false
            
            let responseText: String
            if totalCount == 0 {
                responseText = "喵？你的衣橱还是空的耶，快去添加几件漂亮裙子吧~"
            } else {
                responseText = "（翻看着小账本）主人，你的衣橱里有\(totalCount)件宝贝，总价值\(NSDecimalNumber(decimal: totalValue).stringValue)元呢！"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .statistics,
                statistics: stats
            )
            messages.append(message)
        }
    }
    
    // 处理搭配色推荐
    private func handleColorMatch() {
        isThinking = true
        
        // 根据衣橱颜色分布生成推荐
        let colorRecommendations = [
            ColorRecommendation(
                primaryColor: "粉色",
                secondaryColor: "白色",
                accentColor: "米色",
                description: "甜美优雅",
                reasoning: "粉色系是Lo裙的经典配色，白色和米色的点缀能让整体更加温柔~"
            ),
            ColorRecommendation(
                primaryColor: "蓝色",
                secondaryColor: "白色",
                accentColor: "银色",
                description: "清新梦幻",
                reasoning: "蓝色系像天空一样清新，适合夏日穿搭，银色点缀增添梦幻感~"
            ),
            ColorRecommendation(
                primaryColor: "紫色",
                secondaryColor: "黑色",
                accentColor: "金色",
                description: "神秘高贵",
                reasoning: "紫色与黑色的搭配神秘又高贵，金色点缀更显华丽~"
            )
        ]
        
        let randomRec = colorRecommendations.randomElement()!
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isThinking = false
            
            let message = PetChatMessage(
                text: "（歪头思考）主人今天想走什么风格呢？我给你搭配了一套~",
                isUser: false,
                type: .colorMatch,
                colorRecommendation: randomRec
            )
            messages.append(message)
        }
    }
    
    // 处理搜索
    private func handleSearch(_ query: String) {
        isThinking = true
        
        // 提取搜索关键词
        let keywords = query
            .replacingOccurrences(of: "帮我找", with: "")
            .replacingOccurrences(of: "搜索", with: "")
            .replacingOccurrences(of: "有没有", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let results = clothings.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(keywords) ||
            (clothing.brand?.name.localizedCaseInsensitiveContains(keywords) ?? false) ||
            clothing.types.localizedCaseInsensitiveContains(keywords)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if results.isEmpty {
                responseText = "喵... 没找到相关的裙子呢，要不要看看其他的？"
            } else {
                responseText = "（眼睛发亮）找到\(results.count)件相关的裙子，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: results.isEmpty ? nil : results
            )
            messages.append(message)
        }
    }
    
    // 处理尾款查询
    private func handleDepositPlanQuery() {
        isThinking = true
        
        // 计算完整的衣橱统计数据
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if depositPlans.isEmpty {
                responseText = "喵~ 目前没有待补款的裙子呢，主人的钱包可以休息一下啦！"
            } else {
                responseText = "（认真脸）主人还有\(depositPlans.count)款裙子要补尾款，一共要准备\(NSDecimalNumber(decimal: totalBalance).stringValue)元喵~"
            }
            
            let stats = WardrobeStats(
                totalCount: totalCount,
                totalValue: totalValue,
                mostExpensiveItem: nil,
                depositPlanCount: depositPlans.count,
                totalDeposit: totalDeposit,
                totalBalance: totalBalance
            )
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: depositPlans.isEmpty ? .text : .statistics,
                statistics: depositPlans.isEmpty ? nil : stats
            )
            messages.append(message)
        }
    }
    
    // 处理AI对话
    private func handleAIChat(_ text: String) {
        isThinking = true

        Task {
            let response = await petAI.sendMessage(text, enableVoice: false)

            await MainActor.run {
                isThinking = false

                // PetAIService 返回的 ChatMessage 已经解析过 [IMAGE:xxx] 指令
                // 直接使用 response.imageName 和 response.text
                let message = PetChatMessage(
                    text: response.text,
                    isUser: false,
                    imageName: response.imageName,
                    isAIGenerated: true
                )
                messages.append(message)
            }
        }
    }

    // MARK: - 搭配建议处理

    /// 处理搭配建议请求
    private func handleOutfitSuggestion(_ text: String) {
        // 检查是否有足够的抠图
        let availableCount = OutfitSuggestionService.shared.availableCutoutCount(context: modelContext)
        guard availableCount >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的抠图还不够呢，至少需要2件单品才能搭配喵~ 快去生成一些抠图吧！",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制，防止卡住
                let (outfit, responseText) = try await withTimeout(seconds: 30) {
                    try await OutfitSuggestionService.shared.processOutfitRequest(
                        query: text,
                        clothings: self.clothings,
                        context: self.modelContext
                    )
                }

                await MainActor.run {
                    isThinking = false

                    let suggestionData = OutfitSuggestionData(
                        outfit: outfit,
                        description: responseText,
                        style: "日常",
                        occasion: "日常"
                    )

                    let message = PetChatMessage(
                        text: responseText,
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成超时了，请检查网络后重试喵~",
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false

                    let errorMessage = (error as? OutfitSuggestionError)?.errorDescription ?? "搭配生成失败，请重试喵~"
                    let message = PetChatMessage(
                        text: "（挠头）\(errorMessage)",
                        isUser: false
                    )
                    messages.append(message)
                }
            }
        }
    }

    /// 快速创建搭配（无需AI）
    private func createQuickOutfit(style: String, occasion: String) {
        let availableCount = OutfitSuggestionService.shared.availableCutoutCount(context: modelContext)
        guard availableCount >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的抠图还不够呢，至少需要2件单品才能搭配喵~",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制
                let outfit = try await withTimeout(seconds: 15) {
                    try await OutfitSuggestionService.shared.createQuickOutfit(
                        style: style,
                        occasion: occasion,
                        clothings: self.clothings,
                        context: self.modelContext
                    )
                }

                await MainActor.run {
                    isThinking = false

                    let suggestionData = OutfitSuggestionData(
                        outfit: outfit,
                        description: "为你准备了一套\(style)风\(occasion)搭配~",
                        style: style,
                        occasion: occasion
                    )

                    let message = PetChatMessage(
                        text: "（眼睛发亮）为你准备了一套\(style)风\(occasion)搭配，快来看看吧喵~",
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成超时了，请检查网络后重试喵~",
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成失败：\(error.localizedDescription)",
                        isUser: false
                    )
                    messages.append(message)
                }
            }
        }
    }
}

// MARK: - 印章视图 (参考萌宠日记)
struct PetStampView: View {
    var body: some View {
        ZStack {
            // 外圈圆环
            Circle()
                .stroke(Color(hex: "FF69B4").opacity(0.6), lineWidth: 3)
                .frame(width: 60, height: 60)
            
            // 内部双圆环装饰
            Circle()
                .stroke(Color(hex: "FF69B4").opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: 52, height: 52)
            
            // 猫爪
            Image(systemName: "pawprint.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: "FF69B4").opacity(0.5))
                .rotationEffect(.degrees(10))
            
            // 文字装饰
            Text("REVIEWED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "FF69B4"))
                .offset(y: 22)
                .rotationEffect(.degrees(-10))
        }
        .compositingGroup()
        .opacity(0.8)
    }
}

// MARK: - 快捷操作按钮
struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - iOS 18以下版本
struct PetChatViewLegacy: View {
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]
    
    @StateObject private var petAI = PetAIService.shared
    @State private var messages: [PetChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @State private var selectedClothing: Clothing?
    @State private var navigateToDetail = false

    // 搭配建议相关状态
    @State private var selectedOutfit: Outfit?
    @State private var navigateToOutfitEditor = false

    @StateObject private var greetingManager = DailyGreetingManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    legacyMessageBubble(for: message)
                                }
                                
                                if isThinking {
                                    HStack {
                                        ModernAIThinkingView()
                                            .id("thinking")
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .onChange(of: messages.count) { _ in
                            if let lastId = messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // 底部输入区域（Legacy 版本使用萌宠对话框样式）
                    petDialogueInputArea
                }
            }
            .navigationTitle("\(petAI.petName)的悄悄话")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToDetail) {
                if let clothing = selectedClothing {
                    ClothingDetailView(clothing: clothing)
                }
            }
            .navigationDestination(isPresented: $navigateToOutfitEditor) {
                if let outfit = selectedOutfit {
                    OOTDEditorView(outfit: outfit)
                }
            }
            .onAppear {
                if messages.isEmpty {
                    loadInitialGreeting()
                }
                configureAIService()
            }
        }
    }

    // 萌宠对话框样式的输入区域（iOS18版本）- 放在底部导航栏上方
    private var petDialogueInputArea: some View {
        VStack(spacing: 0) {
            // 使用萌宠对话框样式
            HStack(spacing: 12) {
                // 左侧功能菜单按钮
                Menu {
                    // AI搭配菜单
                    Menu("AI搭配") {
                        Button {
                            handleOutfitSuggestion("帮我搭配一套")
                        } label: {
                            Label("智能搭配", systemImage: "wand.and.stars")
                        }

                        Button {
                            createQuickOutfit(style: "甜美", occasion: "约会")
                        } label: {
                            Label("甜美约会", systemImage: "heart")
                        }

                        Button {
                            createQuickOutfit(style: "优雅", occasion: "茶会")
                        } label: {
                            Label("优雅茶会", systemImage: "cup.and.saucer")
                        }

                        Button {
                            createQuickOutfit(style: "日常", occasion: "出门")
                        } label: {
                            Label("日常出门", systemImage: "bag")
                        }
                    }

                    Button {
                        handleWardrobeStatistics()
                    } label: {
                        Label("统计裙子", systemImage: "chart.pie")
                    }

                    Button {
                        handleColorMatch()
                    } label: {
                        Label("今日搭配色", systemImage: "paintpalette")
                    }

                    Button {
                        handleDepositPlanQuery()
                    } label: {
                        Label("尾款提醒", systemImage: "tag")
                    }

                    Button {
                        // 查找衣柜功能
                        inputText = "帮我找"
                    } label: {
                        Label("查找衣柜", systemImage: "magnifyingglass")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.pink)
                }
                
                // 中间输入框（萌宠对话框样式）
                ZStack(alignment: .leading) {
                    if inputText.isEmpty {
                        Text("和萌宠对话、搜索裙子...")
                            .foregroundStyle(.gray.opacity(0.6))
                            .padding(.horizontal, 16)
                    }
                    
                    TextField("", text: $inputText)
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
                
                // 右侧发送按钮（猫爪样式）
                Button {
                    if !inputText.isEmpty {
                        sendMessageFromInput()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "FFC0CB"), Color(hex: "FFB6C1")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(hex: "FF69B4").opacity(0.3), radius: 2, x: 0, y: 2)
                        
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    }
                    .frame(width: 44, height: 44)
                }
                .disabled(inputText.isEmpty)
                .opacity(inputText.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            ZStack {
                // 主体气泡背景
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFD1DC"), Color(hex: "FFC0CB")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
                
                // 气泡尾巴（左下角）
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 30, y: geo.size.height - 25))
                        path.addLine(to: CGPoint(x: 18, y: geo.size.height + 6))
                        path.addLine(to: CGPoint(x: 50, y: geo.size.height - 15))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "FFC0CB"))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        // 添加底部安全区域间距，避免与底部导航栏重叠
        .padding(.bottom, 80)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    // 从底部输入框发送消息 - 等同于 PetDialogueInputView 的功能
    private func sendMessageFromInput() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        // 清空输入框
        inputText = ""
        
        // 添加用户消息到对话
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图
        processUserIntent(userText)
    }
    
    private func configureAIService() {
        let wardrobeContext = WardrobeContextManager.shared.generateWardrobeSummary(clothings: clothings)
        petAI.ensureConfiguration(
            role: .kitten,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: wardrobeContext
        )
    }
    
    private func loadInitialGreeting() {
        let greeting = greetingManager.getGreetingTitle()
        let welcomeMessage = PetChatMessage(
            text: "\(greeting)喵~ 我是你的专属衣橱管家\(petAI.petName)，有什么可以帮你的吗？",
            isUser: false
        )
        messages.append(welcomeMessage)
    }
    
    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        inputText = ""
        
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        processUserIntent(userText)
    }

    // 创建消息气泡视图（Legacy版本）
    private func legacyMessageBubble(for message: PetChatMessage) -> some View {
        PetChatBubble(
            message: message,
            petName: petAI.petName,
            onCardTap: legacyHandleClothingTap,
            onSearchResultTap: legacyHandleClothingTap,
            onOutfitTap: legacyHandleOutfitTap
        )
        .id(message.id)
    }

    // 处理服装点击（Legacy版本）
    private func legacyHandleClothingTap(_ clothing: Clothing) {
        selectedClothing = clothing
        navigateToDetail = true
    }

    // 处理搭配建议点击（Legacy版本）
    private func legacyHandleOutfitTap(_ suggestion: OutfitSuggestionData) {
        selectedOutfit = suggestion.outfit
        navigateToOutfitEditor = true
    }

    private func processUserIntent(_ text: String) {
        let lowercasedText = text.lowercased()

        if lowercasedText.contains("统计") || lowercasedText.contains("多少") ||
           lowercasedText.contains("价值") || lowercasedText.contains("几件") {
            handleWardrobeStatistics()
            return
        }

        // 检查是否是OOTD/搭配查询（优先于颜色搭配）
        if lowercasedText.contains("ootd") || lowercasedText.contains("造型") ||
           lowercasedText.contains("穿搭") || lowercasedText.contains("怎么穿") ||
           (lowercasedText.contains("搭配") && (lowercasedText.contains("一套") || lowercasedText.contains("出门") || lowercasedText.contains("今天"))) {
            handleOutfitSuggestion(text)
            return
        }

        if lowercasedText.contains("搭配") || lowercasedText.contains("颜色") ||
           lowercasedText.contains("穿什么") || lowercasedText.contains("推荐") {
            handleColorMatch()
            return
        }

        if lowercasedText.contains("找") || lowercasedText.contains("搜索") ||
           lowercasedText.contains("有没有") {
            handleSearch(text)
            return
        }

        if lowercasedText.contains("尾款") || lowercasedText.contains("定金") ||
           lowercasedText.contains("补款") {
            handleDepositPlanQuery()
            return
        }

        handleAIChat(text)
    }

    private func handleWardrobeStatistics() {
        isThinking = true

        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
        let mostExpensiveItem = clothings.max(by: { ($0.price + $0.accessoriesPrice) < ($1.price + $1.accessoriesPrice) })
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }
        
        let stats = WardrobeStats(
            totalCount: totalCount,
            totalValue: totalValue,
            mostExpensiveItem: mostExpensiveItem,
            depositPlanCount: depositPlans.count,
            totalDeposit: totalDeposit,
            totalBalance: totalBalance
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isThinking = false
            
            let responseText: String
            if totalCount == 0 {
                responseText = "喵？你的衣橱还是空的耶，快去添加几件漂亮裙子吧~"
            } else {
                responseText = "（翻看着小账本）主人，你的衣橱里有\(totalCount)件宝贝，总价值\(NSDecimalNumber(decimal: totalValue).stringValue)元呢！"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .statistics,
                statistics: stats
            )
            messages.append(message)
        }
    }
    
    private func handleColorMatch() {
        isThinking = true
        
        let colorRecommendations = [
            ColorRecommendation(
                primaryColor: "粉色",
                secondaryColor: "白色",
                accentColor: "米色",
                description: "甜美优雅",
                reasoning: "粉色系是Lo裙的经典配色，白色和米色的点缀能让整体更加温柔~"
            ),
            ColorRecommendation(
                primaryColor: "蓝色",
                secondaryColor: "白色",
                accentColor: "银色",
                description: "清新梦幻",
                reasoning: "蓝色系像天空一样清新，适合夏日穿搭，银色点缀增添梦幻感~"
            ),
            ColorRecommendation(
                primaryColor: "紫色",
                secondaryColor: "黑色",
                accentColor: "金色",
                description: "神秘高贵",
                reasoning: "紫色与黑色的搭配神秘又高贵，金色点缀更显华丽~"
            )
        ]
        
        let randomRec = colorRecommendations.randomElement()!
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isThinking = false
            
            let message = PetChatMessage(
                text: "（歪头思考）主人今天想走什么风格呢？我给你搭配了一套~",
                isUser: false,
                type: .colorMatch,
                colorRecommendation: randomRec
            )
            messages.append(message)
        }
    }
    
    private func handleSearch(_ query: String) {
        isThinking = true
        
        let keywords = query
            .replacingOccurrences(of: "帮我找", with: "")
            .replacingOccurrences(of: "搜索", with: "")
            .replacingOccurrences(of: "有没有", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let results = clothings.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(keywords) ||
            (clothing.brand?.name.localizedCaseInsensitiveContains(keywords) ?? false) ||
            clothing.types.localizedCaseInsensitiveContains(keywords)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if results.isEmpty {
                responseText = "喵... 没找到相关的裙子呢，要不要看看其他的？"
            } else {
                responseText = "（眼睛发亮）找到\(results.count)件相关的裙子，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: results.isEmpty ? nil : results
            )
            messages.append(message)
        }
    }
    
    private func handleDepositPlanQuery() {
        isThinking = true
        
        // 计算完整的衣橱统计数据
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if depositPlans.isEmpty {
                responseText = "喵~ 目前没有待补款的裙子呢，主人的钱包可以休息一下啦！"
            } else {
                responseText = "（认真脸）主人还有\(depositPlans.count)款裙子要补尾款，一共要准备\(NSDecimalNumber(decimal: totalBalance).stringValue)元喵~"
            }
            
            let stats = WardrobeStats(
                totalCount: totalCount,
                totalValue: totalValue,
                mostExpensiveItem: nil,
                depositPlanCount: depositPlans.count,
                totalDeposit: totalDeposit,
                totalBalance: totalBalance
            )
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: depositPlans.isEmpty ? .text : .statistics,
                statistics: depositPlans.isEmpty ? nil : stats
            )
            messages.append(message)
        }
    }
    
    private func handleAIChat(_ text: String) {
        isThinking = true
        
        Task {
            let response = await petAI.sendMessage(text, enableVoice: false)
            
            await MainActor.run {
                isThinking = false
                
                // PetAIService 返回的 ChatMessage 已经解析过 [IMAGE:xxx] 指令
                // 直接使用 response.imageName 和 response.text
                let message = PetChatMessage(
                    text: response.text,
                    isUser: false,
                    imageName: response.imageName,
                    isAIGenerated: true
                )
                messages.append(message)
            }
        }
    }

    // MARK: - 搭配建议处理（Legacy版本）

    /// 处理搭配建议请求
    private func handleOutfitSuggestion(_ text: String) {
        // 检查是否有足够的抠图
        let availableCount = OutfitSuggestionService.shared.availableCutoutCount(context: modelContext)
        guard availableCount >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的抠图还不够呢，至少需要2件单品才能搭配喵~ 快去生成一些抠图吧！",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制
                let (outfit, responseText) = try await withTimeout(seconds: 30) {
                    try await OutfitSuggestionService.shared.processOutfitRequest(
                        query: text,
                        clothings: self.clothings,
                        context: self.modelContext
                    )
                }

                await MainActor.run {
                    isThinking = false

                    let suggestionData = OutfitSuggestionData(
                        outfit: outfit,
                        description: responseText,
                        style: "日常",
                        occasion: "日常"
                    )

                    let message = PetChatMessage(
                        text: responseText,
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成超时了，请检查网络后重试喵~",
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false

                    let errorMessage = (error as? OutfitSuggestionError)?.errorDescription ?? "搭配生成失败，请重试喵~"
                    let message = PetChatMessage(
                        text: "（挠头）\(errorMessage)",
                        isUser: false
                    )
                    messages.append(message)
                }
            }
        }
    }

    /// 快速创建搭配（无需AI）
    private func createQuickOutfit(style: String, occasion: String) {
        let availableCount = OutfitSuggestionService.shared.availableCutoutCount(context: modelContext)
        guard availableCount >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的抠图还不够呢，至少需要2件单品才能搭配喵~",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制
                let outfit = try await withTimeout(seconds: 15) {
                    try await OutfitSuggestionService.shared.createQuickOutfit(
                        style: style,
                        occasion: occasion,
                        clothings: self.clothings,
                        context: self.modelContext
                    )
                }

                await MainActor.run {
                    isThinking = false

                    let suggestionData = OutfitSuggestionData(
                        outfit: outfit,
                        description: "为你准备了一套\(style)风\(occasion)搭配~",
                        style: style,
                        occasion: occasion
                    )

                    let message = PetChatMessage(
                        text: "（眼睛发亮）为你准备了一套\(style)风\(occasion)搭配，快来看看吧喵~",
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成超时了，请检查网络后重试喵~",
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成失败：\(error.localizedDescription)",
                        isUser: false
                    )
                    messages.append(message)
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    if #available(iOS 18.0, *) {
        PetChatView(searchText: .constant(""))
    } else {
        PetChatViewLegacy(searchText: .constant(""))
    }
}
