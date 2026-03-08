import SwiftUI

/// 支持长按拷贝的文本组件
/// 用于详情页字段值显示，用户长按可弹出拷贝菜单
struct CopyableText: View {
    let text: String
    var font: Font = .subheadline
    var foregroundStyle: Color = .primary
    var alignment: TextAlignment = .trailing
    
    @State private var showCopyFeedback = false
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .multilineTextAlignment(alignment)
            .contentShape(Rectangle())
            // 使用 highPriorityGesture 确保长按手势优先
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        copyToClipboard()
                    }
            )
            .overlay {
                if showCopyFeedback {
                    CopyFeedbackView(text: text)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = text
        
        // 触发触觉反馈
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // 显示拷贝成功反馈
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopyFeedback = true
        }
        
        // 1.5秒后隐藏反馈
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyFeedback = false
            }
        }
    }
}

/// 拷贝成功弹窗视图 - 现代化设计
private struct CopyFeedbackView: View {
    let text: String
    
    var body: some View {
        VStack(spacing: 16) {
            // 成功图标
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 70, height: 70)
                
                Circle()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: 55, height: 55)
                
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.green)
            }
            
            // 标题
            Text("已拷贝到剪贴板")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            
            // 拷贝的内容预览
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .frame(maxWidth: 280)
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
        case "裙子总价", "裙子单价", "原价": return "tag"
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
