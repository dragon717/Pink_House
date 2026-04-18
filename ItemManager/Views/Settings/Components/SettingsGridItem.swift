import SwiftUI

struct SettingsGridItem: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    var iconSystemName: Bool = true // 是否是 SF Symbol

    private var isGirlClosetThemed: Bool {
        guard let descriptor = themeSkinManager.activeThemeDescriptor(for: .settingsGridCard, state: .default) else {
            return false
        }
        return descriptor.assetNamespace == "girl_closet"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if iconSystemName {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                        .frame(width: 40, height: 40)
                        .background(iconCircleBackground)
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
        .overlay(alignment: .topTrailing) {
            if isGirlClosetThemed {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "D17A9A"))
                    .padding(8)
            }
        }
        .shadow(color: isGirlClosetThemed ? Color(hex: "E5B5C7").opacity(0.22) : .clear, radius: 12, x: 0, y: 6)
    }

    private var iconCircleBackground: some View {
        Group {
            if isGirlClosetThemed {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "E7C7D3").opacity(0.95), lineWidth: 1)
                    )
            } else if iconSystemName {
                iconColor.opacity(0.1)
            } else {
                Color.gray.opacity(0.1)
            }
        }
    }
    
    // MARK: - 卡片背景（适配主题色）
    private var cardBackground: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return Group {
            if isGirlClosetThemed {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "FFFDF8"),
                                Color(hex: "FCEEF3")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(hex: "E5B5C7").opacity(0.18), radius: 10, x: 0, y: 5)
            } else {
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
    }
    
    // MARK: - 卡片边框（适配主题色）
    private var cardOverlay: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return RoundedRectangle(cornerRadius: 20)
            .stroke(
                isGirlClosetThemed
                    ? LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color(hex: "E7C7D3").opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [cardColors.accentRGBA.color.opacity(isDark ? 0.3 : 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                lineWidth: 1
            )
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
