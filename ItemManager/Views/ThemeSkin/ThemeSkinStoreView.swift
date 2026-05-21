import SwiftUI

struct ThemeSkinStoreView: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @ObservedObject private var vipManager = VIPManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

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
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                themeProductList
                purchaseNotesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 126)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Boutique Gallery", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(themeManager.accentTextColor)
                        .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        .textCase(.uppercase)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.52), in: Capsule())

                    Text("主题皮肤画廊")
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(themeManager.primaryTextColor)
                        .themeSkinLegibleText(level: .chip, slot: .sectionCard)

                    Text("挑选一整套视觉语言，顶部、底栏、卡片与按钮只在同主题内成套生效。")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ThemeSkinBalancePill(balance: currentBalance)
            }

            galleryStrip

            ViewThatFits(in: .horizontal) {
                statusChipRow
                statusChipColumn
            }
        }
        .padding(18)
        .themeSkinSectionCard(cornerRadius: 28)
    }

    private var galleryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(themeSkinManager.products) { product in
                    ThemeSkinGalleryPreviewTile(
                        product: product,
                        isActive: themeSkinManager.isActiveTheme(product.themeId)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var themeProductList: some View {
        VStack(spacing: 14) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text("购买说明")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)

            ThemeSkinBulletRow(text: "购买后只能启用同一主题包内的组件，不会与其他主题皮肤混用。")
            ThemeSkinBulletRow(text: "每个组件支持单独启用或停用，未启用时回退系统默认样式。")
            ThemeSkinBulletRow(text: "若喵币不足，可直接从右上角进入喵币商店补充。")
        }
        .padding(18)
        .themeSkinSectionCard(cornerRadius: 24)
    }

    private var storeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    themeManager.backgroundColor.opacity(0.98),
                    Color(hex: "FFF7ED").opacity(0.58),
                    Color(hex: "F1ECFF").opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(themeManager.cardTintColor.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 44)
                .offset(x: -150, y: -230)

            Circle()
                .fill(Color(hex: "DAD4FF").opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 54)
                .offset(x: 145, y: 280)
        }
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
    @Environment(\.colorScheme) private var colorScheme

    private var displayPrice: Int { quote?.finalPrice ?? product.basePrice }
    private var previewAssetName: String { product.previewAssetNames.first ?? ThemeSkinAssetName.previewStoreHero }
    private var canAfford: Bool { currentBalance >= displayPrice }
    private var descriptor: ThemeSkinDescriptor? {
        ThemeSkinManager.shared.descriptor(forThemeId: product.themeId, slot: .sectionCard)
    }
    private var primaryTextColor: Color {
        SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme)
    }
    private var secondaryTextColor: Color {
        primaryTextColor.opacity(0.76)
    }

    private var componentSummaryTags: [String] {
        var tags: [String] = []
        if product.supportedSlots.contains(where: { [.topBarMain, .topBarSegment, .topBarIconButton, .topBarAddButton, .searchBar].contains($0) }) {
            tags.append("顶栏")
        }
        if product.supportedSlots.contains(where: { [.tabBarMain, .tabBarItem].contains($0) }) {
            tags.append("底栏")
        }
        if product.supportedSlots.contains(where: { [.statsCard, .wardrobeItemCard, .settingsGridCard, .sectionCard].contains($0) }) {
            tags.append("卡片")
        }
        if product.supportedSlots.contains(where: { [.primaryButton, .iconCircleButton, .segmentedControl, .filterChip, .discountBadge].contains($0) }) {
            tags.append("按钮")
        }
        if product.supportedSlots.contains(where: { [.filterSheet, .emptyState].contains($0) }) {
            tags.append("空态")
        }
        return tags
    }

    private var componentCaption: String {
        guard !componentSummaryTags.isEmpty else {
            return "\(product.supportedSlots.count) 项组件可单独开关"
        }
        return "覆盖 \(componentSummaryTags.joined(separator: " · ")) · \(product.supportedSlots.count) 项组件"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                previewArtwork

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(product.name)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(primaryTextColor)
                            .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: descriptor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        ThemeSkinStatusBadge(isPurchased: isPurchased, isActive: isActive, descriptor: descriptor)
                    }

                    Text(product.subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(secondaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    priceLine

                    componentSummary
                }
            }

            if isPurchased {
                ownershipLine
                purchasedActionRow
            } else {
                purchaseActionRow
            }
        }
        .padding(16)
        .themeSkinSectionCard(cornerRadius: 28)
    }

    private var previewArtwork: some View {
        ThemeSkinOptionalFittedAsset(
            previewAssetName,
            namespace: product.assetNamespace,
            allowShortNameFallback: false
        ) {
            ThemeSkinProductPreviewFallback(product: product)
        }
        .frame(width: 96, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        }
        .shadow(color: themeManager.cardTintColor.opacity(0.10), radius: 10, x: 0, y: 5)
    }

    private var priceLine: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text("\(displayPrice)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(primaryTextColor)
                .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: descriptor)
            Text("喵币")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
            if displayPrice < product.basePrice {
                Text("原价 \(product.basePrice)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryTextColor.opacity(0.82))
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
                    .strikethrough()
            }
        }
    }

    private var componentSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.accentTextColor.opacity(0.78))
            Text(componentCaption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.46), in: Capsule())
    }

    private var ownershipLine: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? Color(hex: "A98654") : Color(hex: "62A871"))
            Text(isActive ? "正在使用 · 可在详情里微调组件" : "已收入皮肤库 · 可随时应用")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var purchaseActionRow: some View {
        HStack(spacing: 10) {
            Button(action: purchaseAction) {
                ThemeSkinActionLabel(
                    title: canAfford ? "购买并应用" : "补充喵币",
                    subtitle: canAfford ? "\(displayPrice) 喵币 · VIP 9 折" : "当前 \(currentBalance)，还差 \(max(0, displayPrice - currentBalance))",
                    systemImage: canAfford ? "bag.fill" : "pawprint.fill"
                )
            }
            .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: Color(hex: "D9A66A"), cornerRadius: 18, verticalPadding: 0))

            detailLink(title: "预览")
                .frame(width: 86)
        }
    }

    private var purchasedActionRow: some View {
        HStack(spacing: 10) {
            Button(action: toggleAction) {
                ThemeSkinMiniActionLabel(
                    title: isActive ? "停用当前" : "应用这套",
                    systemImage: isActive ? "power.circle.fill" : "wand.and.stars",
                    tint: primaryTextColor,
                    descriptor: descriptor
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themeManager.cardTintColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            detailLink(title: "组件细调")
                .frame(maxWidth: .infinity)
        }
    }

    private func detailLink(title: String) -> some View {
        NavigationLink {
            ThemeSkinDetailView(themeId: product.themeId)
        } label: {
            ThemeSkinMiniActionLabel(
                title: title,
                systemImage: "arrow.right.circle.fill",
                tint: SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme),
                descriptor: descriptor
            )
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ThemeSkinStatusBadge: View {
    let isPurchased: Bool
    let isActive: Bool
    let descriptor: ThemeSkinDescriptor?

    var body: some View {
        Text(isActive ? "使用中" : (isPurchased ? "已购" : "未购"))
            .font(.caption.weight(.bold))
            .foregroundStyle(isActive ? Color(hex: "9C6B4A") : (isPurchased ? Color(hex: "4F9B63") : Color(hex: "A78292")))
            .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: descriptor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(isActive ? 0.82 : 0.56))
            )
            .overlay(
                Capsule()
                    .stroke((isActive ? Color(hex: "E6C894") : Color.white).opacity(0.62), lineWidth: 1)
            )
    }
}

private struct ThemeSkinBalancePill: View {
    let balance: Int
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Label("余额", systemImage: "pawprint.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.accentTextColor)
                .themeSkinLegibleText(level: .chip, slot: .sectionCard)

            Text("\(balance)")
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .chip, slot: .sectionCard)

            Text("喵币可用")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.68), lineWidth: 1)
        )
    }
}

private struct ThemeSkinGalleryPreviewTile: View {
    let product: ThemeSkinProduct
    let isActive: Bool
    @Environment(ThemeManager.self) private var themeManager

    private var previewAssetName: String {
        product.previewAssetNames.first ?? ThemeSkinAssetName.previewStoreHero
    }

    private var descriptor: ThemeSkinDescriptor? {
        ThemeSkinManager.shared.descriptor(forThemeId: product.themeId, slot: .sectionCard)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ThemeSkinOptionalFittedAsset(
                previewAssetName,
                namespace: product.assetNamespace,
                allowShortNameFallback: false
            ) {
                ThemeSkinProductPreviewFallback(product: product)
            }
            .frame(width: 120, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.24)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(product.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .themeSkinLegibleText(level: .badge, slot: .sectionCard, descriptor: descriptor)
                .themeSkinLegibilityBackdrop(level: .preview, slot: .sectionCard, cornerRadius: 8, descriptor: descriptor)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)

            if isActive {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "F6D78E"))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: 120, height: 72)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isActive ? Color(hex: "F6D78E").opacity(0.82) : Color.white.opacity(0.68), lineWidth: isActive ? 1.4 : 1)
        }
        .shadow(color: themeManager.cardTintColor.opacity(isActive ? 0.16 : 0.08), radius: 10, x: 0, y: 5)
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
            .themeSkinLegibleText(level: .chip, slot: .sectionCard)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
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
                    .foregroundStyle(Color.white.opacity(0.74))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ThemeSkinMiniActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary
    var descriptor: ThemeSkinDescriptor? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(tint)
        .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: descriptor)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
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
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ThemeSkinProductPreviewFallback: View {
    let product: ThemeSkinProduct

    private var descriptor: ThemeSkinDescriptor? {
        ThemeSkinManager.shared.descriptor(forThemeId: product.themeId, slot: .sectionCard)
    }

    private var isSwanDream: Bool {
        product.assetNamespace == SwanDreamThemeSkin.namespace
    }

    private var decorAssetName: String {
        isSwanDream ? SwanDreamThemeSkin.decorCrownedSwanClouds : SkyConcertThemeSkin.decorMoonStarClouds
    }

    private var gradientColors: [Color] {
        if isSwanDream {
            return [
                SwanDreamThemeSkin.creamTop.opacity(0.96),
                SwanDreamThemeSkin.ribbonPink.opacity(0.52),
                SwanDreamThemeSkin.moonLavender.opacity(0.82)
            ]
        }
        return [
            SkyConcertThemeSkin.creamTop.opacity(0.96),
            SkyConcertThemeSkin.cloudBlue.opacity(0.68),
            SkyConcertThemeSkin.blush.opacity(0.42)
        ]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ThemeSkinOptionalFittedAsset(
                decorAssetName,
                namespace: product.assetNamespace,
                allowShortNameFallback: false
            ) {
                Image(systemName: isSwanDream ? "moon.stars.fill" : "music.note")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle((isSwanDream ? SwanDreamThemeSkin.moonGold : SkyConcertThemeSkin.softGold).opacity(0.72))
            }
            .frame(width: 72, height: 72)
            .opacity(0.82)

            VStack {
                Spacer()
                Text(product.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSwanDream ? SwanDreamThemeSkin.text : SkyConcertThemeSkin.text)
                    .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: descriptor)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.56), in: Capsule())
                    .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ThemeSkinStoreView()
            .environment(ThemeManager.shared)
    }
}
