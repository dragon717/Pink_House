import SwiftUI

struct ThemeSkinDetailPreviewPanel: View {
    let product: ThemeSkinProduct
    let isPurchased: Bool
    let isActive: Bool
    let enabledSlots: Set<ThemeSkinSlot>
    @Binding var mode: ThemeSkinPreviewMode
    @Binding var scene: ThemeSkinPreviewScene
    let focusedSlot: ThemeSkinSlot?
    let onPreviewSlotTap: (ThemeSkinSlot) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var context: ThemeSkinPreviewContext {
        ThemeSkinPreviewContext(product: product, mode: mode, enabledSlots: enabledSlots)
    }

    private var highlightedAnchor: ThemeSkinPreviewAnchor? {
        focusedSlot.map(ThemeSkinPreviewAnchor.anchor(for:))
    }

    private var noticeDescriptor: ThemeSkinDescriptor? {
        context.representativeDescriptor
            ?? ThemeSkinManager.shared.descriptor(forThemeId: product.themeId, slot: .sectionCard)
    }

    var body: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                header
                previewModePicker
                phonePreview
                sceneSwitcher
                helperLine
                themePriorityNotice
            }
            .padding(18)
        }
        .id(ThemeSkinSlotRowID.previewCard)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(product.localizedName)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(themeManager.primaryTextColor)
                Text(product.localizedSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(isActive ? "使用中".appLocalized : (isPurchased ? "已拥有".appLocalized : "预览中".appLocalized))
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? Color(hex: "FF5C93") : themeManager.accentTextColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.72)))
        }
    }

    private var previewModePicker: some View {
        Picker("预览模式".appLocalized, selection: $mode) {
            ForEach(ThemeSkinPreviewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("默认与主题对照".appLocalized)
    }

    private var phonePreview: some View {
        ThemeSkinPreviewPhoneFrame(
            context: context,
            scene: scene,
            highlightedAnchor: highlightedAnchor,
            onPreviewSlotTap: onPreviewSlotTap
        )
        .frame(maxWidth: .infinity)
    }

    private var sceneSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(ThemeSkinPreviewScene.allCases) { previewScene in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        scene = previewScene
                    }
                } label: {
                    Text(previewScene.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scene == previewScene ? .white : themeManager.accentTextColor)
                        .themeSkinLegibleText(
                            level: scene == previewScene ? .chip : .inline,
                            slot: .topBarSegment,
                            descriptor: context.representativeDescriptor
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(scene == previewScene ? themeManager.cardTintColor.opacity(0.84) : Color.white.opacity(0.56))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var helperLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.accentTextColor)
            Text("点预览部位会跳到对应开关；点下方开关行会高亮这里的部位。".appLocalized)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var themePriorityNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "paintpalette.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(SkyConcertThemeSkin.accent(for: noticeDescriptor, colorScheme: colorScheme))
                .themeSkinLegibleSymbol(level: .chip, slot: .sectionCard, descriptor: noticeDescriptor)

            Text("启用主题皮肤后，文字、图标与背景层级会跟随当前主题；普通魔法配色与主题皮肤视觉互斥，不叠加。".appLocalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: noticeDescriptor, colorScheme: colorScheme).opacity(0.86))
                .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: noticeDescriptor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .themeSkinLegibilityBackdrop(level: .preview, slot: .sectionCard, cornerRadius: 14, descriptor: noticeDescriptor)
        .background(SkyConcertThemeSkin.shellFillTop(for: noticeDescriptor).opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SkyConcertThemeSkin.shellStroke(for: noticeDescriptor).opacity(0.34), lineWidth: 1)
        )
    }
}

private struct ThemeSkinPreviewPhoneFrame: View {
    let context: ThemeSkinPreviewContext
    let scene: ThemeSkinPreviewScene
    let highlightedAnchor: ThemeSkinPreviewAnchor?
    let onPreviewSlotTap: (ThemeSkinSlot) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color(hex: "2F3140"))
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(appBackground)
                .overlay(sceneContent)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(8)

            Capsule()
                .fill(Color.black.opacity(0.32))
                .frame(width: 70, height: 6)
                .offset(y: -202)
        }
        .frame(width: 244, height: 448)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主题实时预览".appLocalized)
    }

    private var sceneContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                ThemeSkinPreviewSceneContent(
                    context: context,
                    scene: scene,
                    highlightedAnchor: highlightedAnchor,
                    onPreviewSlotTap: onPreviewSlotTap
                )
                .padding(.horizontal, 14)
                .padding(.top, 24)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            ThemeSkinPreviewHotspot(anchor: .tabBar, highlightedAnchor: highlightedAnchor) {
                onPreviewSlotTap(.tabBarMain)
            } content: {
                ThemeSkinPreviewTabBar(context: context)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
    }

    private var appBackground: LinearGradient {
        if let descriptor = context.representativeDescriptor {
            if colorScheme == .dark {
                switch descriptor.assetNamespace {
                case SwanDreamThemeSkin.namespace:
                    return LinearGradient(colors: [Color(hex: "191523"), Color(hex: "2A2038"), Color(hex: "21182E")], startPoint: .top, endPoint: .bottom)
                case SkyConcertThemeSkin.namespace:
                    return LinearGradient(colors: [Color(hex: "111D2A"), Color(hex: "1B3141"), Color(hex: "221A2C")], startPoint: .top, endPoint: .bottom)
                default:
                    break
                }
            }

            return LinearGradient(
                colors: [
                    SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.98),
                    SkyConcertThemeSkin.shellFillBottom(for: descriptor).opacity(0.82),
                    Color.white.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if colorScheme == .dark {
            return LinearGradient(
                colors: [Color(hex: "181722"), Color(hex: "211923")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [themeManager.cardBackgroundColor.opacity(0.96), Color.white.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct ThemeSkinPreviewSceneContent: View {
    let context: ThemeSkinPreviewContext
    let scene: ThemeSkinPreviewScene
    let highlightedAnchor: ThemeSkinPreviewAnchor?
    let onPreviewSlotTap: (ThemeSkinSlot) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ThemeSkinPreviewHotspot(anchor: .topBar, highlightedAnchor: highlightedAnchor) {
                onPreviewSlotTap(.topBarMain)
            } content: {
                ThemeSkinPreviewTopBar(context: context, title: scene.title)
            }

            switch scene {
            case .me:
                meScene
            case .wardrobe:
                wardrobeScene
            case .settings:
                settingsScene
            }
        }
    }

    private var meScene: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ThemeSkinPreviewHotspot(anchor: .sectionCard, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.sectionCard) } content: {
                    ThemeSkinPreviewSectionCard(context: context, title: "会员", subtitle: "今日装扮 6 件")
                }
                ThemeSkinPreviewHotspot(anchor: .iconButton, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.iconCircleButton) } content: {
                    ThemeSkinPreviewRoundButton(context: context, label: "♡")
                }
            }
            ThemeSkinPreviewHotspot(anchor: .settingsGrid, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.settingsGridCard) } content: {
                ThemeSkinPreviewSettingsGrid(context: context)
            }
            ThemeSkinPreviewHotspot(anchor: .primaryButton, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.primaryButton) } content: {
                ThemeSkinPreviewPrimaryButton(context: context, title: "应用这套主题")
            }
        }
    }

    private var wardrobeScene: some View {
        VStack(spacing: 12) {
            ThemeSkinPreviewHotspot(anchor: .searchBar, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.searchBar) } content: {
                ThemeSkinPreviewSearchBar(context: context)
            }
            ThemeSkinPreviewHotspot(anchor: .segmentedControl, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.segmentedControl) } content: {
                ThemeSkinPreviewSegmentedControl(context: context)
            }
            ThemeSkinPreviewHotspot(anchor: .statsCard, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.statsCard) } content: {
                ThemeSkinPreviewStatsCard(context: context)
            }
            HStack(spacing: 10) {
                ThemeSkinPreviewHotspot(anchor: .wardrobeCard, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.wardrobeItemCard) } content: {
                    ThemeSkinPreviewWardrobeCard(context: context, title: "云朵裙")
                }
                ThemeSkinPreviewHotspot(anchor: .discountBadge, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.discountBadge) } content: {
                    ThemeSkinPreviewDiscountBadge(context: context)
                }
            }
            ThemeSkinPreviewHotspot(anchor: .filterChip, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.filterChip) } content: {
                HStack(spacing: 6) {
                    ThemeSkinPreviewFilterChip(context: context, title: "粉色")
                    ThemeSkinPreviewFilterChip(context: context, title: "收藏")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var settingsScene: some View {
        VStack(spacing: 12) {
            ThemeSkinPreviewHotspot(anchor: .filterSheet, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.filterSheet) } content: {
                ThemeSkinPreviewFilterSheet(context: context)
            }
            ThemeSkinPreviewHotspot(anchor: .emptyState, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.emptyState) } content: {
                ThemeSkinPreviewEmptyState(context: context)
            }
            ThemeSkinPreviewHotspot(anchor: .sectionCard, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.sectionCard) } content: {
                ThemeSkinPreviewSectionCard(context: context, title: "组件说明", subtitle: "开关只影响当前主题")
            }
            ThemeSkinPreviewHotspot(anchor: .primaryButton, highlightedAnchor: highlightedAnchor) { onPreviewSlotTap(.primaryButton) } content: {
                ThemeSkinPreviewPrimaryButton(context: context, title: "保存设置")
            }
        }
    }
}

private struct ThemeSkinPreviewHotspot<Content: View>: View {
    let anchor: ThemeSkinPreviewAnchor
    let highlightedAnchor: ThemeSkinPreviewAnchor?
    let action: () -> Void
    let content: Content
    @State private var pulse = false

    init(anchor: ThemeSkinPreviewAnchor, highlightedAnchor: ThemeSkinPreviewAnchor?, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.highlightedAnchor = highlightedAnchor
        self.action = action
        self.content = content()
    }

    private var isHighlighted: Bool { highlightedAnchor == anchor }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: "FF6FA1"), lineWidth: 2)
                    .scaleEffect(pulse ? 1.045 : 1)
                    .opacity(pulse ? 0.38 : 0.96)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { restartPulseIfNeeded() }
        .onChange(of: highlightedAnchor?.rawValue) { _, _ in restartPulseIfNeeded() }
        .accessibilityLabel(anchor.title)
        .accessibilityHint("点按跳到对应组件开关".appLocalized)
    }

    private func restartPulseIfNeeded() {
        guard isHighlighted else {
            pulse = false
            return
        }
        pulse = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.55).repeatCount(2, autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ThemeSkinPreviewTopBar: View {
    let context: ThemeSkinPreviewContext
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .topBarMain) }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.appLocalized)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                .themeSkinLegibleText(level: .inline, slot: .topBarMain, descriptor: descriptor)
            Spacer(minLength: 0)
            ThemeSkinPreviewRoundButton(context: context, label: "＋", size: 28, slot: .topBarAddButton)
            ThemeSkinPreviewRoundButton(context: context, label: "⋯", size: 28, slot: .topBarIconButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .themeSkinLegibilityBackdrop(level: .preview, slot: .topBarMain, cornerRadius: 13, descriptor: descriptor)
        .background(previewAsset(ThemeSkinAssetName.topBarMain, context: context, slot: .topBarMain, cornerRadius: 18))
    }
}

private struct ThemeSkinPreviewSearchBar: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .searchBar) }

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(0.42)).frame(width: 10, height: 10)
            Text("搜索衣物 / 主题".appLocalized)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.72))
                .themeSkinLegibleText(level: .inline, slot: .searchBar, descriptor: descriptor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .themeSkinLegibilityBackdrop(level: .preview, slot: .searchBar, cornerRadius: 12, descriptor: descriptor)
        .background(previewAsset(ThemeSkinAssetName.searchBarCompact, context: context, slot: .searchBar, cornerRadius: 16))
    }
}

private struct ThemeSkinPreviewTabBar: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .tabBarMain) }

    var body: some View {
        HStack(spacing: 8) {
            tab("衣", selected: false)
            tab("屋", selected: true)
            tab("我", selected: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .themeSkinLegibilityBackdrop(level: .preview, slot: .tabBarMain, cornerRadius: 18, descriptor: descriptor)
        .background(previewAsset(ThemeSkinAssetName.tabBarMain, context: context, slot: .tabBarMain, cornerRadius: 24))
    }

    private func tab(_ title: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(selected ? SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme) : SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.24))
                .frame(width: 15, height: 15)
            Text(title.appLocalized)
                .font(.system(size: 9, weight: selected ? .bold : .medium, design: .rounded))
                .foregroundStyle(selected ? SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme) : SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.72))
                .themeSkinLegibleText(level: selected ? .chip : .inline, slot: .tabBarMain, descriptor: descriptor)
        }
        .frame(maxWidth: .infinity)
    }
}
