import SwiftUI

struct ThemeSkinDetailView: View {
    let themeId: String

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var actionMessage = ""
    @State private var showActionAlert = false
    @State private var previewMode: ThemeSkinPreviewMode = .theme
    @State private var previewScene: ThemeSkinPreviewScene = .wardrobe
    @State private var focusedSlot: ThemeSkinSlot?

    private var product: ThemeSkinProduct? {
        themeSkinManager.product(for: themeId)
    }

    private var isPurchased: Bool {
        themeSkinManager.isPurchased(themeId)
    }

    private var isActive: Bool {
        themeSkinManager.isActiveTheme(themeId)
    }

    private var previewEnabledSlots: Set<ThemeSkinSlot> {
        guard let product else { return [] }
        let sourceSlots = isActive ? themeSkinManager.currentEnabledSlots : Set(product.defaultEnabledSlots)
        return sourceSlots.intersection(Set(product.supportedSlots))
    }

    private var sectionDescriptor: ThemeSkinDescriptor? {
        guard let product else { return nil }
        return themeSkinManager.descriptor(forThemeId: product.themeId, slot: .sectionCard)
    }

    private var sectionPrimaryTextColor: Color {
        guard let sectionDescriptor else { return themeManager.primaryTextColor }
        return SkyConcertThemeSkin.labelColor(for: sectionDescriptor, colorScheme: colorScheme)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    if let product {
                        ThemeSkinDetailPreviewPanel(
                            product: product,
                            isPurchased: isPurchased,
                            isActive: isActive,
                            enabledSlots: previewEnabledSlots,
                            mode: $previewMode,
                            scene: $previewScene,
                            focusedSlot: focusedSlot,
                            onPreviewSlotTap: { slot in
                                focus(slot, proxy: proxy, scrollToRow: true)
                            }
                        )
                    }

                    purchaseCard
                    if let product {
                        ThemeSkinBackgroundStickerSelectionCard(product: product)
                    }

                    ThemeSkinSlotToggleSection(
                        themeId: themeId,
                        previewEnabledSlots: previewEnabledSlots,
                        focusedSlot: focusedSlot,
                        onFocusSlot: { slot in
                            focus(slot, proxy: proxy, scrollToRow: false)
                        }
                    )
                }
                .padding()
            }
            .background(LiquidBackground(themeSkinWallpaperContext: .themeDetail))
        }
        .navigationTitle(product?.name ?? "主题详情")
        .navigationBarTitleDisplayMode(.inline)
        .alert("主题操作", isPresented: $showActionAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(actionMessage)
        }
    }

    private var purchaseCard: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("购买与应用")
                    .font(.headline)
                    .foregroundStyle(sectionPrimaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: sectionDescriptor)

                if let product, let quote = themeSkinManager.priceQuote(for: themeId) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(quote.finalPrice)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(sectionPrimaryTextColor)
                            .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: sectionDescriptor)
                        Text("喵币")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: sectionDescriptor)
                        Text("原价 \(product.basePrice)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: sectionDescriptor)
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

    private func focus(_ slot: ThemeSkinSlot, proxy: ScrollViewProxy, scrollToRow: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            focusedSlot = slot
            previewMode = .theme
            previewScene = scene(for: slot)
        }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                if scrollToRow {
                    proxy.scrollTo(ThemeSkinSlotRowID.slot(slot), anchor: .center)
                } else {
                    proxy.scrollTo(ThemeSkinSlotRowID.previewCard, anchor: .top)
                }
            }
        }
    }

    private func scene(for slot: ThemeSkinSlot) -> ThemeSkinPreviewScene {
        switch ThemeSkinPreviewAnchor.anchor(for: slot) {
        case .searchBar, .tabBar, .statsCard, .wardrobeCard, .segmentedControl, .filterChip, .discountBadge:
            return .wardrobe
        case .filterSheet, .emptyState:
            return .settings
        case .topBar, .settingsGrid, .sectionCard, .primaryButton, .iconButton:
            return .me
        }
    }

    private func present(_ message: String) {
        actionMessage = message
        showActionAlert = true
    }
}
