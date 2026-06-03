import SwiftUI

struct VIPTrialPopupView: View {
    let visualTheme: VIPVisualTheme
    @Binding var isPresented: Bool
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @State private var showContent = false

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

    private var popupStrokeColor: Color {
        themeSkinDescriptor.map { SkyConcertThemeSkin.shellStroke(for: $0).opacity(0.88) }
            ?? visualTheme.primaryGlassStyle.strokeColor.opacity(0.85)
    }

    private var popupShadowColor: Color {
        themeSkinDescriptor.map { SkyConcertThemeSkin.shadowColor(for: $0).opacity(0.78) }
            ?? visualTheme.primaryGlassStyle.glowColor
    }

    init(
        visualTheme: VIPVisualTheme = VIPManager.shared.preferredVisualTheme,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.visualTheme = visualTheme
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissPopup()
                    }

                popupCard(in: geometry.size)
                    .scaleEffect(showContent ? 1.0 : 0.88)
                    .opacity(showContent ? 1.0 : 0.0)
                    .offset(y: showContent ? 0 : 26)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                showContent = true
            }
        }
    }

    @ViewBuilder
    private func popupCard(in containerSize: CGSize) -> some View {
        let horizontalInset: CGFloat = 28
        let cardWidth = min(360, max(280, containerSize.width - horizontalInset * 2))
        let isCompactHeight = containerSize.height < 760
        let needsScrollableLayout = containerSize.height < 700
        let verticalInset = max(18, min(36, containerSize.height * 0.06))
        let contentSpacing: CGFloat = isCompactHeight ? 14 : 18
        let sectionSpacing: CGFloat = isCompactHeight ? 8 : 10
        let privilegesSpacing: CGFloat = isCompactHeight ? 10 : 12
        let contentPadding = EdgeInsets(
            top: isCompactHeight ? 20 : 24,
            leading: 22,
            bottom: isCompactHeight ? 18 : 24,
            trailing: 22
        )

        Group {
            if needsScrollableLayout {
                ScrollView(.vertical, showsIndicators: false) {
                    popupSurface(
                        isCompactHeight: isCompactHeight,
                        contentSpacing: contentSpacing,
                        sectionSpacing: sectionSpacing,
                        privilegesSpacing: privilegesSpacing,
                        contentPadding: contentPadding
                    )
                }
                .frame(maxWidth: cardWidth, maxHeight: containerSize.height - verticalInset * 2)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                popupSurface(
                    isCompactHeight: isCompactHeight,
                    contentSpacing: contentSpacing,
                    sectionSpacing: sectionSpacing,
                    privilegesSpacing: privilegesSpacing,
                    contentPadding: contentPadding
                )
                .frame(maxWidth: cardWidth)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
    }

    private func popupSurface(
        isCompactHeight: Bool,
        contentSpacing: CGFloat,
        sectionSpacing: CGFloat,
        privilegesSpacing: CGFloat,
        contentPadding: EdgeInsets
    ) -> some View {
        popupContent(
            isCompactHeight: isCompactHeight,
            contentSpacing: contentSpacing,
            sectionSpacing: sectionSpacing,
            privilegesSpacing: privilegesSpacing
        )
        .padding(contentPadding)
        .frame(maxWidth: .infinity)
        .background(popupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(popupStrokeColor, lineWidth: isThemeSkinActive ? 1.2 : 1)
        )
        .shadow(color: popupShadowColor, radius: 24, x: 0, y: 12)
    }

    private func popupContent(
        isCompactHeight: Bool,
        contentSpacing: CGFloat,
        sectionSpacing: CGFloat,
        privilegesSpacing: CGFloat
    ) -> some View {
        VStack(spacing: contentSpacing) {
            VStack(spacing: sectionSpacing) {
                Image(systemName: "sparkles")
                    .font(.system(size: isCompactHeight ? 22 : 24, weight: .bold))
                    .foregroundStyle(accentColor)

                Text("先体验 3 天 VIP".appLocalized)
                    .font(.system(size: isCompactHeight ? 22 : 24, weight: .bold))
                    .foregroundStyle(primaryTextColor)

                Text("解锁智能能力、尊贵身份与会员优惠".appLocalized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: privilegesSpacing) {
                privilegeRow(icon: "bubble.left.and.bubble.right.fill", text: "萌宠智能对话与多模态能力".appLocalized)
                privilegeRow(icon: "crown.fill", text: "专属 VIP 身份与卡片皮肤".appLocalized)
                privilegeRow(icon: "ticket.fill", text: "萌宠商店 %@".appLocalized(VIPManager.petShopDiscountText))
            }

            Text("体验结束后可继续兑换 1个月 / 3个月 会员时长".appLocalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryTextColor.opacity(0.76))
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        onConfirm()
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("确认体验".appLocalized)
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isThemeSkinActive ? primaryTextColor : Color.black.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(confirmButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isThemeSkinActive ? popupStrokeColor : Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: popupShadowColor, radius: 18, x: 0, y: 8)
                }
                .captureGuideTarget(.aiAnalysisVIPTrialConfirmButton)

                Button {
                    dismissPopup()
                } label: {
                    Text("稍后".appLocalized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var popupBackground: some View {
        if let descriptor = themeSkinDescriptor {
            ZStack {
                LinearGradient(
                    colors: [
                        SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.98),
                        SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.72 : 0.52),
                        SkyConcertThemeSkin.shellFillBottom(for: descriptor).opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                    SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.statsCardPlacements)
                        .opacity(0.48)
                } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                    SkyConcertDecorationLayer(
                        placements: SwanDreamThemeSkin.statsCardPlacements,
                        namespace: SwanDreamThemeSkin.namespace
                    )
                    .opacity(0.5)
                }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .blendMode(.softLight)
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: visualTheme.backgroundGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(visualTheme.glowColor)
                    .frame(width: 180, height: 180)
                    .blur(radius: 42)
                    .offset(x: -76, y: -120)

                VIPGlassCardBackground(glassStyle: visualTheme.primaryGlassStyle, cornerRadius: 28)
            }
        }
    }

    @ViewBuilder
    private var confirmButtonBackground: some View {
        if let descriptor = themeSkinDescriptor {
            LinearGradient(
                colors: [
                    SkyConcertThemeSkin.accent(for: descriptor).opacity(0.94),
                    SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    visualTheme.accentColor,
                    visualTheme.accentColor.opacity(0.82)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func privilegeRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isThemeSkinActive ? accentColor : visualTheme.primaryGlassStyle.iconTint)
                .frame(width: 26, height: 26)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(primaryTextColor)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false) {
            VIPGlassCardBackground(glassStyle: .glossBlack, cornerRadius: 18)
        }
    }

    private func dismissPopup() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
            isPresented = false
        }
    }
}

#Preview {
    VIPTrialPopupView(
        visualTheme: .deepBlue,
        isPresented: .constant(true),
        onConfirm: { print("确认体验") },
        onDismiss: { print("关闭弹窗") }
    )
}
