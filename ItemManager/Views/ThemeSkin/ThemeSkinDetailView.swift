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
        VStack(alignment: .leading, spacing: 12) {
            Text(product?.name ?? "主题")
                .font(.title3.bold())
                .foregroundStyle(themeManager.primaryTextColor)

            Text(product?.subtitle ?? "主题预览")
                .font(.subheadline)
                .foregroundStyle(themeManager.secondaryTextColor)

            ThemeSkinOptionalFittedAsset(ThemeSkinAssetName.previewStoreHero) {
                RoundedRectangle(cornerRadius: 20)
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
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            CardBackgroundView(cornerRadius: 24)
        }
    }

    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("购买与应用")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            if let product, let quote = themeSkinManager.priceQuote(for: themeId) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("原价 \(product.basePrice) 喵币")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                    Text("当前价 \(quote.finalPrice) 喵币")
                        .font(.title3.bold())
                        .foregroundStyle(themeManager.primaryTextColor)
                }
            }

            HStack(spacing: 10) {
                if !isPurchased {
                    Button {
                        present(themeSkinManager.purchaseTheme(themeId, autoActivateIfNeeded: true).message)
                    } label: {
                        Text("购买并应用")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.accentTextColor)
                } else {
                    Button {
                        let result = isActive
                            ? themeSkinManager.deactivateCurrentTheme()
                            : themeSkinManager.activateTheme(themeId)
                        present(result.message)
                    } label: {
                        Text(isActive ? "停用主题" : "应用主题")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isActive ? .gray : themeManager.accentTextColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            CardBackgroundView(cornerRadius: 24)
        }
    }

    private func present(_ message: String) {
        actionMessage = message
        showActionAlert = true
    }
}
