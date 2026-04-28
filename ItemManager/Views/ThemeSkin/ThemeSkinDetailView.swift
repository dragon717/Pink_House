import SwiftUI

struct ThemeSkinDetailView: View {
    let themeId: String

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager

    @State private var actionMessage = ""
    @State private var showActionAlert = false

    private var product: ThemeSkinProduct? {
        themeSkinManager.product(for: themeId)
    }

    private var isPurchased: Bool {
        themeSkinManager.isPurchased(themeId)
    }

    private var isActive: Bool {
        themeSkinManager.isActiveTheme(themeId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                previewCard
                livePreviewCard
                purchaseCard
                ThemeSkinSlotToggleSection(themeId: themeId)
            }
            .padding()
        }
        .background(LiquidBackground())
        .navigationTitle(product?.name ?? "主题详情")
        .navigationBarTitleDisplayMode(.inline)
        .alert("主题操作", isPresented: $showActionAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(actionMessage)
        }
    }

    private var previewCard: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product?.name ?? "主题")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(themeManager.primaryTextColor)

                        Text(product?.subtitle ?? "主题预览")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }

                    Spacer()

                    Text(isActive ? "使用中" : (isPurchased ? "已拥有" : "未购买"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isActive ? Color(hex: "FF5C93") : themeManager.accentTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.72)))
                }

                ThemeSkinOptionalFittedAsset(
                    ThemeSkinAssetName.previewStoreHero,
                    namespace: product?.assetNamespace,
                    allowShortNameFallback: false
                ) {
                    heroFallback
                }
                .frame(height: 236)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(18)
        }
    }

    private var heroFallback: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(themeManager.cardBackgroundColor.opacity(0.85))
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(themeManager.accentTextColor)
                    Text("主题预览")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text("顶部栏 / 卡片 / TabBar 会从同一主题包里解析，不允许和其他主题混用。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .padding(.horizontal)
                }
            )
    }

    private var livePreviewCard: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("实时组件预览")
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)

                VStack(spacing: 12) {
                    HStack {
                        ThemeSkinIconBadge(systemName: "sparkles", fallbackColor: themeManager.accentTextColor, size: 34, symbolSize: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("精致顶栏")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.primaryTextColor)
                            Text("卡片、按钮、空状态会随主题槽位开关实时回退。")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .themeSkinSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false)

                    HStack(spacing: 8) {
                        Text("卡片")
                        Text("按钮")
                        Text("空状态")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {} label: {
                        Label("主题主按钮示例", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: themeManager.accentTextColor))
                    .disabled(true)
                }
            }
            .padding(18)
        }
    }

    private var purchaseCard: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("购买与应用")
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)

                if let product, let quote = themeSkinManager.priceQuote(for: themeId) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(quote.finalPrice)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(themeManager.primaryTextColor)
                        Text("喵币")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.secondaryTextColor)
                        Text("原价 \(product.basePrice)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .strikethrough()
                    }
                }

                if !isPurchased {
                    Button {
                        present(themeSkinManager.purchaseTheme(themeId, autoActivateIfNeeded: true).message)
                    } label: {
                        Label("购买并应用", systemImage: "bag.fill")
                    }
                    .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: themeManager.accentTextColor))
                } else {
                    Button {
                        let result = isActive
                            ? themeSkinManager.deactivateCurrentTheme()
                            : themeSkinManager.activateTheme(themeId)
                        present(result.message)
                    } label: {
                        Label(isActive ? "停用主题" : "应用主题", systemImage: isActive ? "power.circle.fill" : "wand.and.stars")
                    }
                    .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: isActive ? .gray : themeManager.accentTextColor))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private func present(_ message: String) {
        actionMessage = message
        showActionAlert = true
    }
}
