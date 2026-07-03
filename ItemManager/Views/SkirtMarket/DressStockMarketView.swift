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
    @State private var showImportSheet = false
    @State private var importMode: SkirtMarketDeepSeekImportMode = .link
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
                    Menu {
                        Button {
                            openImportSheet(mode: .link)
                        } label: {
                            Label("粘贴链接/文本", systemImage: "doc.on.clipboard")
                        }

                        Button {
                            openImportSheet(mode: .keyword)
                        } label: {
                            Label("关键词模式", systemImage: "magnifyingglass")
                        }
                    } label: {
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
            Task {
                await initializeGRDB()
                itemObserver.startObservingActive()
            }
        }
        .onDisappear {
            itemObserver.stopObserving()
        }
        .sheet(isPresented: $showImportSheet) {
            SkirtMarketDeepSeekImportSheet(initialMode: importMode) { confirmedItem in
                Task {
                    await addParsedItem(confirmedItem)
                }
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
    
    // MARK: - 方法

    private func openImportSheet(mode: SkirtMarketDeepSeekImportMode) {
        importMode = mode
        showImportSheet = true
    }
    
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
        let item = parsed.makeGRDBItem()
        let events = parsed.priceEvents()
        guard let writer = GRDBManager.shared.writer else { return }

        do {
            try await writer.write { db in
                if var existing = try GRDBLolitaItem.fetchByPlatformID(db, platformID: item.platformID) {
                    existing.rawTitle = item.rawTitle
                    existing.cleanedName = item.cleanedName
                    existing.brand = item.brand
                    existing.currentPrice = item.currentPrice
                    existing.priceTrend = item.priceTrend
                    existing.sourceURL = item.sourceURL
                    existing.originalPrice = item.originalPrice
                    existing.depositPrice = item.depositPrice
                    existing.balancePrice = item.balancePrice
                    existing.depositDate = item.depositDate
                    existing.finalPaymentDate = item.finalPaymentDate
                    existing.analysisCapturedAt = item.analysisCapturedAt
                    existing.analysisConfidence = item.analysisConfidence
                    existing.rawAnalysisJSON = item.rawAnalysisJSON
                    existing.lastUpdated = Date()
                    existing.modifiedAt = Date()
                    existing.syncStatus = "pending"
                    try existing.update(db)
                } else {
                    try item.insert(db)
                }

                for event in events {
                    try event.insert(db)
                }
            }
            print("✅ 添加解析商品成功: \(item.rawTitle)")
        } catch {
            print("❌ 添加解析商品失败: \(error)")
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

struct ParsedItem: Identifiable {
    var id = UUID()
    var platform: String
    var platformID: String
    var title: String
    var currentPriceText: String
    var originalPriceText: String
    var depositPriceText: String
    var balancePriceText: String
    var depositDateText: String
    var finalPaymentDateText: String
    var url: String
    var rawContent: String
    var brand: String?
    var series: String?
    var category: String?
    var color: String?
    var size: String?
    var condition: String?
    var isLolitaRelated: Bool
    var saleIntent: String?
    var confidence: Double?
    var missingFields: [String]
    var rawAnalysisJSON: String?
    var capturedAt: Date

    var currentPrice: Double { Double(currentPriceText) ?? 0 }
    var originalPrice: Double? { Double(originalPriceText) }
    var depositPrice: Double? { Double(depositPriceText) }
    var balancePrice: Double? { Double(balancePriceText) }
    var depositDate: Date? { SkirtMarketImportParser.parseDate(depositDateText) }
    var finalPaymentDate: Date? { SkirtMarketImportParser.parseDate(finalPaymentDateText) }

    var priceTrend: String {
        guard let originalPrice, originalPrice > 0, currentPrice > 0 else { return "unknown" }
        let ratio = currentPrice / originalPrice
        if ratio < 0.7 { return "bargain" }
        if ratio > 1.3 { return "premium" }
        return "fair"
    }

    func priceEvents() -> [GRDBLolitaPriceEvent] {
        let source = rawAnalysisJSON == nil ? "local" : "deepseek"
        let observedAt = capturedAt
        var events: [GRDBLolitaPriceEvent] = []

        func append(kind: String, amount: Double?, appliesAt: Date? = nil) {
            guard let amount, amount > 0 else { return }
            events.append(
                GRDBLolitaPriceEvent(
                    platformID: platformID,
                    kind: kind,
                    amount: amount,
                    observedAt: observedAt,
                    appliesAt: appliesAt,
                    source: source
                )
            )
        }

        append(kind: "current", amount: currentPrice)
        append(kind: "original", amount: originalPrice)
        append(kind: "deposit", amount: depositPrice, appliesAt: depositDate)
        append(kind: "balance", amount: balancePrice, appliesAt: finalPaymentDate)
        return events
    }

    func makeGRDBItem() -> GRDBLolitaItem {
        GRDBLolitaItem(
            platform: platform,
            platformID: platformID,
            rawTitle: title,
            cleanedName: series?.isEmpty == false ? series : nil,
            brand: brand?.isEmpty == false ? brand : nil,
            currentPrice: currentPrice,
            priceTrend: priceTrend,
            sourceURL: url.isEmpty ? nil : url,
            originalPrice: originalPrice,
            depositPrice: depositPrice,
            balancePrice: balancePrice,
            depositDate: depositDate,
            finalPaymentDate: finalPaymentDate,
            analysisCapturedAt: capturedAt,
            analysisConfidence: confidence,
            rawAnalysisJSON: rawAnalysisJSON
        )
    }

    static func fallback(from local: SkirtMarketImportLocalParse, rawText: String, capturedAt: Date) -> ParsedItem {
        let platform = local.platformHint
        let price = local.price.map { Self.priceString($0) } ?? ""
        return ParsedItem(
            platform: platform,
            platformID: SkirtMarketImportParser.platformID(platform: platform, sourceURL: local.sourceURL),
            title: local.title ?? "待确认商品",
            currentPriceText: price,
            originalPriceText: "",
            depositPriceText: "",
            balancePriceText: "",
            depositDateText: "",
            finalPaymentDateText: "",
            url: local.sourceURL ?? "",
            rawContent: rawText,
            brand: nil,
            series: nil,
            category: nil,
            color: nil,
            size: nil,
            condition: nil,
            isLolitaRelated: true,
            saleIntent: "unknown",
            confidence: nil,
            missingFields: ["deepseek"],
            rawAnalysisJSON: nil,
            capturedAt: capturedAt
        )
    }

    static func fromAI(
        _ item: SkirtMarketDeepSeekItem,
        local: SkirtMarketImportLocalParse,
        rawText: String,
        rawJSON: String,
        capturedAt: Date
    ) -> ParsedItem {
        let platform = local.platformHint
        let events = item.priceEvents
        let current = events.first(where: { $0.kind == "current" })?.amount ?? local.price
        let original = events.first(where: { $0.kind == "original" })?.amount
        let deposit = events.first(where: { $0.kind == "deposit" })?.amount
        let balance = events.first(where: { $0.kind == "balance" })?.amount
        let depositDate = events.first(where: { $0.kind == "deposit" })?.appliesAt
        let balanceDate = events.first(where: { $0.kind == "balance" })?.appliesAt

        return ParsedItem(
            platform: platform,
            platformID: SkirtMarketImportParser.platformID(platform: platform, sourceURL: local.sourceURL),
            title: item.title.isEmpty ? (local.title ?? "待确认商品") : item.title,
            currentPriceText: current.map(priceString) ?? "",
            originalPriceText: original.map(priceString) ?? "",
            depositPriceText: deposit.map(priceString) ?? "",
            balancePriceText: balance.map(priceString) ?? "",
            depositDateText: normalizedDateString(depositDate),
            finalPaymentDateText: normalizedDateString(balanceDate),
            url: local.sourceURL ?? "",
            rawContent: rawText,
            brand: item.brand,
            series: item.series,
            category: item.category,
            color: item.color,
            size: item.size,
            condition: item.condition,
            isLolitaRelated: item.isLolitaRelated,
            saleIntent: item.saleIntent,
            confidence: item.confidence,
            missingFields: item.missingFields,
            rawAnalysisJSON: rawJSON,
            capturedAt: capturedAt
        )
    }

    private static func normalizedDateString(_ value: String?) -> String {
        guard let date = SkirtMarketImportParser.parseDate(value) else { return value ?? "" }
        return SkirtMarketImportParser.dateString(from: date)
    }

    nonisolated private static func priceString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct SkirtMarketDeepSeekImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let onConfirm: (ParsedItem) -> Void

    @State private var mode: SkirtMarketDeepSeekImportMode
    @State private var linkText = ""
    @State private var keyword = ""
    @State private var keywordResultText = ""
    @State private var drafts: [ParsedItem] = []
    @State private var selectedDraftIndex = 0
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    init(initialMode: SkirtMarketDeepSeekImportMode, onConfirm: @escaping (ParsedItem) -> Void) {
        self.onConfirm = onConfirm
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .wardrobe)
                    .ignoresSafeArea()

                Form {
                    Section {
                        Picker("模式", selection: $mode) {
                            ForEach(SkirtMarketDeepSeekImportMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if mode == .link {
                        linkInputSection
                    } else {
                        keywordInputSection
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if !drafts.isEmpty {
                        resultSection
                        editSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("DeepSeek 商品解析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("添加为裙装") {
                        onConfirm(selectedDraft)
                        dismiss()
                    }
                    .disabled(drafts.isEmpty || selectedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                analyzeButton
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .tint(magicPalette.accent)
        }
    }

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    @ViewBuilder
    private var analyzeButton: some View {
        let button = Button {
            Task { await analyze() }
        } label: {
            HStack {
                if isAnalyzing {
                    ProgressView()
                }
                Text(isAnalyzing ? "分析中..." : "DeepSeek 分析")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .disabled(isAnalyzing || activeRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var linkInputSection: some View {
        Section("链接/粘贴文本") {
            TextEditor(text: $linkText)
                .frame(minHeight: 120)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            PasteButton(payloadType: String.self) { values in
                linkText = values.first ?? linkText
            }
        }
    }

    private var keywordInputSection: some View {
        Group {
            Section("关键词") {
                TextField("例如 AP 辉夜姬 黑色 JSK", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("商品/搜索结果文本") {
                TextEditor(text: $keywordResultText)
                    .frame(minHeight: 100)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                PasteButton(payloadType: String.self) { values in
                    keywordResultText = values.first ?? keywordResultText
                }
            }
        }
    }

    private var resultSection: some View {
        Section("识别结果") {
            if drafts.count > 1 {
                Picker("商品", selection: $selectedDraftIndex) {
                    ForEach(drafts.indices, id: \.self) { index in
                        Text(drafts[index].title).tag(index)
                    }
                }
            }

            HStack {
                Text("平台")
                Spacer()
                PlatformIconView(platform: selectedDraft.platform)
                Text(platformDisplayName(selectedDraft.platform))
                    .foregroundStyle(.secondary)
            }

            if let confidence = selectedDraft.confidence {
                HStack {
                    Text("置信度")
                    Spacer()
                    Text(String(format: "%.0f%%", confidence * 100))
                        .foregroundStyle(.secondary)
                }
            }

            if !selectedDraft.missingFields.isEmpty {
                Text("缺失：\(selectedDraft.missingFields.joined(separator: "、"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editSection: some View {
        Section("保存前确认") {
            TextField("商品标题", text: selectedDraftBinding.title)
            TextField("品牌", text: optionalBinding(\.brand))
            TextField("系列/款名", text: optionalBinding(\.series))
            TextField("分类", text: optionalBinding(\.category))
            TextField("颜色", text: optionalBinding(\.color))
            TextField("尺码", text: optionalBinding(\.size))
            TextField("成色", text: optionalBinding(\.condition))
            TextField("当前价", text: selectedDraftBinding.currentPriceText)
                .keyboardType(.decimalPad)
            TextField("原价", text: selectedDraftBinding.originalPriceText)
                .keyboardType(.decimalPad)
            TextField("定金", text: selectedDraftBinding.depositPriceText)
                .keyboardType(.decimalPad)
            TextField("尾款", text: selectedDraftBinding.balancePriceText)
                .keyboardType(.decimalPad)
            TextField("定金日期 yyyy-MM-dd", text: selectedDraftBinding.depositDateText)
            TextField("尾款日期 yyyy-MM-dd", text: selectedDraftBinding.finalPaymentDateText)

            if !selectedDraft.url.isEmpty {
                Link("打开原链接", destination: URL(string: selectedDraft.url) ?? URL(string: "https://example.com")!)
            }
        }
    }

    private var activeRawText: String {
        switch mode {
        case .link:
            return linkText
        case .keyword:
            return [keyword, keywordResultText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        }
    }

    private var selectedDraft: ParsedItem {
        guard drafts.indices.contains(selectedDraftIndex) else {
            return ParsedItem.fallback(
                from: SkirtMarketImportParser.localParse(activeRawText),
                rawText: activeRawText,
                capturedAt: Date()
            )
        }
        return drafts[selectedDraftIndex]
    }

    private var selectedDraftBinding: Binding<ParsedItem> {
        Binding(
            get: { selectedDraft },
            set: { newValue in
                guard drafts.indices.contains(selectedDraftIndex) else { return }
                drafts[selectedDraftIndex] = newValue
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<ParsedItem, String?>) -> Binding<String> {
        Binding(
            get: { selectedDraft[keyPath: keyPath] ?? "" },
            set: { newValue in
                var draft = selectedDraft
                draft[keyPath: keyPath] = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
                if drafts.indices.contains(selectedDraftIndex) {
                    drafts[selectedDraftIndex] = draft
                }
            }
        )
    }

    private func analyze() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        let rawText = activeRawText
        let capturedAt = Date()
        let local = SkirtMarketImportParser.localParse(rawText)
        let input = SkirtMarketDeepSeekInput(
            mode: mode.rawValue,
            platformHint: local.platformHint,
            sourceURL: local.sourceURL,
            keyword: mode == .keyword ? keyword : nil,
            capturedAt: SkirtMarketImportParser.isoString(from: capturedAt),
            rawText: rawText,
            localParse: local
        )

        do {
            let result = try await SkirtMarketDeepSeekImportService.shared.analyze(input: input)
            drafts = result.items.map {
                ParsedItem.fromAI($0, local: local, rawText: rawText, rawJSON: result.rawJSON, capturedAt: capturedAt)
            }
            if drafts.isEmpty {
                drafts = [ParsedItem.fallback(from: local, rawText: rawText, capturedAt: capturedAt)]
                errorMessage = "DeepSeek 未返回商品，已生成本地草稿。"
            }
            selectedDraftIndex = 0
        } catch {
            drafts = [ParsedItem.fallback(from: local, rawText: rawText, capturedAt: capturedAt)]
            selectedDraftIndex = 0
            errorMessage = error.localizedDescription
        }
    }

    private func platformDisplayName(_ platform: String) -> String {
        switch platform {
        case "xianyu": return "闲鱼"
        case "xiaohongshu": return "小红书"
        case "taobao": return "淘宝"
        case "weidian": return "微店"
        default: return platform
        }
    }
}

// MARK: - 预览

#Preview {
    DressStockMarketView()
}
