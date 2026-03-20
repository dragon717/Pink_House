import SwiftUI

struct SettingsGridItem: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    var iconSystemName: Bool = true // 是否是 SF Symbol
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if iconSystemName {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                        .frame(width: 40, height: 40)
                        .background(iconColor.opacity(0.1))
                        .clipShape(Circle())
                } else {
                    Text(icon)
                        .font(.title)
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.0, contentMode: .fill) // 1:1 宽高比
        .background(cardBackground)
        .overlay(cardOverlay)
    }
    
    // MARK: - 卡片背景（适配主题色）
    private var cardBackground: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return Group {
            switch themeManager.cardStyle {
            case .solid:
                // 实色：使用主题卡片背景色
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                
            case .transparent:
                // 半透明：使用主题卡片背景色 + 透明度
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color.opacity(themeManager.transparentOpacity))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                
            case .fullyTransparent:
                // 全透明：使用主题卡片背景色 + 低透明度
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color.opacity(0.3))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                
            case .tinted:
                // 色调：使用主题卡片背景色作为色调
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
}

#Preview {
    ZStack {
        Color.pink.opacity(0.1).ignoresSafeArea()
        HStack {
            SettingsGridItem(
                title: "梦幻衣橱",
                subtitle: "外观 · 隐私 · 提醒",
                icon: "tshirt",
                iconColor: .pink
            )
            SettingsGridItem(
                title: "智能萌宠",
                subtitle: "AI 大脑 · 语音 · 形象",
                icon: "pawprint.fill",
                iconColor: .purple
            )
        }
        .padding()
    }
}
