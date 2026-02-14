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
            .background(LiquidBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 自适应分组 (替代 Section)
struct AdaptiveSection<Content: View>: View {
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
                Text(header.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            
            VStack(spacing: 0) {
                content
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.8))
            .cornerRadius(12)
            // 添加边框或阴影以增强豆腐块质感
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .fixedSize(horizontal: false, vertical: true) // 允许换行
            }
        }
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
            
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
