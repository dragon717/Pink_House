import SwiftUI

/// 支持长按拷贝的文本组件
/// 用于详情页字段值显示，用户长按可弹出拷贝菜单
struct CopyableText: View {
    let text: String
    var font: Font = .subheadline
    var foregroundStyle: Color = .primary
    var alignment: TextAlignment = .trailing
    var themeSkinLegibilitySlot: ThemeSkinSlot = .sectionCard
    var themeSkinDescriptor: ThemeSkinDescriptor? = nil
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .themeSkinLegibleText(
                level: .inline,
                slot: themeSkinLegibilitySlot,
                descriptor: themeSkinDescriptor
            )
            .multilineTextAlignment(alignment)
            .contentShape(Rectangle())
            // 使用 highPriorityGesture 确保长按手势优先
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        copyToClipboard()
                    }
            )
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = text
        
        // 触发触觉反馈
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // 使用全局提示管理器显示提示
        CopyToastManager.shared.show(text: text)
    }
}

/// 支持长按拷贝的InfoRow组件
/// 用于详情页字段标签-值对的显示，支持长按拷贝值
struct CopyableInfoRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: iconForLabel(label))
                .font(.caption)
                .foregroundStyle(themeManager.tertiaryTextColor)
                .frame(width: 20)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            
            Spacer()
            
            CopyableText(
                text: value,
                font: .subheadline,
                foregroundStyle: themeManager.primaryTextColor,
                alignment: .trailing
            )
        }
        .contentShape(Rectangle())
    }
    
    private func iconForLabel(_ label: String) -> String {
        switch label {
        case "类型": return "tshirt"
        case "颜色": return "paintpalette"
        case "尺码": return "ruler"
        case "衣长": return "arrow.up.and.down"
        case "状态": return "star.circle"
        case "小物": return "sparkles"
        case "裙装总价", "裙装单价", "原价": return "tag"
        case "库存数量": return "number.circle"
        case "购买日期": return "calendar"
        case "定金日期": return "calendar.badge.clock"
        case "预估尾款": return "hourglass"
        case "拥有时长": return "clock"
        case "尾款金额": return "creditcard"
        default: return "circle"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CopyableText(text: "长按我可以拷贝这段文字")
            .padding()
        
        CopyableInfoRow(label: "类型", value: "JSK")
        CopyableInfoRow(label: "颜色", value: " sax 蓝色")
        CopyableInfoRow(label: "品牌", value: "Angelic Pretty")
    }
    .padding()
    .environment(ThemeManager())
}
