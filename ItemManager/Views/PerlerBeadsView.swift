import SwiftUI

struct PerlerBeadsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.95, blue: 0.97),
                        Color(red: 0.98, green: 0.92, blue: 0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 30) {
                    // 图标
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.55, blue: 0.75),
                                        Color(red: 1.0, green: 0.41, blue: 0.71)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .shadow(color: Color(red: 1.0, green: 0.41, blue: 0.71).opacity(0.3), radius: 20, x: 0, y: 10)

                        Image(systemName: "circle.grid.2x2")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }

                    // 标题
                    Text("拼豆工坊")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.25))

                    // 描述
                    Text("即将上线，敬请期待")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.45))

                    // 功能预览
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "photo", text: "图片转拼豆图案")
                        FeatureRow(icon: "pencil", text: "自由绘制像素画")
                        FeatureRow(icon: "list.bullet", text: "生成材料清单")
                        FeatureRow(icon: "square.and.arrow.up", text: "分享你的作品")
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                    Spacer()

                    // 提示文字
                    Text("正在精心打造中...")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.55))
                        .padding(.bottom, 30)
                }
                .padding(.top, 60)
            }
            .navigationTitle("拼豆")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 功能预览行
private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.41, blue: 0.71))
                .frame(width: 32)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.35))

            Spacer()
        }
    }
}

// MARK: - 预览
#Preview {
    PerlerBeadsView()
}
