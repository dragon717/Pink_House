import SwiftUI

struct WardrobeNavigationStyleSelectionView: View {
    @AppStorage("UserPreference_WardrobeNavigationStyle") private var wardrobeNavigationStyle: WardrobeNavigationStyle = .classic
    
    var body: some View {
        AdaptiveSettingsView(title: "选择样式") {
            AdaptiveSection(
                header: "衣橱顶部导航",
                footer: "经典样式保持现有布局；时尚样式会将排序/筛选放在左侧，顶部标签切换居中，视图/更多/创建放在右侧。"
            ) {
                Picker("样式", selection: $wardrobeNavigationStyle) {
                    ForEach(WardrobeNavigationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .adaptiveRow()
                
                styleRow(.classic, icon: "rectangle.leadinghalf.filled")
                    .adaptiveRow()
                
                styleRow(.fashion, icon: "rectangle.center.inset.filled")
                    .adaptiveRow(showDivider: false)
            }
        }
    }
    
    @ViewBuilder
    private func styleRow(_ style: WardrobeNavigationStyle, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(style.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(style.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if wardrobeNavigationStyle == style {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.pink)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            wardrobeNavigationStyle = style
        }
    }
}
