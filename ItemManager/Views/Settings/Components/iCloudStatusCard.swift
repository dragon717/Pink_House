import SwiftUI

struct iCloudStatusCard: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
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
                        .foregroundStyle(themeManager.primaryTextColor)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .background(cardBackground)
            .overlay(cardOverlay)
        }
        .buttonStyle(PlainButtonStyle())
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
