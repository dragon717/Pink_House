//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI

struct SmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.journalRoom.rawValue
    
    var body: some View {
        Group {
            if smallWorldStyle == SmallWorldStyle.journalRoom.rawValue {
                JournalRoomSmallWorldView(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else if smallWorldStyle == SmallWorldStyle.rococo.rawValue {
                RococoSmallWorldView(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            } else {
                FrenchRetroSmallWorldView(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            }
        }
    }
}

private struct JournalRoomSmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared

    @State private var showUnlockAlert = false
    @State private var lockedFeature: AppFeatureDescriptor?

    @MainActor
    private var primaryFeatures: [AppFeatureDescriptor] {
        [.outfitJournal, .magicSticker, .wealth]
            .map(AppFeatureRegistry.descriptor(for:))
            .filter { $0.surfaces.contains(.houseRoom) }
    }

    @MainActor
    private var pinnedFeatures: [AppFeatureDescriptor] {
        [.wardrobe, .depositPlan, .calendar, .dressStock, .perler, .bigWorld]
            .map(AppFeatureRegistry.descriptor(for:))
            .filter { $0.surfaces.contains(.houseRoom) }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .house)
                    .ignoresSafeArea()

                journalRoom(in: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, geometry.size.width > 700 ? 52 : 20)
                    .padding(.top, 28)
                    .padding(.bottom, 98)
            }
        }
        .alert("功能未解锁", isPresented: $showUnlockAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            if let feature = lockedFeature?.unlockFeature {
                let condition = featureManager.getCondition(for: feature)
                Text("\(feature.displayName) 尚未解锁\n\(condition.description)")
            } else {
                Text("该功能尚未解锁，请先完成对应任务")
            }
        }
    }

    private func journalRoom(in geometry: GeometryProxy) -> some View {
        let isWide = geometry.size.width > geometry.size.height
        return VStack(spacing: isWide ? 12 : 18) {
            header
                .padding(.horizontal, isWide ? 30 : 8)

            ZStack {
                journalBackdrop
                journalPages(isWide: isWide)
                    .padding(isWide ? 24 : 18)
            }
            .frame(maxWidth: isWide ? 760 : 520)
            .frame(height: isWide ? min(geometry.size.height * 0.76, 520) : min(geometry.size.height * 0.7, 620))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("House")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(themeManager.primaryTextColor)
                Text("手帐房间")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }

            Spacer()

            if let product = themeSkinManager.activeProduct {
                Label(product.name, systemImage: "wand.and.stars.inverse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.accentTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }

    private var journalBackdrop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "DFA2B8").opacity(colorScheme == .dark ? 0.58 : 0.78),
                            Color(hex: "B78AD8").opacity(colorScheme == .dark ? 0.42 : 0.62),
                            Color(hex: "84BFD6").opacity(colorScheme == .dark ? 0.36 : 0.56)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: "966B8C").opacity(0.22), radius: 24, x: 0, y: 18)

            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55), lineWidth: 1.5)
                .padding(8)
        }
        .rotation3DEffect(.degrees(7), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
    }

    @ViewBuilder
    private func journalPages(isWide: Bool) -> some View {
        if isWide {
            HStack(spacing: 14) {
                leftPage
                spine
                rightPage
            }
        } else {
            VStack(spacing: 12) {
                leftPage
                spine.frame(height: 10)
                rightPage
            }
        }
    }

    private var leftPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日房间")
                .font(.headline.weight(.bold))
                .foregroundStyle(themeManager.primaryTextColor)

            ForEach(primaryFeatures) { feature in
                JournalRoomPosterButton(
                    feature: feature,
                    style: .poster,
                    action: { open(feature) }
                )
                .captureGuideTarget(guideTarget(for: feature))
            }

            Spacer(minLength: 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageSurface)
    }

    private var rightPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷挂画")
                .font(.headline.weight(.bold))
                .foregroundStyle(themeManager.primaryTextColor)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(pinnedFeatures) { feature in
                    JournalRoomPosterButton(
                        feature: feature,
                        style: .pin,
                        action: { open(feature) }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageSurface)
    }

    private var spine: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "C97D9F"), Color(hex: "8D6FAE")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 12)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }

    private var pageSurface: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(hex: colorScheme == .dark ? "342B38" : "FFF9F3").opacity(colorScheme == .dark ? 0.88 : 0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(themeAccent.opacity(colorScheme == .dark ? 0.28 : 0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 12, x: 0, y: 8)
    }

    private var themeAccent: Color {
        if let product = themeSkinManager.activeProduct {
            switch product.assetNamespace {
            case "sky_concert":
                return Color(hex: "A9D8F6")
            case "swan_dream":
                return Color(hex: "DBC7F2")
            default:
                return themeManager.accentTextColor
            }
        }
        return themeManager.accentTextColor
    }

    private func open(_ feature: AppFeatureDescriptor) {
        guard feature.isUnlocked else {
            lockedFeature = feature
            showUnlockAlert = true
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            switch feature.route {
            case .tab(let tabIndex):
                selectedTab = tabIndex
            case .wardrobe(let tab):
                homeTab = tab
                selectedTab = 0
            case .smallWorld(let nextDestination):
                TabNavigationManager.shared.markNavigatingInsideSmallWorld()
                destination = nextDestination
            }
        }
    }

    private func guideTarget(for feature: AppFeatureDescriptor) -> GuideTargetKey? {
        switch feature.id {
        case .outfitJournal:
            return .ootdEntry
        case .wealth:
            return .wealthEntry
        default:
            return nil
        }
    }
}

private struct JournalRoomPosterButton: View {
    enum Style {
        case poster
        case pin
    }

    let feature: AppFeatureDescriptor
    let style: Style
    let action: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: feature.systemImage)
                    .font(style == .poster ? .title2 : .body.weight(.bold))
                    .foregroundStyle(feature.isUnlocked ? Color(hex: feature.tintHex) : themeManager.tertiaryTextColor)
                    .frame(width: style == .poster ? 42 : 34, height: style == .poster ? 42 : 34)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(style == .poster ? .body.weight(.bold) : .caption.weight(.bold))
                        .foregroundStyle(themeManager.primaryTextColor)
                        .lineLimit(1)

                    Text(feature.isUnlocked ? feature.subtitle : "待解锁")
                        .font(.caption2)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .lineLimit(style == .poster ? 2 : 1)
                }

                Spacer(minLength: 0)
            }
            .padding(style == .poster ? 14 : 10)
            .frame(minHeight: style == .poster ? 70 : 58)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: style == .poster ? 18 : 14))
            .overlay(pinDecoration, alignment: .topTrailing)
            .overlay(lockOverlay, alignment: .bottomTrailing)
        }
        .buttonStyle(.plain)
    }

    private var iconBackground: Color {
        (feature.isUnlocked ? Color(hex: feature.tintHex) : themeManager.tertiaryTextColor)
            .opacity(colorScheme == .dark ? 0.18 : 0.14)
    }

    private var buttonBackground: Color {
        if feature.isUnlocked {
            return Color(hex: feature.tintHex).opacity(colorScheme == .dark ? 0.16 : 0.10)
        }
        return themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.42 : 0.7)
    }

    @ViewBuilder
    private var pinDecoration: some View {
        if style == .pin {
            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.32 : 0.86))
                .frame(width: 9, height: 9)
                .padding(8)
        }
    }

    @ViewBuilder
    private var lockOverlay: some View {
        if !feature.isUnlocked {
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(themeManager.tertiaryTextColor)
                .padding(8)
        }
    }
}
