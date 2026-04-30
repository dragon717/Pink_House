import SwiftUI
import SwiftData

/// iCloud 同步状态视图
struct iCloudSyncStatusView: View {
    @State private var syncManager = iCloudSyncManager.shared
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails.toggle() }) {
            HStack(spacing: 6) {
                syncIcon
                if case .migrating(let progress) = syncManager.syncStatus {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 40)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            SyncDetailsView()
        }
    }
    
    @ViewBuilder
    private var syncIcon: some View {
        switch syncManager.syncStatus {
        case .notStarted:
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
        case .migrating:
            if #available(iOS 18.0, *) {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce)
            } else {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.blue)
            }
        case .syncing:
            if #available(iOS 18.0, *) {
                Image(systemName: "arrow.clockwise.icloud")
                    .foregroundStyle(.blue)
                    .symbolEffect(.rotate)
            } else {
                LegacyRotatingSyncIcon()
            }
        case .synced:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.red)
        case .offline:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LegacyRotatingSyncIcon: View {
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.clockwise.icloud")
            .foregroundStyle(.blue)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                rotation = 0
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            .onDisappear {
                rotation = 0
            }
    }
}

/// 同步详情视图
struct SyncDetailsView: View {
    @State private var syncManager = iCloudSyncManager.shared
    @Environment(\.dismiss) private var dismiss

    private var isSyncingOrMigrating: Bool {
        if case .migrating = syncManager.syncStatus {
            return true
        }
        return syncManager.syncStatus == .syncing
    }

    var body: some View {
        NavigationStack {
            List {
                Section("同步状态") {
                    HStack {
                        Label("状态", systemImage: statusIcon)
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }
                    
                    if case .migrating(let progress) = syncManager.syncStatus {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("数据迁移中...")
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let lastSync = syncManager.lastSyncTime {
                        HStack {
                            Label("上次同步", systemImage: "clock")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("操作") {
                    Button(action: {
                        Task {
                            await syncManager.triggerSync()
                        }
                    }) {
                        Label("立即同步", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSyncingOrMigrating)
                    
                    if syncManager.isMigrationCompleted {
                        HStack {
                            Label("数据迁移", systemImage: "checkmark.circle")
                            Spacer()
                            Text("已完成")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button(action: {
                            Task {
                                await syncManager.performMigration()
                            }
                        }) {
                            Label("重新迁移数据", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
                
                Section("说明") {
                    Text("iCloud 同步可以将您的数据自动备份到云端，并在您的所有设备之间同步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iCloud 同步")
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
    
    private var statusIcon: String {
        switch syncManager.syncStatus {
        case .notStarted: return "icloud"
        case .migrating: return "icloud.and.arrow.up"
        case .syncing: return "arrow.clockwise.icloud"
        case .synced: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        case .offline: return "icloud.slash"
        }
    }
    
    private var statusText: String {
        switch syncManager.syncStatus {
        case .notStarted: return "未开始"
        case .migrating: return "迁移中"
        case .syncing: return "同步中"
        case .synced: return "已同步"
        case .failed: return "失败"
        case .offline: return "离线"
        }
    }
    
    private var statusColor: Color {
        switch syncManager.syncStatus {
        case .notStarted, .offline: return .secondary
        case .migrating, .syncing: return .blue
        case .synced: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    iCloudSyncStatusView()
}
