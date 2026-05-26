import SwiftUI

struct ThemeSkinPreviewRoundButton: View {
    let context: ThemeSkinPreviewContext
    let label: String
    var size: CGFloat = 42
    var slot: ThemeSkinSlot = .iconCircleButton

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: slot) }

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme))
            .themeSkinLegibleSymbol(level: .badge, slot: slot, descriptor: descriptor)
            .frame(width: size, height: size)
            .background(Circle().fill(SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.96)))
            .overlay(Circle().stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.86), lineWidth: 1))
            .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(context.isThemed(slot) ? 0.45 : 0.16), radius: 5, x: 0, y: 2)
    }
}

struct ThemeSkinPreviewSettingsGrid: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .settingsGridCard) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(["衣橱", "手帐", "财富", "主题"], id: \.self) { title in
                VStack(alignment: .leading, spacing: 8) {
                    Circle()
                        .fill(SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(0.26))
                        .frame(width: 22, height: 22)
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                        .themeSkinLegibleText(level: .inline, slot: .settingsGridCard, descriptor: descriptor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(previewAsset(ThemeSkinAssetName.cardSettingsGrid, context: context, slot: .settingsGridCard, cornerRadius: 16))
            }
        }
    }
}

struct ThemeSkinPreviewSectionCard: View {
    let context: ThemeSkinPreviewContext
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .sectionCard) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.66))
                .themeSkinLegibleText(level: .inline, slot: .sectionCard, descriptor: descriptor)
                .lineLimit(2)
        }
        .themeSkinLegibilityBackdrop(level: .preview, slot: .sectionCard, cornerRadius: 12, descriptor: descriptor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(previewFallbackSurface(context: context, slot: .sectionCard, cornerRadius: 18))
    }
}

struct ThemeSkinPreviewStatsCard: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .statsCard) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("衣橱统计")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                    .themeSkinLegibleText(level: .inline, slot: .statsCard, descriptor: descriptor)
                Text("128 件 · 24 套穿搭")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.65))
                    .themeSkinLegibleText(level: .inline, slot: .statsCard, descriptor: descriptor)
            }
            .themeSkinLegibilityBackdrop(level: .preview, slot: .statsCard, cornerRadius: 12, descriptor: descriptor)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 4) {
                bar(height: 20, opacity: 0.94)
                bar(height: 32, opacity: 0.68)
                bar(height: 25, opacity: 0.48)
            }
        }
        .padding(12)
        .background(previewAsset(ThemeSkinAssetName.cardStatsDefault, context: context, slot: .statsCard, cornerRadius: 20))
    }

    private func bar(height: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(opacity))
            .frame(width: 9, height: height)
    }
}

struct ThemeSkinPreviewWardrobeCard: View {
    let context: ThemeSkinPreviewContext
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .wardrobeItemCard) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(0.72))
                .frame(height: 58)
                .overlay(alignment: .topLeading) { ribbon }
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: descriptor)
            Text("今日推荐")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.58))
                .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: descriptor)
        }
        .padding(10)
        .background(previewAsset(ThemeSkinAssetName.cardWardrobeItem, context: context, slot: .wardrobeItemCard, cornerRadius: 18))
    }

    @ViewBuilder
    private var ribbon: some View {
        if let descriptor {
            ThemeSkinOptionalFittedAsset(
                ThemeSkinAssetName.cardWardrobeRibbonTopLeft,
                namespace: descriptor.assetNamespace,
                allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
            ) {
                Circle().fill(SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(0.72))
            }
            .frame(width: 34, height: 24)
            .offset(x: -5, y: -5)
        } else {
            Circle()
                .fill(SkyConcertThemeSkin.accent(for: nil, colorScheme: colorScheme).opacity(0.48))
                .frame(width: 18, height: 18)
                .offset(x: -3, y: -3)
        }
    }
}

struct ThemeSkinPreviewPrimaryButton: View {
    let context: ThemeSkinPreviewContext
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .primaryButton) }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .themeSkinLegibleText(level: .badge, slot: .primaryButton, descriptor: descriptor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [
                        SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(0.94),
                        SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.45), lineWidth: 1))
    }
}

struct ThemeSkinPreviewSegmentedControl: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .segmentedControl) ?? context.descriptor(for: .topBarSegment) }

    var body: some View {
        HStack(spacing: 4) {
            segment("全部", selected: true)
            segment("收藏", selected: false)
            segment("最近", selected: false)
        }
        .padding(4)
        .background(previewAsset(ThemeSkinAssetName.topBarSegment, context: context, slot: .segmentedControl, cornerRadius: 18))
    }

    private func segment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(selected ? .white : SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.78))
            .themeSkinLegibleText(level: selected ? .chip : .inline, slot: .segmentedControl, descriptor: descriptor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(0.9) : Color.white.opacity(0.42)))
    }
}

struct ThemeSkinPreviewFilterChip: View {
    let context: ThemeSkinPreviewContext
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .filterChip) }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
            .themeSkinLegibleText(level: .chip, slot: .filterChip, descriptor: descriptor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.88)))
            .overlay(Capsule().stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.74), lineWidth: 1))
    }
}

struct ThemeSkinPreviewDiscountBadge: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .discountBadge) }

    var body: some View {
        VStack(spacing: 3) {
            Text("VIP")
                .font(.system(size: 9, weight: .black, design: .rounded))
            Text("9折")
                .font(.system(size: 13, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .themeSkinLegibleText(level: .badge, slot: .discountBadge, descriptor: descriptor)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme).opacity(0.92)))
        .rotationEffect(.degrees(-5))
        .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.38), radius: 6, x: 0, y: 3)
    }
}

struct ThemeSkinPreviewFilterSheet: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .filterSheet) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("筛选面板")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                .themeSkinLegibleText(level: .inline, slot: .filterSheet, descriptor: descriptor)
            HStack(spacing: 7) {
                ThemeSkinPreviewFilterChip(context: context, title: "上衣")
                ThemeSkinPreviewFilterChip(context: context, title: "裙子")
                Spacer(minLength: 0)
            }
        }
        .themeSkinLegibilityBackdrop(level: .preview, slot: .filterSheet, cornerRadius: 12, descriptor: descriptor)
        .padding(12)
        .background(previewFallbackSurface(context: context, slot: .filterSheet, cornerRadius: 20))
    }
}

struct ThemeSkinPreviewEmptyState: View {
    let context: ThemeSkinPreviewContext

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: ThemeSkinDescriptor? { context.descriptor(for: .emptyState) }

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(0.78))
                .frame(width: 38, height: 38)
                .overlay(Text("✨").font(.system(size: 16)))
            Text("这里还没有内容")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                .themeSkinLegibleText(level: .inline, slot: .emptyState, descriptor: descriptor)
            Text("主题空状态会保持温柔提示")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.62))
                .themeSkinLegibleText(level: .inline, slot: .emptyState, descriptor: descriptor)
        }
        .themeSkinLegibilityBackdrop(level: .preview, slot: .emptyState, cornerRadius: 14, descriptor: descriptor)
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(previewFallbackSurface(context: context, slot: .emptyState, cornerRadius: 22))
    }
}

@ViewBuilder
func previewAsset(_ name: String, context: ThemeSkinPreviewContext, slot: ThemeSkinSlot, cornerRadius: CGFloat) -> some View {
    let descriptor = context.descriptor(for: slot)
    if let descriptor {
        ThemeSkinOptionalResizableAsset(
            name,
            namespace: descriptor.assetNamespace,
            allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor),
            capInsets: ThemeSkinAssetName.capInsets(for: name)
        ) {
            previewFallbackSurface(context: context, slot: slot, cornerRadius: cornerRadius)
        }
    } else {
        previewFallbackSurface(context: context, slot: slot, cornerRadius: cornerRadius)
    }
}

func previewFallbackSurface(context: ThemeSkinPreviewContext, slot: ThemeSkinSlot, cornerRadius: CGFloat) -> some View {
    let descriptor = context.descriptor(for: slot)
    return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.98),
                    SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(context.isThemed(slot) ? 0.58 : 0.18),
                    SkyConcertThemeSkin.shellFillBottom(for: descriptor).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(context.isThemed(slot) ? 0.76 : 0.20), lineWidth: 1)
        )
}
