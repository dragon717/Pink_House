import SwiftUI

struct FavoriteMenuSettingsView: View {
    @StateObject private var bottomDockSettingsManager = BottomDockSettingsManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                List {
                    Section {
                        ForEach(bottomDockSettingsManager.slots, id: \.self) { slotIndex in
                            BottomDockSlotPickerRow(
                                slotTitle: bottomDockSettingsManager.slotTitle(for: slotIndex),
                                selectedFeature: bottomDockSettingsManager.feature(at: slotIndex),
                                availableFeatures: bottomDockSettingsManager.availableFeatures
                            ) { featureID in
                                bottomDockSettingsManager.setFeature(featureID, at: slotIndex)
                            }
                            .listRowBackground(settingsRowBackground)
                        }
                    } header: {
                        Text("底部导航".appLocalized)
                            .foregroundColor(themeManager.secondaryTextColor)
                    } footer: {
                        Text("四个位置都可以调整；选择已在其他位置使用的入口时，会自动互换。系统会保留「House」和「我」入口，避免房间和设置页失联。".appLocalized)
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("底部导航设置".appLocalized)
                .navigationBarTitleDisplayMode(.inline)
            }
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

// MARK: - 底部导航位置行
private struct BottomDockSlotPickerRow: View {
    let slotTitle: String
    let selectedFeature: AppFeatureDescriptor
    let availableFeatures: [AppFeatureDescriptor]
    let onSelect: (AppFeatureID) -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 12) {
            Text(slotTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(themeManager.secondaryTextColor)
                .frame(width: 50, alignment: .leading)

            Image(systemName: selectedFeature.systemImage)
                .font(.title3)
                .foregroundColor(Color(hex: selectedFeature.tintHex))
                .frame(width: 36, height: 36)
                .background(Color(hex: selectedFeature.tintHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedFeature.localizedTitle)
                    .font(.body)
                    .foregroundColor(themeManager.primaryTextColor)

                Text(selectedFeature.localizedSubtitle)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                ForEach(availableFeatures) { feature in
                    Button {
                        onSelect(feature.id)
                    } label: {
                        Label(feature.localizedTitle, systemImage: feature.systemImage)
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(themeManager.accentTextColor)
                    .frame(width: 32, height: 32)
                    .background(themeManager.accentTextColor.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - 预览
#Preview {
    FavoriteMenuSettingsView()
}
