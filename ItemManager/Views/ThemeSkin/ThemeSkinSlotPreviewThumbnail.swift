import SwiftUI

struct ThemeSkinSlotPreviewThumbnail: View {
    let product: ThemeSkinProduct
    let slot: ThemeSkinSlot
    let enabledSlots: Set<ThemeSkinSlot>
    var isFocused: Bool = false
    var size: CGFloat = 42

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var context: ThemeSkinPreviewContext {
        ThemeSkinPreviewContext(product: product, mode: .theme, enabledSlots: enabledSlots)
    }

    private var descriptor: ThemeSkinDescriptor? {
        context.descriptor(for: slot)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(shellFill)

            thumbnailContent
                .padding(5)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused ? 1.7 : 1)
        }
        .frame(width: size, height: size)
        .shadow(color: shadowColor, radius: isFocused ? 6 : 3, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        switch slot {
        case .topBarMain:
            miniTopBar
        case .topBarSegment:
            miniSegmented
        case .topBarIconButton, .topBarAddButton, .iconCircleButton:
            miniIconButton(label: slot == .topBarAddButton ? "+" : "•")
        case .searchBar:
            miniSearchBar
        case .tabBarMain:
            miniTabBar(showSelected: false)
        case .tabBarItem:
            miniTabBar(showSelected: true)
        case .segmentedControl:
            miniSegmented
        case .filterChip:
            miniFilterChip
        case .statsCard:
            miniStatsCard
        case .wardrobeItemCard:
            miniWardrobeCard
        case .settingsGridCard:
            miniSettingsGrid
        case .sectionCard:
            miniSectionCard
        case .primaryButton:
            miniPrimaryButton
        case .discountBadge:
            miniDiscountBadge
        case .filterSheet:
            miniFilterSheet
        case .emptyState:
            miniEmptyState
        }
    }

    private var miniTopBar: some View {
        optionalResizableAsset(ThemeSkinAssetName.topBarMain) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themedGradient)
        }
        .frame(height: 15)
        .overlay(alignment: .leading) {
            Circle().fill(accentColor).frame(width: 5, height: 5).padding(.leading, 5)
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 3) {
                Circle().fill(accentColor.opacity(0.65)).frame(width: 4, height: 4)
                Circle().fill(accentColor).frame(width: 4, height: 4)
            }
            .padding(.trailing, 5)
        }
    }

    private var miniSearchBar: some View {
        optionalResizableAsset(ThemeSkinAssetName.searchBarCompact) {
            Capsule().fill(themedGradient)
        }
        .frame(height: 13)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(labelColor.opacity(0.35))
                .frame(width: 15, height: 3)
                .padding(.leading, 8)
        }
    }

    private var miniSegmented: some View {
        HStack(spacing: 2) {
            Capsule().fill(accentColor.opacity(0.85))
            Capsule().fill(Color.white.opacity(0.72))
        }
        .padding(3)
        .background(
            optionalResizableAsset(ThemeSkinAssetName.topBarSegment) {
                Capsule().fill(themedGradient)
            }
        )
        .frame(height: 17)
    }

    private func miniIconButton(label: String) -> some View {
        Text(label)
            .font(.system(size: label == "+" ? 16 : 18, weight: .heavy, design: .rounded))
            .foregroundStyle(accentColor)
            .frame(width: 22, height: 22)
            .background(Circle().fill(SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.96)))
            .overlay(Circle().stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.88), lineWidth: 1))
    }

    private func miniTabBar(showSelected: Bool) -> some View {
        optionalResizableAsset(showSelected ? ThemeSkinAssetName.tabBarItemSelected : ThemeSkinAssetName.tabBarMain) {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(themedGradient)
        }
        .frame(height: 18)
        .overlay {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 1 || showSelected ? accentColor : labelColor.opacity(0.25))
                        .frame(width: index == 1 || showSelected ? 5 : 4, height: index == 1 || showSelected ? 5 : 4)
                }
            }
        }
    }

    private var miniStatsCard: some View {
        cardAsset(ThemeSkinAssetName.cardStatsDefault, cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(labelColor.opacity(0.28)).frame(width: 18, height: 3)
                HStack(spacing: 3) {
                    Capsule().fill(accentColor.opacity(0.9)).frame(width: 7, height: 12)
                    Capsule().fill(accentColor.opacity(0.55)).frame(width: 7, height: 8)
                    Capsule().fill(accentColor.opacity(0.35)).frame(width: 7, height: 10)
                }
            }
        }
    }

    private var miniWardrobeCard: some View {
        cardAsset(ThemeSkinAssetName.cardWardrobeItem, cornerRadius: 10) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 5).fill(accentColor.opacity(0.24)).frame(height: 14)
                Capsule().fill(labelColor.opacity(0.28)).frame(height: 3)
            }
            .overlay(alignment: .topLeading) {
                optionalFittedAsset(ThemeSkinAssetName.cardWardrobeRibbonTopLeft) {
                    Circle().fill(accentColor.opacity(0.72))
                }
                .frame(width: 13, height: 10)
                .offset(x: -3, y: -3)
            }
        }
    }

    private var miniSettingsGrid: some View {
        cardAsset(ThemeSkinAssetName.cardSettingsGrid, cornerRadius: 9) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 2), spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == 0 ? accentColor.opacity(0.52) : Color.white.opacity(0.72))
                }
            }
        }
    }

    private var miniSectionCard: some View { miniCardLines(cornerRadius: 9) }
    private var miniFilterSheet: some View { miniCardLines(cornerRadius: 12).frame(height: 28) }

    private var miniPrimaryButton: some View {
        Capsule()
            .fill(LinearGradient(colors: [accentColor.opacity(0.95), labelColor.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 18)
            .overlay(Capsule().fill(Color.white.opacity(0.35)).frame(width: 16, height: 3))
    }

    private var miniFilterChip: some View {
        HStack(spacing: 4) {
            Circle().fill(accentColor).frame(width: 5, height: 5)
            Capsule().fill(labelColor.opacity(0.34)).frame(width: 15, height: 3)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Capsule().fill(SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.92)))
        .overlay(Capsule().stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.72), lineWidth: 1))
    }

    private var miniDiscountBadge: some View {
        Text("9")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .themeSkinLegibleText(level: .inline, slot: .discountBadge, descriptor: descriptor)
            .frame(width: 24, height: 18)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accentColor.opacity(0.92)))
            .rotationEffect(.degrees(-7))
    }

    private var miniEmptyState: some View {
        VStack(spacing: 4) {
            Circle().fill(accentColor.opacity(0.24)).frame(width: 13, height: 13)
            Capsule().fill(labelColor.opacity(0.25)).frame(width: 23, height: 3)
            Capsule().fill(labelColor.opacity(0.16)).frame(width: 16, height: 3)
        }
    }

    private func cardAsset<Content: View>(_ name: String, cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            optionalResizableAsset(name) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(themedGradient)
            }
            content().padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func miniCardLines(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(themedGradient)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(accentColor.opacity(0.42)).frame(width: 20, height: 4)
                    Capsule().fill(labelColor.opacity(0.22)).frame(width: 26, height: 3)
                }
                .padding(.leading, 7)
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.62), lineWidth: 1))
    }

    @ViewBuilder
    private func optionalResizableAsset<Placeholder: View>(_ name: String, @ViewBuilder placeholder: @escaping () -> Placeholder) -> some View {
        if let descriptor {
            ThemeSkinOptionalResizableAsset(
                name,
                namespace: descriptor.assetNamespace,
                allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor),
                capInsets: ThemeSkinAssetName.capInsets(for: name)
            ) {
                placeholder()
            }
        } else {
            placeholder()
        }
    }

    @ViewBuilder
    private func optionalFittedAsset<Placeholder: View>(_ name: String, @ViewBuilder placeholder: @escaping () -> Placeholder) -> some View {
        if let descriptor {
            ThemeSkinOptionalFittedAsset(
                name,
                namespace: descriptor.assetNamespace,
                allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
            ) {
                placeholder()
            }
        } else {
            placeholder()
        }
    }

    private var shellFill: Color {
        context.isThemed(slot) ? SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.82) : themeManager.cardBackgroundColor.opacity(0.68)
    }

    private var themedGradient: LinearGradient {
        LinearGradient(
            colors: [SkyConcertThemeSkin.shellFillTop(for: descriptor), SkyConcertThemeSkin.shellFillBottom(for: descriptor)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accentColor: Color { SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme) }
    private var labelColor: Color { SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme) }

    private var borderColor: Color {
        isFocused ? accentColor.opacity(0.9) : SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(context.isThemed(slot) ? 0.72 : 0.28)
    }

    private var shadowColor: Color {
        (context.isThemed(slot) ? SkyConcertThemeSkin.shadowColor(for: descriptor) : Color.black.opacity(0.05)).opacity(isFocused ? 0.55 : 0.28)
    }
}
