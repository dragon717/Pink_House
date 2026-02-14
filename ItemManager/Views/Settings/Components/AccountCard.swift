import SwiftUI
import AuthenticationServices

struct AccountCard: View {
    @ObservedObject var authManager: AuthenticationManager
    @ObservedObject var cloudManager: CloudSyncManager
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        if authManager.isAuthenticated {
                            // 已登录：显示头像
                            UserAvatarView(
                                givenName: authManager.givenName,
                                familyName: authManager.familyName,
                                size: 40
                            )
                        } else {
                            // 未登录：显示占位图标
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()
                    
                    // 右上角状态标
                    if authManager.isAuthenticated {
                        if cloudManager.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if let error = cloudManager.syncError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        } else {
                            Image(systemName: "icloud.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if authManager.isAuthenticated {
                        Text(authManager.givenName.isEmpty ? "已登录用户" : authManager.givenName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(icloudStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Apple 登录")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text("点击登录以同步数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
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
    
    private var icloudStatusText: String {
        if cloudManager.isSyncing { return "正在同步..." }
        if cloudManager.syncError != nil { return "同步出错" }
        if let date = cloudManager.lastCloudBackupDate {
            return "备份于 " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return "iCloud 就绪"
    }
}
