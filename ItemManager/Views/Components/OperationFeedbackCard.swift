import SwiftUI

/// 普通提示、复制和奖励共同使用的卡片；主题不改写系统材质与语义颜色。
struct OperationFeedbackCard: View {
    let message: OperationFeedbackCenter.Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.kind.icon)
                .font(.title3)
                .foregroundStyle(message.kind.color)
            VStack(alignment: .leading, spacing: 5) {
                Text(message.text).font(.subheadline.weight(.semibold))
                if message.fishCoins > 0 {
                    Label("鱼币 +%@".appLocalized(String(message.fishCoins)), systemImage: "fish.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let detail = message.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if message.fishCoins > 0 {
                    Button("查看魔法任务".appLocalized) {
                        NotificationCenter.default.post(name: .navigateToMagicTasks, object: nil)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .systemBackground).opacity(0.94))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("operationFeedbackCard")
    }
}
