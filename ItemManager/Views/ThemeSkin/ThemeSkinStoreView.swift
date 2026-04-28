import SwiftUI

struct ThemeSkinStoreView: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @ObservedObject private var vipManager = VIPManager.shared
    @Environment(ThemeManager.self) private var themeManager

    @State private var alertTitle = "提示"
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showCoinStore = false
    private let fallbackThemeBasePrice = 99

    private var lowestVipPrice: Int {
        themeSkinManager.products.map(\.vipPrice).min()
            ?? VIPManager.discountedPrice(fallbackThemeBasePrice, rate: VIPManager.themeSkinShopDiscountRate)
    }

    private var currentBalance: Int {
        themeSkinManager.currentMeowCoinBalance
    }

    private var activeProductName: String? {
        guard let activeThemeId = themeSkinManager.activeThemeId else { return nil }
        return themeSkinManager.product(for: activeThemeId)?.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                themeProductList
                purchaseNotesCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
        .background(storeBackground.ignoresSafeArea())
        .refreshable {
            themeSkinManager.reloadFromDisk()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCoinStore = true
                } label: {
                    Label("喵币商店", systemImage: "pawprint.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showCoinStore) {
            MeowCoinStoreView()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("主题皮肤商店")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text("购买后仅可启用该主题自己的顶部栏、底部栏、搜索栏和卡片组件，不支持跨主题混搭。")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("当前余额")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeManager.secondaryTextColor)

                    Text("\(currentBalance)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text("喵币")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.accentTextColor)
                }
            }

            ViewThatFits(in: .horizontal) {
                statusChipRow
                statusChipColumn
            }
        }
        .padding(18)
        .background(cardShell(cornerRadius: 26))
    }

    private var themeProductList: some View {
        VStack(spacing: 16) {
            ForEach(themeSkinManager.products) { product in
                ThemeSkinProductStoreCard(
                    product: product,
                    currentBalance: currentBalance,
                    quote: themeSkinManager.priceQuote(for: product.themeId),
                    isPurchased: themeSkinManager.isPurchased(product.themeId),
                    isActive: themeSkinManager.isActiveTheme(product.themeId),
                    purchaseAction: {
                        guard let quote = themeSkinManager.priceQuote(for: product.themeId) else { return }
                        if currentBalance < quote.finalPrice {
                            showCoinStore = true
                        } else {
                            present(themeSkinManager.purchaseTheme(product.themeId, autoActivateIfNeeded: true))
                        }
                    },
                    toggleAction: {
                        let result = themeSkinManager.isActiveTheme(product.themeId)
                            ? themeSkinManager.deactivateCurrentTheme()
                            : themeSkinManager.activateTheme(product.themeId)
                        present(result)
                    }
                )
            }
        }
    }

    private var statusChipRow: some View {
        HStack(spacing: 10) {
            purchaseStateChip
            activeStateChip
            vipStateChip
        }
    }

    private var statusChipColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                purchaseStateChip
                activeStateChip
            }

            vipStateChip
        }
    }

    private var purchaseStateChip: some View {
        ThemeSkinInfoChip(
            title: "\(themeSkinManager.products.count) 个主题",
            systemImage: "sparkles",
            tint: themeManager.accentTextColor
        )
    }

    private var activeStateChip: some View {
        ThemeSkinInfoChip(
            title: activeProductName.map { "使用中：\($0)" } ?? "未启用",
            systemImage: activeProductName == nil ? "circle.dashed" : "wand.and.stars.inverse",
            tint: activeProductName == nil ? themeManager.secondaryTextColor : Color(hex: "FF6BA6")
        )
    }

    private var vipStateChip: some View {
        Group {
            if vipManager.isVIP {
                DiscountBadgeView(text: VIPManager.themeSkinDiscountText, style: .capsuleGlow, size: .small)
            } else {
                ThemeSkinInfoChip(
                    title: "VIP 最低 \(lowestVipPrice)喵币",
                    systemImage: "crown.fill",
                    tint: Color(hex: "FF8A5B")
                )
            }
        }
    }

    private var purchaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("购买说明")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            ThemeSkinBulletRow(text: "购买后只能启用同一主题包内的组件，不会与其他主题皮肤混用。")
            ThemeSkinBulletRow(text: "每个组件支持单独启用或停用，未启用时回退系统默认样式。")
            ThemeSkinBulletRow(text: "若喵币不足，可直接从右上角进入喵币商店补充。")
        }
        .padding(18)
        .background(cardShell(cornerRadius: 24))
    }

    private var storeBackground: some View {
        LinearGradient(
            colors: [
                themeManager.backgroundColor.opacity(0.96),
                Color.white.opacity(0.45),
                themeManager.cardTintColor.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func cardShell(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background(CardBackgroundView(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.78),
                                themeManager.cardTintColor.opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            )
            .shadow(color: themeManager.cardTintColor.opacity(0.10), radius: 20, x: 0, y: 10)
    }

    private func present(_ result: ThemeSkinActionResult) {
        alertTitle = result.success ? "操作成功" : "操作失败"
        alertMessage = result.message
        showAlert = true
    }
}

private struct ThemeSkinProductStoreCard: View {
    let product: ThemeSkinProduct
    let currentBalance: Int
    let quote: ThemeSkinPriceQuote?
    let isPurchased: Bool
    let isActive: Bool
    let purchaseAction: () -> Void
    let toggleAction: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    private var displayPrice: Int { quote?.finalPrice ?? product.basePrice }
    private var previewAssetName: String { product.previewAssetNames.first ?? ThemeSkinAssetName.previewStoreHero }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ThemeSkinOptionalFittedAsset(previewAssetName) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(themeManager.cardTintColor.opacity(0.18))
                        .overlay(Image(systemName: "sparkles").foregroundStyle(themeManager.accentTextColor))
                }
                .frame(width: 112, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(themeManager.primaryTextColor)
                            Text(product.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(themeManager.secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        ThemeSkinStatusBadge(isPurchased: isPurchased, isActive: isActive)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(displayPrice)")
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
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(product.defaultEnabledSlots) { slot in
                    ThemeSkinSlotTag(title: slot.displayName)
                }
            }

            VStack(spacing: 10) {
                Button(action: purchaseAction) {
                    ThemeSkinActionLabel(
                        title: isPurchased ? "已购买\(product.name)主题" : "购买主题",
                        subtitle: isPurchased ? "主题组件已加入你的皮肤库" : "立即支付 \(displayPrice) 喵币，VIP 自动享 9 折",
                        systemImage: isPurchased ? "checkmark.seal.fill" : "bag.fill"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchased)
                .opacity(isPurchased ? 0.6 : 1)
                .background(
                    LinearGradient(
                        colors: isPurchased ? [Color.gray.opacity(0.28), Color.gray.opacity(0.18)] : [Color(hex: "FFB7CF"), Color(hex: "FFC7AB")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    Button(action: toggleAction) {
                        ThemeSkinMiniActionLabel(title: isActive ? "停用主题" : "应用主题", systemImage: isActive ? "power.circle.fill" : "wand.and.stars")
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPurchased)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isPurchased ? themeManager.cardTintColor.opacity(0.18) : Color.gray.opacity(0.12))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(isPurchased ? 1 : 0.45)

                    NavigationLink {
                        ThemeSkinDetailView(themeId: product.themeId)
                    } label: {
                        ThemeSkinMiniActionLabel(title: "进入详情", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.clear)
                .background(CardBackgroundView(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.78), lineWidth: 1.1)
                )
        )
    }
}

private struct ThemeSkinStatusBadge: View {
    let isPurchased: Bool
    let isActive: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(isPurchased ? "已购" : "未购")
                .font(.caption.weight(.bold))
                .foregroundStyle(isPurchased ? Color.green : Color(hex: "FF7E9F"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((isPurchased ? Color.green : Color(hex: "FF7E9F")).opacity(0.14))
                )

            if isActive {
                Text("使用中")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: "FF5C93"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.84))
                    )
            }
        }
    }
}

private struct ThemeSkinInfoChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct ThemeSkinSlotTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: "B75C7C"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.76))
            )
            .overlay(
                Capsule()
                    .stroke(Color(hex: "FFB5CB").opacity(0.85), lineWidth: 1)
            )
    }
}

private struct ThemeSkinActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.black.opacity(0.88))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ThemeSkinMiniActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

private struct ThemeSkinBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: "FF8FAE"))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        ThemeSkinStoreView()
            .environment(ThemeManager.shared)
    }
}
