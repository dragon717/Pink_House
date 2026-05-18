import SwiftUI

struct FavoriteMenuSettingsView: View {
    @StateObject private var settingsManager = FavoriteMenuSettingsManager.shared
    @StateObject private var bottomDockSettingsManager = BottomDockSettingsManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var showMaxItemsAlert = false

    // 所有可选功能（排除萌宠，因为有独立的萌宠对话 Tab）
    private let allItems = FavoriteMenuItem.allCases.filter { $0 != .pet }
    private let maxItems = 5

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                List {
                    Section {
                        ForEach(bottomDockSettingsManager.availableFeatures) { feature in
                            BottomDockFeatureRow(
                                feature: feature,
                                isSelected: bottomDockSettingsManager.selectedFeatureID == feature.id
                            ) {
                                bottomDockSettingsManager.setSelectedFeature(feature.id)
                            }
                            .listRowBackground(settingsRowBackground)
                        }
                    } header: {
                        Text("底部快捷入口")
                            .foregroundColor(themeManager.secondaryTextColor)
                    } footer: {
                        Text("替换底部最右侧入口。固定保留「衣橱」「House」「我」，这里负责你最常用的第四个入口。")
                            .foregroundColor(themeManager.secondaryTextColor)
                    }

                    // 已选中的常用功能（可排序），只显示已解锁的
                    Section {
                        ForEach(selectedAndUnlockedItems) { item in
                            SelectedItemRow(item: item, isEditing: isEditing)
                                .listRowBackground(settingsRowBackground)
                        }
                        .onMove { from, to in
                            settingsManager.reorderItems(from: from, to: to)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = selectedAndUnlockedItems[index]
                                settingsManager.removeItem(item)
                            }
                        }
                    } header: {
                        Text("House 长按菜单（左滑删除，最多 \(maxItems) 个）")
                            .foregroundColor(themeManager.secondaryTextColor)
                    } footer: {
                        Text("长按 House Tab 时仍会显示这些功能；底部快捷入口与这里互不冲突。")
                            .foregroundColor(themeManager.secondaryTextColor)
                    }

                    // 可选功能列表
                    Section {
                        ForEach(availableItems) { item in
                            AvailableItemRow(
                                item: item,
                                isSelected: false,
                                isDisabled: selectedAndUnlockedItems.count >= maxItems,
                                guideTargetKey: item == .ootd ? .favoriteMenuMagicStickerAddButton : nil
                            ) {
                                if selectedAndUnlockedItems.count >= maxItems {
                                    showMaxItemsAlert = true
                                } else {
                                    settingsManager.addItem(item)
                                }
                            }
                            .listRowBackground(settingsRowBackground)
                        }
                    } header: {
                        Text("House 菜单可选功能")
                            .foregroundColor(themeManager.secondaryTextColor)
                    } footer: {
                        Text("最多可选择 \(maxItems) 个 House 长按菜单功能")
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("常用入口设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "完成" : "编辑") {
                            withAnimation {
                                isEditing.toggle()
                            }
                        }
                        .foregroundColor(themeManager.accentTextColor)
                    }
                }
                .alert("常用菜单已满", isPresented: $showMaxItemsAlert) {
                    Button("我知道了", role: .cancel) {}
                } message: {
                    Text("最多只能添加 \(maxItems) 个常用功能，请先删除一些再添加新的")
                }
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .favoriteMenuSettingsOpened, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .favoriteMenuSettingsViewDismissed, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissFavoriteMenuSettingsView)) { _ in
            dismiss()
        }
    }
    
    // 计算已选中且已解锁的功能（用于显示，排除萌宠）
    private var selectedAndUnlockedItems: [FavoriteMenuItem] {
        settingsManager.selectedItems.filter { $0.isUnlocked && $0 != .pet }
    }
    
    // 计算还未选中且已解锁的功能（排除萌宠）
    private var availableItems: [FavoriteMenuItem] {
        allItems.filter { item in
            !settingsManager.selectedItems.contains(item) && item.isUnlocked
        }
    }

    private var settingsRowBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
            )
            .padding(.vertical, 4)
    }
}

// MARK: - 底部快捷入口行
private struct BottomDockFeatureRow: View {
    let feature: AppFeatureDescriptor
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: feature.systemImage)
                    .font(.title3)
                    .foregroundColor(Color(hex: feature.tintHex))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: feature.tintHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(.body)
                        .foregroundColor(themeManager.primaryTextColor)

                    Text(feature.subtitle)
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? themeManager.accentTextColor : themeManager.secondaryTextColor)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 已选中功能行
private struct SelectedItemRow: View {
    let item: FavoriteMenuItem
    let isEditing: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundColor(Color(hex: item.color))
                .frame(width: 36, height: 36)
                .background(Color(hex: item.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.rawValue)
                .font(.body)
                .foregroundColor(themeManager.primaryTextColor)

            Spacer()

            // 只在编辑模式下显示汉堡键
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - 可选功能行
private struct AvailableItemRow: View {
    let item: FavoriteMenuItem
    let isSelected: Bool
    let isDisabled: Bool
    let guideTargetKey: GuideTargetKey?
    let action: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundColor(isDisabled ? themeManager.secondaryTextColor : Color(hex: item.color))
                    .frame(width: 36, height: 36)
                    .background((isDisabled ? themeManager.secondaryTextColor : Color(hex: item.color)).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.rawValue)
                    .font(.body)
                    .foregroundColor(isDisabled ? themeManager.secondaryTextColor : themeManager.primaryTextColor)

                Spacer()

                Image(systemName: isDisabled ? "plus.circle" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(isDisabled ? themeManager.secondaryTextColor : themeManager.accentTextColor)
                    .captureGuideTarget(guideTargetKey)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 预览
#Preview {
    FavoriteMenuSettingsView()
}
