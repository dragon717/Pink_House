import SwiftUI

struct FeatureGuideMenuOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private let rowHeight: CGFloat = 44
    private let dividerHeight: CGFloat = 8

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        GeometryReader { geometry in
            if let state = guideManager.guideMenuPresentationState,
               let menuFrame = menuFrame(for: state, in: geometry) {
                let highlightedIndex = highlightedActionIndex(in: state.items)

                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            switch item.kind {
                            case .divider:
                                Divider()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            case .action:
                                Button {
                                    let action = item.action
                                    guideManager.dismissGuideMenu()
                                    action?()
                                } label: {
                                    HStack(spacing: 12) {
                                        if let systemImage = item.systemImage {
                                            Image(systemName: systemImage)
                                                .font(.system(size: 15, weight: .medium))
                                                .frame(width: 18, height: 18)
                                        }

                                        Text(item.title.appLocalized)
                                            .font(.system(size: 16))
                                            .lineLimit(1)

                                        Spacer(minLength: 8)

                                        if item.showsChevron {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(magicPalette.secondaryText.opacity(0.9))
                                        }
                                    }
                                    .foregroundStyle(
                                        item.isDestructive
                                            ? AnyShapeStyle(Color.red)
                                            : AnyShapeStyle(magicPalette.primaryText)
                                    )
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(item.isHighlighted ? magicPalette.accent.opacity(0.14) : Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        item.isHighlighted ? Color.white.opacity(0.88) : Color.clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    )
                                    .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                .frame(height: rowHeight)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: state.width, height: menuHeight(for: state.items), alignment: .top)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
                    .captureGuideInteractionRegion("guide.menu.overlay.\(state.scenario.rawValue)")

                    if let highlightedIndex,
                       let pawPosition = catPawPosition(for: highlightedIndex, items: state.items, menuFrame: menuFrame) {
                        CatPawTapAnimation(position: pawPosition, delay: 0.35)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: menuFrame.width, height: menuFrame.height)
                .position(x: menuFrame.midX, y: menuFrame.midY)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(guideManager.guideMenuPresentationState != nil)
    }

    private func menuFrame(
        for state: GuideMenuPresentationState,
        in geometry: GeometryProxy
    ) -> CGRect? {
        guard let globalAnchorFrame = guideManager.guideTargetFrame(for: state.anchorKey) else { return nil }
        let origin = geometry.frame(in: .global).origin
        let anchorFrame = CGRect(
            x: globalAnchorFrame.minX - origin.x,
            y: globalAnchorFrame.minY - origin.y,
            width: globalAnchorFrame.width,
            height: globalAnchorFrame.height
        )

        let menuWidth = state.width
        let menuHeight = menuHeight(for: state.items)
        let inset: CGFloat = 12
        let cascadeOffset = CGFloat(state.submenuDepth) * (menuWidth - 28)
        let rawX = anchorFrame.maxX - menuWidth - cascadeOffset + 6
        let x = min(max(rawX, inset), geometry.size.width - menuWidth - inset)
        let y = min(
            max(anchorFrame.maxY + 8, geometry.safeAreaInsets.top + 8),
            geometry.size.height - menuHeight - max(geometry.safeAreaInsets.bottom, inset) - inset
        )

        return CGRect(x: x, y: y, width: menuWidth, height: menuHeight)
    }

    private func menuHeight(for items: [GuideMenuItem]) -> CGFloat {
        let contentHeight = items.reduce(CGFloat.zero) { partialResult, item in
            partialResult + (item.kind == .divider ? dividerHeight : rowHeight)
        }
        return contentHeight + 16
    }

    private func highlightedActionIndex(in items: [GuideMenuItem]) -> Int? {
        items.firstIndex { $0.kind == .action && $0.isHighlighted }
    }

    private func catPawPosition(
        for highlightedIndex: Int,
        items: [GuideMenuItem],
        menuFrame: CGRect
    ) -> CGPoint? {
        var currentY = menuFrame.minY + 8

        for (index, item) in items.enumerated() {
            let itemHeight = item.kind == .divider ? dividerHeight : rowHeight
            if index == highlightedIndex, item.kind == .action {
                return CGPoint(
                    x: menuFrame.maxX - 26,
                    y: currentY + itemHeight / 2
                )
            }
            currentY += itemHeight
        }

        return nil
    }
}
