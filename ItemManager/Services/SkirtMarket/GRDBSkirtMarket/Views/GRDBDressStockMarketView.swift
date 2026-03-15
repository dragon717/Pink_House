//
//  GRDBDressStockMarketView.swift
//  裙装股市 - 使用 GRDB 的主界面
//
//  完全独立于 SwiftData，使用 GRDB + CloudKit 架构
//

import SwiftUI
import GRDB

/// 使用 GRDB 的裙装股市主界面
struct GRDBDressStockMarketView: View {
    // MARK: - 状态
    
    /// 使用 GRDBObserver 替代 @Query
    @StateObject private var itemObserver = GRDBLolitaItemObserver()
    
    /// 选中的标签页
    @State private var selectedTab = 0
    
    /// 是否显示添加商品表单
    @State private var showAddItemSheet = false
    
    /// 同步状态
    @State private var isSyncing = false
    
    // MARK: - 视图
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 同步状态栏
                SyncStatusBar(isSyncing: isSyncing)
                
                // 标签页切换
                Picker("视图", selection: $selectedTab) {
                    Text("商品列表").tag(0)
                    Text("市场指数").tag(1)
                    Text("节点监控").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // 内容区域
                TabView(selection: $selectedTab) {
                    // 商品列表
                    ItemListView(items: itemObserver.items, isLoading: itemObserver.isLoading)
                        .tag(0)
                    
                    // 市场指数（待实现）
                    Text("市场指数视图")
                        .tag(1)
                    
                    // 节点监控（待实现）
                    Text("节点监控视图")
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("裙装股市")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddItemSheet = true }) {
                        Image(systemName: "plus")
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
            // 启动观察
            itemObserver.startObservingActive()
            
            // 初始化 GRDB
            Task {
                await initializeGRDB()
            }
        }
        .onDisappear {
            // 停止观察
            itemObserver.stopObserving()
        }
        .sheet(isPresented: $showAddItemSheet) {
            AddItemView { item in
                Task {
                    await addItem(item)
                }
            }
        }
    }
    
    // MARK: - 方法
    
    /// 初始化 GRDB
    private func initializeGRDB() async {
        do {
            try await GRDBManager.shared.initialize()
            
            // 配置同步引擎
            await SyncEngine.shared.configure()
            
            // 从云端拉取数据
            await SyncEngine.shared.pullFromCloud()
            
        } catch {
            print("❌ GRDB 初始化失败: \(error)")
        }
    }
    
    /// 手动同步
    private func manualSync() async {
        isSyncing = true
        defer { isSyncing = false }
        
        await SyncEngine.shared.syncToCloud()
        await SyncEngine.shared.pullFromCloud()
    }
    
    /// 添加商品
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
}

// MARK: - 子视图

/// 同步状态栏
struct SyncStatusBar: View {
    let isSyncing: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isSyncing ? "arrow.clockwise" : "checkmark.circle.fill")
                .foregroundStyle(isSyncing ? .blue : .green)
            
            Text(isSyncing ? "正在同步..." : "已同步")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

/// 商品列表视图
struct ItemListView: View {
    let items: [GRDBLolitaItem]
    let isLoading: Bool
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
            } else if items.isEmpty {
                ContentUnavailableView(
                    "暂无商品",
                    systemImage: "tag.slash",
                    description: Text("点击右上角 + 添加商品")
                )
            } else {
                List(items) { item in
                    ItemRowView(item: item)
                }
            }
        }
    }
}

/// 商品行视图
struct ItemRowView: View {
    let item: GRDBLolitaItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
                .font(.headline)
                .lineLimit(2)
            
            HStack {
                Text("¥\(Int(item.currentPrice))")
                    .font(.subheadline)
                    .foregroundStyle(.pink)
                
                Spacer()
                
                Text(item.platform)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                if item.syncStatus == "synced" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 添加商品视图
struct AddItemView: View {
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

// MARK: - 预览

#Preview {
    GRDBDressStockMarketView()
}
