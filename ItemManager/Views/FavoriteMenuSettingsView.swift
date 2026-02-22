import SwiftUI

struct FavoriteMenuSettingsView: View {
    @StateObject private var settingsManager = FavoriteMenuSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    
    // 所有可选功能
    private let allItems = FavoriteMenuItem.allCases
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                List {
                    // 已选中的常用功能（可排序）
                    Section {
                        ForEach(settingsManager.selectedItems) { item in
                            SelectedItemRow(item: item, isEditing: isEditing)
                        }
                        .onMove { from, to in
                            settingsManager.reorderItems(from: from, to: to)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = settingsManager.selectedItems[index]
                                settingsManager.removeItem(item)
                            }
                        }
                    } header: {
                        Text("已选中的常用功能（左滑删除）")
                    } footer: {
                        Text("长按小世界 Tab 按钮，常用分类将显示这些功能")
                    }

                    // 可选功能列表
                    Section("可选功能") {
                        ForEach(availableItems) { item in
                            AvailableItemRow(
                                item: item,
                                isSelected: false
                            ) {
                                settingsManager.addItem(item)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("常用菜单设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "完成" : "编辑") {
                            withAnimation {
                                isEditing.toggle()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // 计算还未选中的功能
    private var availableItems: [FavoriteMenuItem] {
        allItems.filter { item in
            !settingsManager.selectedItems.contains(item)
        }
    }
}

// MARK: - 已选中功能行
private struct SelectedItemRow: View {
    let item: FavoriteMenuItem
    let isEditing: Bool
    
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
            
            Spacer()
            
            // 只在编辑模式下显示汉堡键
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 可选功能行
private struct AvailableItemRow: View {
    let item: FavoriteMenuItem
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundColor(Color(hex: item.color))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: item.color).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(item.rawValue)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.pink)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 预览
#Preview {
    FavoriteMenuSettingsView()
}
