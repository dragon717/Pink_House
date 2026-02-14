import SwiftUI

struct iCloudStatusCard: View {
    @ObservedObject var cloudManager: CloudSyncManager
    @ObservedObject var authManager: AuthenticationManager
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        if cloudManager.isSyncing {
                            ProgressView()
                                .tint(.blue)
                        } else {
                            Image(systemName: "icloud.fill")
                                .font(.title2)
                                .foregroundStyle(iconColor)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.1))
                    .clipShape(Circle())
                    
                    Spacer()
                    
                    if let error = cloudManager.syncError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    } else if cloudManager.lastCloudBackupDate != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud 同步")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconColor: Color {
        if !authManager.isAuthenticated { return .gray }
        if cloudManager.syncError != nil { return .red }
        return .blue
    }
    
    private var statusText: String {
        if !authManager.isAuthenticated {
            return "未登录"
        }
        if cloudManager.isSyncing {
            return "正在同步..."
        }
        if let error = cloudManager.syncError {
            return "同步出错"
        }
        if let lastDate = cloudManager.lastCloudBackupDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.locale = Locale(identifier: "zh_CN")
            return "备份于 " + formatter.localizedString(for: lastDate, relativeTo: Date())
        }
        return "准备就绪"
    }
}
