import SwiftUI

struct MagicThemeModuleSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var customThemeName: String = ""

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模块预览与主题方案")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                modulePreviewCard(
                    title: "梦幻衣橱",
                    subtitle: "原生顶部栏 · 菜单 · 页签"
                ) {
                    wardrobePreview
                }

                modulePreviewCard(
                    title: "梦裙日历",
                    subtitle: "筛选按钮 · 分段页签"
                ) {
                    calendarPreview
                }

                modulePreviewCard(
                    title: "马上来财",
                    subtitle: "请签文字色 · 容器系统文字色"
                ) {
                    wealthPreview
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("给当前主题起个名字（可选）", text: $customThemeName)
                        .textFieldStyle(.roundedBorder)

                    Button("保存") {
                        _ = themeManager.saveCurrentThemeAsSet(named: customThemeName)
                        customThemeName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }

                HStack(spacing: 8) {
                    Button("恢复默认") {
                        themeManager.restoreDefaultThemeSet()
                    }
                    .buttonStyle(.bordered)

                    Button("切到魔法") {
                        themeManager.switchColorSchemeMode(to: .magic)
                    }
                    .buttonStyle(.bordered)

                    Button("切到客制化") {
                        themeManager.switchColorSchemeMode(to: .custom)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !themeManager.themeColorConfig.customColorConfig.userCustomThemes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("我的主题方案")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(themeManager.themeColorConfig.customColorConfig.userCustomThemes) { theme in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(theme.textAccentRGBA.color)
                                .frame(width: 12, height: 12)
                            Text(theme.name)
                                .font(.subheadline)
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Button("应用") {
                                _ = themeManager.applyThemeSet(named: theme.name)
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                themeManager.deleteThemeSet(id: theme.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func modulePreviewCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(palette.primaryText)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.cardBackground.opacity(colorScheme == .dark ? 0.46 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.quickOptionStroke.opacity(0.8), lineWidth: 1)
        )
    }

    private var wardrobePreview: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                Image(systemName: "line.3.horizontal.decrease.circle")
                Spacer()
                Text("少女衣橱 / 心愿尾款")
                    .font(.caption2)
                Spacer()
                Image(systemName: "square.grid.2x2")
                Image(systemName: "ellipsis.circle")
            }
            .font(.caption)
            .foregroundStyle(palette.navigationForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(palette.navigationBackground)
            )
        }
    }

    private var calendarPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintpalette")
            Capsule()
                .fill(palette.segmentedBackground)
                .frame(width: 110, height: 28)
                .overlay(
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(palette.segmentedSelectedBackground)
                            .frame(width: 52, height: 22)
                            .overlay(Text("月").font(.caption2).foregroundStyle(palette.segmentedSelectedForeground))
                        Text("年")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                    }
                )
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .foregroundStyle(palette.accent)
        .font(.caption)
    }

    private var wealthPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("请签：今日适合温柔俏皮配色")
                .font(.caption)
                .foregroundStyle(palette.primaryText)
            HStack(spacing: 8) {
                Text("请签")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.quickOptionFill)
                    .clipShape(Capsule())
                Text("数钱")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                Text("安财")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }
}
