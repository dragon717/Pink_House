//
//  ImageSyncStatusIndicator.swift
//  ItemManager
//
//  图片同步状态指示器组件
//

import SwiftUI
import SwiftData

/// 图片同步状态指示器
/// 显示裙子主图的 CloudKit 同步状态
struct ImageSyncStatusIndicator: View {
    let imageFileName: String
    
    @State private var syncStatus: String?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let status = syncStatus {
                switch status {
                case "synced":
                    syncedIcon
                case "pending":
                    pendingIcon
                case "failed":
                    failedIcon
                default:
                    EmptyView()
                }
            }
        }
        .task {
            await checkSyncStatus()
        }
        .onChange(of: imageFileName) { _, _ in
            Task {
                await checkSyncStatus()
            }
        }
    }
    
    // MARK: - 状态图标
    
    private var syncedIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.caption)
            .help("图片已同步到 iCloud")
    }
    
    private var pendingIcon: some View {
        Image(systemName: "arrow.up.circle")
            .foregroundColor(.orange)
            .font(.caption)
            .help("图片等待同步")
    }
    
    private var failedIcon: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundColor(.red)
            .font(.caption)
            .help("图片同步失败，点击重试")
            .onTapGesture {
                Task {
                    await retrySync()
                }
            }
    }
    
    // MARK: - 状态检查
    
    private func checkSyncStatus() async {
        let context = ModelContext(SharedContainer.sharedModelContainer)
        syncStatus = ClothingImageSyncService.shared.getSyncStatus(
            imageFileName: imageFileName,
            context: context
        )
    }
    
    private func retrySync() async {
        isLoading = true
        await ClothingImageSyncService.shared.syncPendingImages()
        await checkSyncStatus()
        isLoading = false
    }
}

/// 全局同步状态指示器
/// 显示整体同步状态和待同步数量
struct GlobalImageSyncIndicator: View {
    @StateObject private var syncService = ClothingImageSyncService.shared
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails = true }) {
            HStack(spacing: 4) {
                syncIcon
                if syncService.pendingUploadCount > 0 {
                    Text("\(syncService.pendingUploadCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            SyncStatusDetailView()
        }
    }
    
    private var syncIcon: some View {
        switch syncService.syncStatus {
        case .idle, .completed:
            return Image(systemName: "checkmark.icloud")
                .foregroundColor(.green)
        case .syncing, .uploading, .downloading:
            return Image(systemName: "arrow.clockwise.icloud")
                .foregroundColor(.blue)
        case .failed:
            return Image(systemName: "exclamationmark.icloud")
                .foregroundColor(.red)
        }
    }
}

/// 同步状态详情视图
struct SyncStatusDetailView: View {
    @StateObject private var syncService = ClothingImageSyncService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("同步状态") {
                    HStack {
                        Text("CloudKit 状态")
                        Spacer()
                        Text(syncService.isCloudKitAvailable ? "可用" : "不可用")
                            .foregroundColor(syncService.isCloudKitAvailable ? .green : .red)
                    }
                    
                    HStack {
                        Text("当前状态")
                        Spacer()
                        statusText
                    }
                    
                    if let lastSync = syncService.lastSyncDate {
                        HStack {
                            Text("上次同步")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("待同步图片")
                        Spacer()
                        Text("\(syncService.pendingUploadCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("操作") {
                    Button("立即同步") {
                        Task {
                            await syncService.syncPendingImages()
                        }
                    }
                    .disabled(!syncService.isCloudKitAvailable)
                    
                    Button("检查 CloudKit 状态") {
                        Task {
                            await syncService.checkCloudKitAvailability()
                        }
                    }
                }
            }
            .navigationTitle("图片同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var statusText: some View {
        switch syncService.syncStatus {
        case .idle:
            return Text("空闲").foregroundColor(.secondary)
        case .uploading(let name, let progress):
            return Text("上传中: \(Int(progress * 100))%").foregroundColor(.blue)
        case .downloading(let name, let progress):
            return Text("下载中: \(Int(progress * 100))%").foregroundColor(.blue)
        case .syncing:
            return Text("同步中...").foregroundColor(.blue)
        case .completed:
            return Text("完成").foregroundColor(.green)
        case .failed:
            return Text("失败").foregroundColor(.red)
        }
    }
}

// MARK: - 预览
#Preview {
    VStack(spacing: 20) {
        HStack {
            Text("已同步图片")
            Spacer()
            ImageSyncStatusIndicator(imageFileName: "test.jpg")
        }
        
        GlobalImageSyncIndicator()
    }
    .padding()
}
