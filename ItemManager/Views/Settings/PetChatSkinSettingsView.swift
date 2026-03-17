import SwiftUI

struct PetChatSkinSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AdaptiveSettingsView(title: "萌宠对话皮肤") {
            AdaptiveSection(header: "皮肤选择", footer: "切换后立即生效，适用于搜索栏萌宠对话与聊天气泡。") {
                ForEach(PetChatSkinTheme.allCases) { skin in
                    Button {
                        themeManager.petChatSkinTheme = skin
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: skin.userBubbleColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(skin.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(skin.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if themeManager.petChatSkinTheme == skin {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .adaptiveRow(showDivider: skin != PetChatSkinTheme.allCases.last)
                }
            }

            AdaptiveSection(header: "实时预览") {
                PetChatSkinPreviewCard(theme: themeManager.petChatSkinTheme, colorScheme: colorScheme)
                    .adaptiveRow(showDivider: false)
            }
        }
    }
}

private struct PetChatSkinPreviewCard: View {
    let theme: PetChatSkinTheme
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("奶茶：今天想要偏甜美，还是偏通勤呢？")
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(assistantBubbleBackground)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("主人：先给我看天气穿搭～")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(userBubbleBackground)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text("快捷选项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    previewChip("A. 搭一套")
                    previewChip("B. 看天气")
                    previewChip("C. 找裙子")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: theme.previewBackgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var userBubbleBackground: some View {
        RoundedRectangle(cornerRadius: theme.cornerRadius)
            .fill(
                LinearGradient(
                    colors: theme.userBubbleColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var assistantBubbleBackground: some View {
        RoundedRectangle(cornerRadius: theme.cornerRadius)
            .fill(theme == .classic ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: theme.assistantStrokeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: theme == .classic ? 0 : 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: 3, x: 0, y: 2)
    }

    private func previewChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.pink.opacity(0.12))
            .clipShape(Capsule())
    }
}
