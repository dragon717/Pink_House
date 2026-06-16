//
//  DressStockMarketView.swift
//  裙装股市 - 主界面（整合版）
//
//  包含：商品列表 + AI 解析分享链接 + 市场统计 + K线图
//

import SwiftUI
import GRDB
import Charts

// MARK: - 主视图
struct DressStockMarketView: View {
    // MARK: - 状态
    
    @StateObject private var itemObserver = GRDBLolitaItemObserver()
    @State private var showAIParseResult = false
    @State private var parsedItem: ParsedItem?
    @State private var isSyncing = false
    @State private var searchKeyword = ""
    @State private var selectedTimeRange: TimeRange = .week
    
    // MARK: - 时间范围枚举
    enum TimeRange: String, CaseIterable {
        case day = "日K"
        case week = "周K"
        case month = "月K"
        case year = "年K"
        
        var localizedTitle: String {
            rawValue.appLocalized
        }

        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .year: return 365
            }
        }
    }
    
    // MARK: - 视图
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 搜索栏
                    SearchBar(text: $searchKeyword)
                    
                    // 价格概览卡片
                    MarketPriceOverviewCard()
                    
                    // K线图卡片
                    MarketKLineChartCard(selectedTimeRange: $selectedTimeRange)
                    
                    // 时间范围选择器
                    MarketTimeRangeSelector(selection: $selectedTimeRange)
                    
                    // 市场统计卡片
                    DressMarketStatsCard(itemCount: itemObserver.items.count)
                    
                    // 平台分布卡片
                    DressPlatformDistributionCard()
                    
                    // AI投资建议卡片
                    DressAIAnalysisCard()
                    
                    // 在售商品列表
                    DressActiveListingsSection(items: filteredItems)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("裙装股市".appLocalized)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAIParseResult = true }) {
                        Image(systemName: "link.badge.plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { Task { await manualSync() } }) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isSyncing ? 360 : 0))
                            .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                    }
                    .disabled(isSyncing)
                }
            }
        }
        .onAppear {
            itemObserver.startObservingActive()
            Task {
                await initializeGRDB()
                checkClipboard()
            }
        }
        .onDisappear {
            itemObserver.stopObserving()
        }
        .sheet(isPresented: $showAIParseResult) {
            if let parsed = parsedItem {
                AIParseResultSheet(parsedItem: parsed) { confirmedItem in
                    Task {
                        await addParsedItem(confirmedItem)
                    }
                }
            } else {
                ManualAddItemSheet { item in
                    Task {
                        await addItem(item)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                checkClipboard()
            }
        }
    }
    
    // MARK: - 计算属性
    
    private var filteredItems: [GRDBLolitaItem] {
        if searchKeyword.isEmpty {
            return itemObserver.items
        } else {
            return itemObserver.items.filter {
                $0.rawTitle.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.cleanedName?.localizedCaseInsensitiveContains(searchKeyword) == true
            }
        }
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - 方法
    
    private func initializeGRDB() async {
        do {
            try await GRDBManager.shared.initialize()
            await SyncEngine.shared.configure()
            await SyncEngine.shared.pullFromCloud()
        } catch {
            print("❌ GRDB 初始化失败: \(error)")
        }
    }
    
    private func manualSync() async {
        isSyncing = true
        defer { isSyncing = false }
        await SyncEngine.shared.syncToCloud()
        await SyncEngine.shared.pullFromCloud()
    }
    
    private func addItem(_ item: GRDBLolitaItem) async {
        guard let writer = GRDBManager.shared.writer else { return }
        do {
            try await writer.write { db in
                try item.insert(db)
            }
            print("✅ 添加商品成功: \(item.rawTitle)")
        } catch {
            print("❌ 添加商品失败: \(error)")
        }
    }
    
    private func addParsedItem(_ parsed: ParsedItem) async {
        let item = GRDBLolitaItem(
            platform: parsed.platform,
            platformID: parsed.platformID,
            rawTitle: parsed.title,
            currentPrice: parsed.price
        )
        await addItem(item)
    }
    
    private func checkClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        
        if let parsed = ShareLinkParser.parse(clipboardString) {
            let processedKey = "processed_clipboard_\(parsed.url.hashValue)"
            if UserDefaults.standard.bool(forKey: processedKey) {
                return
            }
            
            UserDefaults.standard.set(true, forKey: processedKey)
            parsedItem = parsed
            showAIParseResult = true
            UIPasteboard.general.string = ""
        }
    }
}

// MARK: - 搜索栏

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("搜索裙装...".appLocalized, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - 价格概览卡片

struct MarketPriceOverviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LO-指数".appLocalized)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // 实时标签
                HStack(spacing: 4) {
                    PulsingDot()
                    Text("实时".appLocalized)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(hex: "E29399"))
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("1,258.36")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                // 涨跌幅
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text("2.35%")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "32CD32"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "32CD32").opacity(0.1))
                .cornerRadius(6)
            }
            
            // 价格区间
            HStack(spacing: 16) {
                MarketPriceRangeItem(title: "最高", value: 1580, color: Color(hex: "32CD32"))
                MarketPriceRangeItem(title: "最低", value: 980, color: Color(hex: "DC143C"))
                MarketPriceRangeItem(title: "中位数", value: 1280, color: Color(hex: "E29399"))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color(hex: "E29399").opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct MarketPriceRangeItem: View {
    let title: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.appLocalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("¥\(String(format: "%.0f", value))")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - K线图卡片

struct MarketKLineChartCard: View {
    @Binding var selectedTimeRange: DressStockMarketView.TimeRange
    
    // 模拟K线数据
    private let mockData: [KLineData] = [
        KLineData(date: Date().addingTimeInterval(-86400 * 6), open: 1200, high: 1250, low: 1180, close: 1230),
        KLineData(date: Date().addingTimeInterval(-86400 * 5), open: 1230, high: 1280, low: 1220, close: 1260),
        KLineData(date: Date().addingTimeInterval(-86400 * 4), open: 1260, high: 1300, low: 1240, close: 1280),
        KLineData(date: Date().addingTimeInterval(-86400 * 3), open: 1280, high: 1320, low: 1260, close: 1250),
        KLineData(date: Date().addingTimeInterval(-86400 * 2), open: 1250, high: 1290, low: 1230, close: 1270),
        KLineData(date: Date().addingTimeInterval(-86400), open: 1270, high: 1310, low: 1250, close: 1300),
        KLineData(date: Date(), open: 1300, high: 1350, low: 1280, close: 1320)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("价格走势".appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(selectedTimeRange.localizedTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "FDF5F6"))
                    .cornerRadius(4)
            }
            
            // K线图（简化版）
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(hex: "E29399"))
                    Text("K线图功能开发中".appLocalized)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(height: 200)
            .background(Color(hex: "FDF5F6"))
            .cornerRadius(12)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color(hex: "E29399").opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct KLineData: Identifiable {
    let id = UUID()
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
}

// MARK: - 时间范围选择器

struct MarketTimeRangeSelector: View {
    @Binding var selection: DressStockMarketView.TimeRange
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(DressStockMarketView.TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selection = range
                    }
                }) {
                    Text(range.localizedTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selection == range ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selection == range ? Color(hex: "E29399") : Color(hex: "FDF5F6")
                        )
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - 市场统计卡片

struct DressMarketStatsCard: View {
    let itemCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("市场统计".appLocalized)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                DressStatBox(
                    title: "挂牌数量",
                    value: "\(itemCount)",
                    icon: "doc.text",
                    color: Color(hex: "E29399")
                )
                
                DressStatBox(
                    title: "萌款数量",
                    value: "42",
                    icon: "heart.fill",
                    color: Color(hex: "D4787F")
                )
                
                DressStatBox(
                    title: "情绪指数",
                    value: "0.68",
                    icon: "face.smiling",
                    color: Color(hex: "A3C1AD")
                )
                
                DressStatBox(
                    title: "价格振幅",
                    value: "12.5%",
                    icon: "arrow.up.arrow.down",
                    color: Color(hex: "FFD700")
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color(hex: "E29399").opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct DressStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            
            Text(title.appLocalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "FDF5F6"))
        .cornerRadius(8)
    }
}

// MARK: - 平台分布卡片

struct DressPlatformDistributionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("平台分布".appLocalized)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                DressPlatformBadge(name: "闲鱼", count: 156, color: .yellow)
                DressPlatformBadge(name: "小红书", count: 89, color: .red)
                DressPlatformBadge(name: "淘宝", count: 234, color: .orange)
                DressPlatformBadge(name: "微店", count: 45, color: .green)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color(hex: "E29399").opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct DressPlatformBadge: View {
    let name: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text("\(name.appLocalized) \(count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(4)
    }
}

// MARK: - AI投资建议卡片

struct DressAIAnalysisCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Color(hex: "E29399"))
                
                Text("AI 投资建议".appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("买入".appLocalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "32CD32"))
                    .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                DressAnalysisRow(title: "好价比例", value: "35%", progress: 0.35)
                DressAnalysisRow(title: "急出比例", value: "20%", progress: 0.20)
                DressAnalysisRow(title: "溢价比例", value: "45%", progress: 0.45)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color(hex: "E29399").opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct DressAnalysisRow: View {
    let title: String
    let value: String
    let progress: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title.appLocalized)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "FDF5F6"))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)), height: 8)
                }
            }
            .frame(height: 8)
            
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 50, alignment: .trailing)
        }
    }
    
    var progressColor: Color {
        if progress < 0.3 {
            return Color(hex: "A3C1AD")
        } else if progress < 0.7 {
            return Color(hex: "FFD700")
        } else {
            return Color(hex: "E29399")
        }
    }
}

// MARK: - 在售商品列表

struct DressActiveListingsSection: View {
    let items: [GRDBLolitaItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("在售商品 (%d)".appLocalized(items.count))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if items.count > 5 {
                    Text("查看全部".appLocalized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "E29399"))
                }
            }
            
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hanger")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(hex: "E29399").opacity(0.5))
                    
                    Text("暂无在售商品".appLocalized)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(items.prefix(5)) { item in
                        DressListingRow(item: item)
                        
                        if item.id != items.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color(hex: "E29399").opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

struct DressListingRow: View {
    let item: GRDBLolitaItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 平台图标
            PlatformIconView(platform: item.platform)
            
            // 商品信息
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(item.platform)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    if item.syncStatus == "synced" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
            
            Spacer()
            
            // 价格
            VStack(alignment: .trailing, spacing: 4) {
                Text("¥\(Int(item.currentPrice))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(priceColor)
                
                // 价格趋势标签
                Text(priceTrendText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(priceTrendColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priceTrendColor.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
    
    var priceColor: Color {
        switch item.priceTrend {
        case "bargain":
            return Color(hex: "32CD32")
        case "premium":
            return Color(hex: "DC143C")
        default:
            return .primary
        }
    }
    
    var priceTrendText: String {
        switch item.priceTrend {
        case "bargain": return "好价".appLocalized
        case "fair": return "合理".appLocalized
        case "premium": return "溢价".appLocalized
        default: return "未知".appLocalized
        }
    }
    
    var priceTrendColor: Color {
        switch item.priceTrend {
        case "bargain": return Color(hex: "32CD32")
        case "fair": return Color(hex: "FFD700")
        case "premium": return Color(hex: "DC143C")
        default: return .gray
        }
    }
}

struct PlatformIconView: View {
    let platform: String
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.2))
                .frame(width: 36, height: 36)
            
            Text(iconText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(backgroundColor)
        }
    }
    
    var iconText: String {
        switch platform.lowercased() {
        case "xianyu", "闲鱼": return "闲"
        case "xiaohongshu", "小红书": return "红"
        case "taobao", "淘宝": return "淘"
        case "weidian", "微店": return "微"
        case "douyin", "抖音": return "抖"
        default: return "?"
        }
    }
    
    var backgroundColor: Color {
        switch platform.lowercased() {
        case "xianyu", "闲鱼": return .yellow
        case "xiaohongshu", "小红书": return .red
        case "taobao", "淘宝": return .orange
        case "weidian", "微店": return .green
        case "douyin", "抖音": return .black
        default: return .gray
        }
    }
}

// MARK: - AI 解析相关

struct ParsedItem {
    let platform: String
    let platformID: String
    let title: String
    let price: Double
    let url: String
    let imageURL: String?
    let sellerName: String?
    let rawContent: String
}

// MARK: - AI 解析结果 Sheet

struct AIParseResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let parsedItem: ParsedItem
    let onConfirm: (ParsedItem) -> Void
    
    @State private var editedTitle: String
    @State private var editedPrice: String
    
    init(parsedItem: ParsedItem, onConfirm: @escaping (ParsedItem) -> Void) {
        self.parsedItem = parsedItem
        self.onConfirm = onConfirm
        _editedTitle = State(initialValue: parsedItem.title)
        _editedPrice = State(initialValue: String(format: "%.2f", parsedItem.price))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("识别结果") {
                    HStack {
                        Text("平台")
                        Spacer()
                        PlatformIconView(platform: parsedItem.platform)
                        Text(platformDisplayName)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("链接")
                        Spacer()
                        Text(parsedItem.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 200, alignment: .trailing)
                    }
                }
                
                Section("商品信息") {
                    TextField("商品标题", text: $editedTitle)
                    TextField("价格", text: $editedPrice)
                        .keyboardType(.decimalPad)
                }
                
                Section("原始内容") {
                    Text(parsedItem.rawContent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("解析分享链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let confirmedItem = ParsedItem(
                            platform: parsedItem.platform,
                            platformID: parsedItem.platformID,
                            title: editedTitle,
                            price: Double(editedPrice) ?? parsedItem.price,
                            url: parsedItem.url,
                            imageURL: parsedItem.imageURL,
                            sellerName: parsedItem.sellerName,
                            rawContent: parsedItem.rawContent
                        )
                        onConfirm(confirmedItem)
                        dismiss()
                    }
                    .disabled(editedTitle.isEmpty)
                }
            }
        }
    }
    
    var platformDisplayName: String {
        switch parsedItem.platform {
        case "xianyu": return "闲鱼"
        case "xiaohongshu": return "小红书"
        case "taobao": return "淘宝"
        case "weidian": return "微店"
        case "douyin": return "抖音"
        default: return parsedItem.platform
        }
    }
}

// MARK: - 手动添加商品 Sheet

struct ManualAddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let onAdd: (GRDBLolitaItem) -> Void
    
    @State private var platform = "xianyu"
    @State private var platformID = ""
    @State private var rawTitle = ""
    @State private var currentPrice = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    Picker("平台", selection: $platform) {
                        Text("闲鱼").tag("xianyu")
                        Text("小红书").tag("xiaohongshu")
                        Text("淘宝").tag("taobao")
                        Text("微店").tag("weidian")
                        Text("抖音").tag("douyin")
                    }
                    
                    TextField("平台商品ID", text: $platformID)
                    TextField("商品标题", text: $rawTitle)
                    TextField("价格", text: $currentPrice)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("添加商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if let price = Double(currentPrice), !rawTitle.isEmpty {
                            let item = GRDBLolitaItem(
                                platform: platform,
                                platformID: platformID.isEmpty ? UUID().uuidString : platformID,
                                rawTitle: rawTitle,
                                currentPrice: price
                            )
                            onAdd(item)
                            dismiss()
                        }
                    }
                    .disabled(rawTitle.isEmpty || currentPrice.isEmpty)
                }
            }
        }
    }
}

// MARK: - 分享链接解析器

enum ShareLinkParser {
    static func parse(_ text: String) -> ParsedItem? {
        if let xianyu = parseXianyuLink(text) { return xianyu }
        if let xiaohongshu = parseXiaohongshuLink(text) { return xiaohongshu }
        if let taobao = parseTaobaoLink(text) { return taobao }
        if let weidian = parseWeidianLink(text) { return weidian }
        if let douyin = parseDouyinLink(text) { return douyin }
        return nil
    }
    
    private static func parseXianyuLink(_ text: String) -> ParsedItem? {
        let patterns = [
            "https://m\\.tb\\.cn/h\\.[a-zA-Z0-9]+",
            "https://2\\.taobao\\.com/item\\.htm\\?id=\\d+",
            "闲鱼.*https?://[^\\s]+",
            "【闲鱼】.*"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let url = (text as NSString).substring(with: match.range)
                return ParsedItem(
                    platform: "xianyu",
                    platformID: extractItemID(from: url) ?? UUID().uuidString,
                    title: extractTitle(from: text) ?? "闲鱼商品",
                    price: extractPrice(from: text) ?? 0,
                    url: url,
                    imageURL: nil,
                    sellerName: nil,
                    rawContent: text
                )
            }
        }
        return nil
    }
    
    private static func parseXiaohongshuLink(_ text: String) -> ParsedItem? {
        let patterns = [
            "https://www\\.xiaohongshu\\.com/explore/\\w+",
            "https://xhslink\\.com/\\w+",
            "小红书.*https?://[^\\s]+",
            "【小红书】.*"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let url = (text as NSString).substring(with: match.range)
                return ParsedItem(
                    platform: "xiaohongshu",
                    platformID: extractItemID(from: url) ?? UUID().uuidString,
                    title: extractTitle(from: text) ?? "小红书商品",
                    price: extractPrice(from: text) ?? 0,
                    url: url,
                    imageURL: nil,
                    sellerName: nil,
                    rawContent: text
                )
            }
        }
        return nil
    }
    
    private static func parseTaobaoLink(_ text: String) -> ParsedItem? {
        let patterns = [
            "https://item\\.taobao\\.com/item\\.htm\\?id=\\d+",
            "https://m\\.tb\\.cn/h\\.[a-zA-Z0-9]+",
            "淘宝.*https?://[^\\s]+",
            "【淘宝】.*"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let url = (text as NSString).substring(with: match.range)
                return ParsedItem(
                    platform: "taobao",
                    platformID: extractItemID(from: url) ?? UUID().uuidString,
                    title: extractTitle(from: text) ?? "淘宝商品",
                    price: extractPrice(from: text) ?? 0,
                    url: url,
                    imageURL: nil,
                    sellerName: nil,
                    rawContent: text
                )
            }
        }
        return nil
    }
    
    private static func parseWeidianLink(_ text: String) -> ParsedItem? {
        let patterns = [
            "https://weidian\\.com/item\\.html\\?itemID=\\d+",
            "https://k\\.weidian\\.com/\\w+",
            "微店.*https?://[^\\s]+",
            "【微店】.*"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let url = (text as NSString).substring(with: match.range)
                return ParsedItem(
                    platform: "weidian",
                    platformID: extractItemID(from: url) ?? UUID().uuidString,
                    title: extractTitle(from: text) ?? "微店商品",
                    price: extractPrice(from: text) ?? 0,
                    url: url,
                    imageURL: nil,
                    sellerName: nil,
                    rawContent: text
                )
            }
        }
        return nil
    }
    
    private static func parseDouyinLink(_ text: String) -> ParsedItem? {
        let patterns = [
            "https://v\\.douyin\\.com/\\w+",
            "https://www\\.douyin\\.com/video/\\d+",
            "抖音.*https?://[^\\s]+",
            "【抖音】.*"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let url = (text as NSString).substring(with: match.range)
                return ParsedItem(
                    platform: "douyin",
                    platformID: extractItemID(from: url) ?? UUID().uuidString,
                    title: extractTitle(from: text) ?? "抖音商品",
                    price: extractPrice(from: text) ?? 0,
                    url: url,
                    imageURL: nil,
                    sellerName: nil,
                    rawContent: text
                )
            }
        }
        return nil
    }
    
    private static func extractItemID(from url: String) -> String? {
        guard let url = URL(string: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        let queryItems = components.queryItems ?? []
        
        if let id = queryItems.first(where: { $0.name == "id" })?.value {
            return id
        }
        if let itemID = queryItems.first(where: { $0.name == "itemID" })?.value {
            return itemID
        }
        
        let path = url.path
        let pathComponents = path.components(separatedBy: "/")
        if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
            return lastComponent
        }
        
        return nil
    }
    
    private static func extractTitle(from text: String) -> String? {
        let patterns = [
            "【([^】]+)】",
            "\\[([^\\]]+)\\]",
            "《([^》]+)》"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let title = (text as NSString).substring(with: match.range(at: 1))
                return title.trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private static func extractPrice(from text: String) -> Double? {
        let patterns = [
            "¥(\\d+(?:\\.\\d+)?)",
            "(\\d+(?:\\.\\d+)?)元",
            "价格[:：]\\s*(\\d+(?:\\.\\d+)?)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let priceString = (text as NSString).substring(with: match.range(at: 1))
                return Double(priceString)
            }
        }
        
        return nil
    }
}

// MARK: - 预览

#Preview {
    DressStockMarketView()
}
