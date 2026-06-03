import SwiftUI

struct VIPAppIconSelectionView: View {
    @ObservedObject private var vipManager = VIPManager.shared
    @ObservedObject private var iconManager = VIPAppIconManager.shared
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var resultMessage = ""
    @State private var showingResultAlert = false

    private var visualTheme: VIPVisualTheme {
        vipManager.preferredVisualTheme
    }

    private var themeSkinDescriptor: ThemeSkinDescriptor? {
        if let descriptor = themeSkinManager.activeThemeDescriptor(for: .sectionCard, state: .default),
           VIPThemeSkinSupport.isSupported(descriptor) {
            return descriptor
        }
        return nil
    }

    private var isThemeSkinActive: Bool {
        VIPThemeSkinSupport.isSupported(themeSkinDescriptor)
    }

    private var primaryTextColor: Color {
        themeSkinDescriptor.map { SkyConcertThemeSkin.labelColor(for: $0) } ?? .white
    }

    private var secondaryTextColor: Color {
        themeSkinDescriptor.map { SkyConcertThemeSkin.labelColor(for: $0).opacity(0.72) }
            ?? visualTheme.secondaryTextColor
    }

    private var accentColor: Color {
        themeSkinDescriptor.map { SkyConcertThemeSkin.accent(for: $0) } ?? visualTheme.accentColor
    }

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    topBar
                    introCard
                    supportCard

                    VStack(spacing: 14) {
                        ForEach(iconManager.availableIcons) { option in
                            iconOptionCard(option)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            iconManager.refreshCurrentIcon()
        }
        .alert("个性图标".appLocalized, isPresented: $showingResultAlert) {
            Button("知道了".appLocalized, role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let descriptor = themeSkinDescriptor {
            ZStack {
                LinearGradient(
                    colors: [
                        SkyConcertThemeSkin.shellFillTop(for: descriptor),
                        SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.7 : 0.5),
                        SkyConcertThemeSkin.shellFillBottom(for: descriptor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                    SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.wardrobeBackdropPlacements)
                        .opacity(0.58)
                        .ignoresSafeArea()
                } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                    SkyConcertDecorationLayer(
                        placements: SwanDreamThemeSkin.wardrobeBackdropPlacements,
                        namespace: SwanDreamThemeSkin.namespace
                    )
                    .opacity(0.58)
                    .ignoresSafeArea()
                }

                LinearGradient(
                    colors: [Color.white.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: visualTheme.backgroundGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(visualTheme.glowColor)
                    .frame(width: 260, height: 260)
                    .blur(radius: 56)
                    .offset(x: -100, y: -220)

                Circle()
                    .fill(visualTheme.glowColor.opacity(0.7))
                    .frame(width: 220, height: 220)
                    .blur(radius: 60)
                    .offset(x: 120, y: -60)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("个性图标库".appLocalized)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                Text("VIP 专属桌面换装".appLocalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                closeButton
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if isThemeSkinActive {
            ThemeSkinIconBadge(
                systemName: "xmark",
                fallbackColor: accentColor,
                size: 38,
                symbolSize: 14,
                slot: .topBarIconButton
            )
        } else {
            ZStack {
                VIPGlassCardBackground(glassStyle: visualTheme.secondaryGlassStyle, cornerRadius: 18)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isThemeSkinActive ? accentColor : visualTheme.primaryGlassStyle.iconTint)
                Text("把喜欢的衣橱风格带到桌面".appLocalized)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(primaryTextColor)
            }

            Text("为 Pink House 换一枚更贴近心情的图标。经典、礼服、珍珠与月光风格都可以收藏，桌面也能保持你喜欢的样子。".appLocalized)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 26) {
            VIPGlassCardBackground(glassStyle: visualTheme.primaryGlassStyle, cornerRadius: 26)
        }
    }

    private var supportCard: some View {
        HStack(spacing: 12) {
            Image(systemName: iconManager.supportsAlternateIcons ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconManager.supportsAlternateIcons ? accentColor : Color.orange)

            Text(iconManager.supportsAlternateIcons ? "这台设备可以切换桌面图标。".appLocalized : "这台设备暂时不能切换桌面图标。".appLocalized)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)

            Spacer()
        }
        .padding(16)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 22, showsDecoration: false) {
            VIPGlassCardBackground(glassStyle: .glossBlack, cornerRadius: 22)
        }
    }

    private func iconOptionCard(_ option: VIPAppIconOption) -> some View {
        let isCurrent = iconManager.currentIconID == option.id

        return HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isThemeSkinActive ? SkyConcertThemeSkin.shellFillTop(for: themeSkinDescriptor).opacity(0.74) : Color.white.opacity(0.08))
                    .frame(width: 92, height: 92)

                Image(option.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(4)

                if let badgeText = option.localizedBadgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accentColor.opacity(isThemeSkinActive ? 0.64 : 0.28)))
                        .overlay(
                            Capsule()
                                .stroke(isThemeSkinActive ? accentColor.opacity(0.42) : Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .offset(x: 8, y: -8)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(option.localizedDisplayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryTextColor)

                    if isCurrent {
                        Text("当前使用".appLocalized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isThemeSkinActive ? primaryTextColor : Color.black.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(accentColor.opacity(isThemeSkinActive ? 0.2 : 1)))
                            .overlay(
                                Capsule()
                                    .stroke(accentColor.opacity(isThemeSkinActive ? 0.42 : 0), lineWidth: 1)
                            )
                    }
                }

                Text(option.localizedSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        let result = await iconManager.applyIcon(option)
                        resultMessage = result.message
                        showingResultAlert = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if iconManager.isApplying && !isCurrent {
                            ProgressView()
                                .tint(isThemeSkinActive ? primaryTextColor : Color.black.opacity(0.9))
                        }
                        Text(isCurrent ? "已启用".appLocalized : "切换图标".appLocalized)
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isThemeSkinActive ? primaryTextColor : Color.black.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(iconManager.supportsAlternateIcons ? accentColor.opacity(isThemeSkinActive ? 0.22 : 1) : Color.white.opacity(0.35))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isThemeSkinActive ? accentColor.opacity(0.48) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCurrent || iconManager.isApplying || !iconManager.supportsAlternateIcons || !vipManager.isVIP)
            }

            Spacer()
        }
        .padding(18)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 24, showsDecoration: isCurrent) {
            VIPGlassCardBackground(
                glassStyle: isCurrent ? visualTheme.primaryGlassStyle : .glossBlack,
                cornerRadius: 24
            )
        }
    }
}

#Preview {
    VIPAppIconSelectionView()
}
