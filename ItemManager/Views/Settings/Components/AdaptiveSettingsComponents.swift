import SwiftUI

// MARK: - 自适应设置容器
struct AdaptiveSettingsView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 600
            
            ScrollView {
                if isWide {
                    // 宽屏模式：双列网格 (豆腐块)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)], spacing: 16) {
                        content
                    }
                    .padding()
                } else {
                    // 竖屏模式：单列堆叠
                    VStack(spacing: 24) {
                        content
                    }
                    .padding()
                }
            }
            // 底部悬浮 Dock 避让：口径收口到 `avoidingBottomDock()`（唯一实现）。
            // 旧实现在 iOS 26+ 直接 return 0，导致这批设置页在新系统上最后一个元素被 Dock 盖住。
            .avoidingBottomDock()
            .background(LiquidBackground())
            .navigationTitle(title.appLocalized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 自适应分组 (替代 Section)
struct AdaptiveSection<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    let header: String?
    let footer: String?
    @ViewBuilder let content: Content
    
    init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }
    
    // 支持 Text 类型的 header/footer (为了兼容性)
    init(header: Text?, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        // 提取 Text 中的字符串有点困难，这里简化处理，要求传入 String
        // 实际重构时我们将修改调用处
        self.header = nil 
        self.footer = nil
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header.appLocalized.uppercased(with: LanguageManager.shared.locale))
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .padding(.leading, 8)
            }
            
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity) // 确保卡片撑满宽度
            .background(sectionBackground)
            .cornerRadius(12)
            // 添加边框或阴影以增强豆腐块质感
            .overlay(sectionOverlay)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            
            if let footer {
                Text(footer.appLocalized)
                    .font(.caption2)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .padding(.leading, 8)
                    .fixedSize(horizontal: false, vertical: true) // 允许换行
            }
        }
    }
    
    // MARK: - 分组背景（适配主题色）
    private var sectionBackground: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)

        return Group {
            switch themeManager.cardStyle {
            case .solid:
                cardColors.backgroundRGBA.color
            case .transparent:
                // 使用高斯模糊材质，类似 VIP 卡片样式
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(cardColors.backgroundRGBA.color.opacity(themeManager.transparentOpacity * 0.5))
            case .fullyTransparent:
                // 完全透明时使用高斯模糊
                Rectangle()
                    .fill(.ultraThinMaterial)
            case .tinted:
                // 色调模式：使用高斯模糊材质叠加主题卡片背景色
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(cardColors.backgroundRGBA.color.opacity(themeManager.tintOpacity))
            }
        }
    }
    
    // MARK: - 分组边框（适配主题色，类似 VIP 卡片样式）
    private var sectionOverlay: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        // 根据卡片样式调整边框透明度
        let strokeOpacity: Double = {
            switch themeManager.cardStyle {
            case .solid:
                return isDark ? 0.3 : 0.2
            case .transparent, .fullyTransparent, .tinted:
                // 高斯模糊模式下使用更明显的边框，类似 VIP 卡片
                return isDark ? 0.4 : 0.3
            }
        }()
        
        return RoundedRectangle(cornerRadius: 12)
            .stroke(cardColors.accentRGBA.color.opacity(strokeOpacity), lineWidth: 1)
    }
}

// MARK: - 自定义行修饰符
// 用于在 AdaptiveSection 内部模拟 List Row 的分割线
struct AdaptiveRow<Content: View>: View {
    let content: Content
    var showDivider: Bool
    
    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading) // 确保内容撑满整行
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle()) // 扩大点击区域
            
            if showDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

// 扩展 View 以便更方便地使用
extension View {
    func adaptiveRow(showDivider: Bool = true) -> some View {
        AdaptiveRow(showDivider: showDivider) {
            self
        }
    }
}
