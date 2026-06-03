import SwiftUI
import Combine
import UIKit

struct VIPCardSkinSelectionView: View {
    @ObservedObject var vipManager = VIPManager.shared
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) var dismiss

    @State private var showingThemeStore = false

    private var activeThemeDescriptor: ThemeSkinDescriptor? {
        VIPThemeSkinSupport.activeDescriptor(slot: .sectionCard)
    }

    private var titleColor: Color {
        activeThemeDescriptor.map { SkyConcertThemeSkin.labelColor(for: $0) } ?? .white
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                backgroundLayer

                VStack(spacing: 0) {
                    Text("选择卡片皮肤".appLocalized)
                        .font(.headline)
                        .foregroundStyle(titleColor)
                        .padding(.top)
                        .padding(.bottom, 20)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 32) {
                            ForEach(VIPCardStyle.allCases) { style in
                                skinOption(style)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                        .padding(.bottom, 100)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("完成".appLocalized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThemeSkinPrimaryButtonStyle(
                        fallbackTint: vipManager.cardStyle == .monicaPink ? Color(hex: "FF69B4") : Color(hex: "1E1E1E"),
                        cornerRadius: 12,
                        verticalPadding: 15
                    ))
                    .padding(.horizontal)
                    .padding(.bottom)
                    .background(
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                            .padding(.top, -20)
                    )
                }
            }
        }
        .sheet(isPresented: $showingThemeStore) {
            NavigationStack {
                ThemeSkinStoreView()
            }
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let descriptor = activeThemeDescriptor {
            ZStack {
                LinearGradient(
                    colors: [
                        SkyConcertThemeSkin.shellFillTop(for: descriptor),
                        SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.72 : 0.5),
                        SkyConcertThemeSkin.shellFillBottom(for: descriptor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                    SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.wardrobeBackdropPlacements)
                        .opacity(0.72)
                        .ignoresSafeArea()
                } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                    SkyConcertDecorationLayer(
                        placements: SwanDreamThemeSkin.wardrobeBackdropPlacements,
                        namespace: SwanDreamThemeSkin.namespace
                    )
                    .opacity(0.72)
                    .ignoresSafeArea()
                }

                Color.white.opacity(0.16).ignoresSafeArea()
            }
        } else {
            ZStack {
                Group {
                    if themeManager.effectiveBackgroundStyle == .image, let image = themeManager.backgroundImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    } else {
                        themeManager.backgroundColor
                            .ignoresSafeArea()
                    }
                }

                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
    }

    private func skinOption(_ style: VIPCardStyle) -> some View {
        let isSelected = vipManager.cardStyle == style
        let isLocked = !VIPThemeSkinSupport.isSelectable(style)

        return VStack(spacing: 16) {
            ZStack {
                VIPCardView(
                    vipNumber: vipManager.vipNumber ?? "88888888",
                    expireDate: vipManager.vipExpireDate ?? Date(),
                    isVIP: true,
                    cardStyle: style,
                    allowsLockedThemePreview: true
                )
                .aspectRatio(1.58, contentMode: .fit)
                .frame(maxWidth: 400)
                .scaleEffect(isSelected ? 1.0 : 0.95)
                .opacity(isLocked ? 0.58 : (isSelected ? 1.0 : 0.74))
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: vipManager.cardStyle)
                .shadow(color: isSelected ? selectionTint(for: style).opacity(0.28) : .clear, radius: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(selectionTint(for: style), lineWidth: isSelected ? 3 : 0)
                )

                if isLocked {
                    lockedOverlay(for: style)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                guard !isLocked else {
                    showingThemeStore = true
                    return
                }

                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    vipManager.updateCardStyle(style)
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(style.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? titleColor : titleColor.opacity(0.64))

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(selectionTint(for: style))
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(selectionTint(for: style))
                    }
                }

                Text(VIPThemeSkinSupport.displayHint(for: style))
                    .font(.caption)
                    .foregroundStyle(titleColor.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func lockedOverlay(for style: VIPCardStyle) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.title2.weight(.bold))
            Text("购买对应主题后可用".appLocalized)
                .font(.caption.weight(.bold))
            Text("点击前往主题商店".appLocalized)
                .font(.caption2.weight(.medium))
                .opacity(0.86)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func selectionTint(for style: VIPCardStyle) -> Color {
        if let descriptor = VIPThemeSkinSupport.descriptor(for: style, slot: .wardrobeItemCard) {
            return SkyConcertThemeSkin.accent(for: descriptor)
        }
        if let descriptor = activeThemeDescriptor {
            return SkyConcertThemeSkin.accent(for: descriptor)
        }
        return style == .monicaPink ? Color(hex: "FF69B4") : .green
    }
}
