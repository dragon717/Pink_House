import SwiftUI

// MARK: - 颜色选择类型
enum ThemeColorPickerType {
    case primary, secondary, tertiary, accent
    case cardBackground, cardAccent, deposit, finalPayment
}

struct MagicThemeModuleSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var unlockManager = FeatureUnlockManager.shared

    // 颜色选择器状态
    @State private var showingColorPicker = false
    @State private var colorPickerType: ThemeColorPickerType = .primary

    // 保存主题相关状态
    @State private var showNameInputAlert = false
    @State private var showOverwriteAlert = false
    @State private var customThemeName: String = ""
    @State private var pendingThemeName: String = ""

    // 检查魔法配色是否已解锁
    private var isMagicColorUnlocked: Bool {
        unlockManager.isUnlocked(.themeCustomize)
    }

    // 当前主题
    private var currentTheme: ThemePreset {
        themeManager.themeColorConfig.currentTheme(forDarkMode: colorScheme == .dark)
    }

    // 检查当前主题是否与默认预设相同（用于判断保存按钮是否可点击）
    private var hasChanges: Bool {
        // 如果当前是自定义模式且没有选中预设，则认为有变化可以保存
        let config = themeManager.themeColorConfig
        if config.colorSchemeMode == .custom && config.customColorConfig.selectedPresetId == nil {
            return true
        }
        // 如果有选中的预设，也可以保存为自定义主题
        if config.colorSchemeMode == .custom && config.customColorConfig.selectedPresetId != nil {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题和保存按钮区域
            HStack {
                Text("我的主题方案")
                    .font(.headline)

                Spacer()

                // 保存按钮 - 无变化时为灰色
                Button {
                    handleSaveTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption)
                        Text("保存")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.accentTextColor)
                .disabled(!hasChanges)
                .opacity(hasChanges ? 1.0 : 0.5)
            }
            .padding(.horizontal, 4)

            // 已保存的主题列表
            if !themeManager.themeColorConfig.customColorConfig.userCustomThemes.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(themeManager.themeColorConfig.customColorConfig.userCustomThemes) { theme in
                        MyThemeCard(
                            theme: theme,
                            isActive: isThemeActive(theme)
                        ) {
                            _ = themeManager.applyThemeSet(named: theme.name)
                        } onDelete: {
                            themeManager.deleteThemeSet(id: theme.id)
                        }
                    }
                }
            }

            // 自定义颜色设置 - 仅在魔法配色解锁时显示
            if isMagicColorUnlocked {
                Divider()
                    .padding(.vertical, 4)

                customColorsSection
            } else {
                // 未解锁时的提示
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                    Text("解锁后可自定义颜色")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        // 颜色选择器 Sheet
        .sheet(isPresented: $showingColorPicker) {
            CompactColorPickerSheet(
                title: colorPickerTitle,
                colorType: colorPickerType,
                selectedColor: bindingForColorPickerType(),
                onReset: { resetColorToDefault() }
            )
        }
        // 输入主题名称弹窗
        .alert("保存主题方案", isPresented: $showNameInputAlert) {
            TextField("输入主题名称", text: $customThemeName)
            Button("取消", role: .cancel) {
                customThemeName = ""
            }
            Button("保存") {
                let name = customThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingThemeName = name.isEmpty ? "我的主题\(Date().formatted(date: .omitted, time: .shortened))" : name
                checkAndSave()
            }
        } message: {
            Text("为当前主题配色方案起个名字")
        }
        // 覆盖确认弹窗
        .alert("主题已存在", isPresented: $showOverwriteAlert) {
            Button("取消", role: .cancel) { }
            Button("覆盖", role: .destructive) {
                performSave()
            }
        } message: {
            Text("已存在名为「\(pendingThemeName)」的主题方案，是否覆盖？")
        }
    }

    // MARK: - 保存主题处理
    private func handleSaveTap() {
        customThemeName = ""
        showNameInputAlert = true
    }

    private func checkAndSave() {
        // 检查是否已存在同名主题
        let exists = themeManager.themeColorConfig.customColorConfig.userCustomThemes.contains {
            $0.name.localizedCaseInsensitiveCompare(pendingThemeName) == .orderedSame
        }

        if exists {
            showOverwriteAlert = true
        } else {
            performSave()
        }
    }

    private func performSave() {
        _ = themeManager.saveCurrentThemeAsSet(named: pendingThemeName)
        customThemeName = ""
        pendingThemeName = ""
    }

    // MARK: - 自定义颜色区域（紧凑布局）
    private var customColorsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自定义颜色")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            // 字体配色 - 紧凑网格布局
            VStack(alignment: .leading, spacing: 8) {
                Text("字体配色")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // 紧凑的颜色选择网格
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    CompactColorButton(
                        title: "主标题",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).primary.color,
                        isSelected: false
                    ) {
                        colorPickerType = .primary
                        showingColorPicker = true
                    }

                    CompactColorButton(
                        title: "副标题",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).secondary.color,
                        isSelected: false
                    ) {
                        colorPickerType = .secondary
                        showingColorPicker = true
                    }

                    CompactColorButton(
                        title: "辅助文字",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).tertiary.color,
                        isSelected: false
                    ) {
                        colorPickerType = .tertiary
                        showingColorPicker = true
                    }

                    CompactColorButton(
                        title: "强调色",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).accent.color,
                        isSelected: false
                    ) {
                        colorPickerType = .accent
                        showingColorPicker = true
                    }
                }
            }

            // 卡片配色 - 紧凑网格布局
            VStack(alignment: .leading, spacing: 8) {
                Text("卡片配色")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    CompactColorButton(
                        title: "卡片背景",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).backgroundRGBA.color,
                        isSelected: false
                    ) {
                        colorPickerType = .cardBackground
                        showingColorPicker = true
                    }

                    CompactColorButton(
                        title: "卡片强调",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).accentRGBA.color,
                        isSelected: false
                    ) {
                        colorPickerType = .cardAccent
                        showingColorPicker = true
                    }

                    CompactColorButton(
                        title: "定金标记",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).depositRGBA.color,
                        isSelected: false
                    ) {
                        colorPickerType = .deposit
                        showingColorPicker = true
                    }

                    CompactColorButton(
                        title: "尾款标记",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).finalPaymentRGBA.color,
                        isSelected: false
                    ) {
                        colorPickerType = .finalPayment
                        showingColorPicker = true
                    }
                }
            }
        }
    }

    // MARK: - 颜色选择器标题
    private var colorPickerTitle: String {
        switch colorPickerType {
        case .primary: return "主标题颜色"
        case .secondary: return "副标题颜色"
        case .tertiary: return "辅助文字颜色"
        case .accent: return "强调色"
        case .cardBackground: return "卡片背景色"
        case .cardAccent: return "卡片强调色"
        case .deposit: return "定金标记色"
        case .finalPayment: return "尾款标记色"
        }
    }

    // MARK: - 颜色选择器绑定
    private func bindingForColorPickerType() -> Binding<Color> {
        let config = themeManager.themeColorConfig.customColorConfig
        let isDark = colorScheme == .dark

        switch colorPickerType {
        case .primary:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextPrimaryRGBA : config.currentCustom.textPrimaryRGBA).color },
                set: { updateTextColor($0, for: \.textPrimaryRGBA, dark: \.darkTextPrimaryRGBA) }
            )
        case .secondary:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextSecondaryRGBA : config.currentCustom.textSecondaryRGBA).color },
                set: { updateTextColor($0, for: \.textSecondaryRGBA, dark: \.darkTextSecondaryRGBA) }
            )
        case .tertiary:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextTertiaryRGBA : config.currentCustom.textTertiaryRGBA).color },
                set: { updateTextColor($0, for: \.textTertiaryRGBA, dark: \.darkTextTertiaryRGBA) }
            )
        case .accent:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextAccentRGBA : config.currentCustom.textAccentRGBA).color },
                set: { updateTextColor($0, for: \.textAccentRGBA, dark: \.darkTextAccentRGBA) }
            )
        case .cardBackground:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.backgroundRGBA : config.currentCustom.cardConfig.backgroundRGBA).color },
                set: { updateCardColor($0, for: \.backgroundRGBA) }
            )
        case .cardAccent:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.accentRGBA : config.currentCustom.cardConfig.accentRGBA).color },
                set: { updateCardColor($0, for: \.accentRGBA) }
            )
        case .deposit:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.depositRGBA : config.currentCustom.cardConfig.depositRGBA).color },
                set: { updateCardColor($0, for: \.depositRGBA) }
            )
        case .finalPayment:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.finalPaymentRGBA : config.currentCustom.cardConfig.finalPaymentRGBA).color },
                set: { updateCardColor($0, for: \.finalPaymentRGBA) }
            )
        }
    }

    private func updateTextColor(_ color: Color, for keyPath: WritableKeyPath<UserCustomTheme, ColorRGBA>, dark darkKeyPath: WritableKeyPath<UserCustomTheme, ColorRGBA>) {
        guard let rgba = color.rgba else { return }
        var newConfig = themeManager.themeColorConfig
        let isDark = colorScheme == .dark
        if isDark {
            newConfig.customColorConfig.currentCustom[keyPath: darkKeyPath] = rgba
        } else {
            newConfig.customColorConfig.currentCustom[keyPath: keyPath] = rgba
        }
        // 切换到自定义模式
        newConfig.customColorConfig.selectedPresetId = nil
        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }

    private func updateCardColor(_ color: Color, for keyPath: WritableKeyPath<CardColorConfig, ColorRGBA>) {
        guard let rgba = color.rgba else { return }
        var newConfig = themeManager.themeColorConfig
        let isDark = colorScheme == .dark
        if isDark {
            var darkCard = newConfig.customColorConfig.currentCustom.darkCardConfig
            darkCard[keyPath: keyPath] = rgba
            newConfig.customColorConfig.currentCustom.darkCardConfig = darkCard
        } else {
            var customCard = newConfig.customColorConfig.currentCustom.cardConfig
            customCard[keyPath: keyPath] = rgba
            newConfig.customColorConfig.currentCustom.cardConfig = customCard
        }
        // 切换到自定义模式
        newConfig.customColorConfig.selectedPresetId = nil
        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }

    // MARK: - 重置颜色
    private func resetColorToDefault() {
        let isDark = colorScheme == .dark
        var newConfig = themeManager.themeColorConfig

        switch colorPickerType {
        case .primary:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextPrimaryRGBA = ColorRGBA.white
            } else {
                newConfig.customColorConfig.currentCustom.textPrimaryRGBA = ColorRGBA(r: 0.42, g: 0.36, b: 0.45)
            }
        case .secondary:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextSecondaryRGBA = ColorRGBA(r: 0.70, g: 0.65, b: 0.75)
            } else {
                newConfig.customColorConfig.currentCustom.textSecondaryRGBA = ColorRGBA(r: 0.61, g: 0.54, b: 0.65)
            }
        case .tertiary:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextTertiaryRGBA = ColorRGBA(r: 0.55, g: 0.50, b: 0.60)
            } else {
                newConfig.customColorConfig.currentCustom.textTertiaryRGBA = ColorRGBA(r: 0.77, g: 0.71, b: 0.80)
            }
        case .accent:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextAccentRGBA = ColorRGBA(r: 0.90, g: 0.70, b: 0.85)
            } else {
                newConfig.customColorConfig.currentCustom.textAccentRGBA = ColorRGBA(r: 0.85, g: 0.65, b: 0.78)
            }
        case .cardBackground:
            let defaultBg = isDark ? ColorRGBA(r: 0.25, g: 0.20, b: 0.28) : ColorRGBA(r: 1.0, g: 0.94, b: 0.96)
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.backgroundRGBA = defaultBg
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.backgroundRGBA = defaultBg
            }
        case .cardAccent:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.accentRGBA = ColorRGBA(r: 0.70, g: 0.60, b: 0.75)
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.accentRGBA = ColorRGBA(r: 0.85, g: 0.75, b: 0.85)
            }
        case .deposit:
            let gold = ColorRGBA(r: 1.0, g: 0.84, b: 0.0)
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.depositRGBA = gold
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.depositRGBA = gold
            }
        case .finalPayment:
            let pink = ColorRGBA(r: 1.0, g: 0.41, b: 0.71)
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.finalPaymentRGBA = pink
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.finalPaymentRGBA = pink
            }
        }

        newConfig.customColorConfig.selectedPresetId = nil
        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }

    // 检查主题是否是当前激活的主题
    private func isThemeActive(_ theme: UserCustomTheme) -> Bool {
        let current = themeManager.themeColorConfig.customColorConfig.currentCustom
        return themeManager.colorSchemeMode == .custom
            && themeManager.themeColorConfig.customColorConfig.selectedPresetId == nil
            && current.id == theme.id
    }
}

// MARK: - 预览
#Preview {
    MagicThemeModuleSection()
        .environment(ThemeManager.shared)
}
