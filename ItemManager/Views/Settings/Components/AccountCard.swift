import SwiftUI
import AuthenticationServices

struct AccountCard: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var authManager: AuthenticationManager
    @ObservedObject var cloudManager: CloudSyncManager
    let action: () -> Void
    @State private var showingProfileEdit = false
    
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
                                customAvatarPath: authManager.customAvatarPath,
                                size: 40
                            )
                        } else {
                            // 未登录：显示占位图标
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title2)
                                .foregroundStyle(themeManager.primaryTextColor)
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
                                .foregroundStyle(themeManager.accentTextColor)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if authManager.isAuthenticated {
                        Text(authManager.displayName)
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                            .lineLimit(1)
                        
                        Text(icloudStatusText)
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Apple 登录")
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                            .lineLimit(1)
                        
                        Text("点击登录以同步数据")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .background(cardBackground)
            .overlay(cardOverlay)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingProfileEdit) {
            UserProfileEditView(authManager: authManager)
        }
    }
    
    // MARK: - 卡片背景（适配主题色）
    private var cardBackground: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return Group {
            switch themeManager.cardStyle {
            case .solid:
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .transparent:
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color.opacity(themeManager.transparentOpacity))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .fullyTransparent:
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color.opacity(0.3))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .tinted:
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(cardColors.backgroundRGBA.color.opacity(themeManager.tintOpacity))
                    )
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - 卡片边框（适配主题色）
    private var cardOverlay: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return RoundedRectangle(cornerRadius: 20)
            .stroke(cardColors.accentRGBA.color.opacity(isDark ? 0.3 : 0.2), lineWidth: 1)
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
