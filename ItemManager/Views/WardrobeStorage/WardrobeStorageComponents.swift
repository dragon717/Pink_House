import SwiftUI
import UIKit

/// Furniture is confined to the explicit storage experience, never drawn on the home screen.
enum WardrobeStorageArt {
    static let ink = Color(red: 0.31, green: 0.22, blue: 0.22)
    static let rose = Color(red: 0.68, green: 0.25, blue: 0.38)
    static let cream = Color(red: 0.99, green: 0.96, blue: 0.93)
}

/// A quiet rear surface shared by the controls and category rail. Furniture casts onto it.
struct WardrobeStorageRearPlane: View {
    @Environment(\.wardrobeStoragePalette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 26)
            .fill(palette.rear.color)
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(palette.border.color.opacity(palette.increasedContrast ? 0.8 : 0.35), lineWidth: 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct WardrobeStorageItemImage: View {
    let entry: WardrobeStorageEntry
    let size: CGSize
    @Environment(\.wardrobeStorageImageRefresh) private var refresh
    @Environment(\.wardrobeStoragePalette) private var palette
    @Environment(\.wardrobeStorageCabinetLighting) private var cabinetLighting
    @State private var isCutout = false
    @State private var image: UIImage?
    @State private var isProcessing = false
    @State private var canRetry = false

    private var imageKey: String {
        [entry.id, entry.imageSource.key, String(refresh)].joined(separator: "/")
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .wardrobeItemLight(size: size, enabled: palette.isDark && cabinetLighting && isCutout)
                    .shadow(color: palette.isDark && cabinetLighting && isCutout ? Color(red: 1, green: 0.77, blue: 0.53).opacity(0.28) : .clear,
                            radius: 1, y: -1)
            } else if isProcessing {
                ProgressView().tint(palette.accent.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: entry.category.symbol)
                    .font(.system(size: min(size.width, size.height) * 0.32, weight: .ultraLight))
                    .foregroundStyle(palette.secondary.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topTrailing) {
            if canRetry {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(palette.accent.color)
            }
        }
        .accessibilityHidden(true)
        .task(id: imageKey) {
            image = nil
            isCutout = false
            canRetry = false
            isProcessing = !entry.imageSource.isEmpty
            let result = await WardrobeStorageImageResolver.resolve(entry.imageSource)
            guard !Task.isCancelled else { return }
            image = result.data.flatMap { UIImage(data: $0) }
            isCutout = result.isCutout
            canRetry = result.canRetry
            isProcessing = false
        }
    }
}

struct WardrobeStorageItemLabel: View {
    let entry: WardrobeStorageEntry
    let showPrice: Bool
    @Environment(\.wardrobeStoragePalette) private var palette

    var body: some View {
        VStack(spacing: 2) {
            Text(entry.title.isEmpty ? "未命名".appLocalized : entry.title)
                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                .foregroundStyle(palette.primary.color)
            if showPrice, let price = entry.price {
                Text(price, format: .currency(code: "CNY"))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(palette.accent.color).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WardrobeStorageShelf: View {
    let category: WardrobeStorageCategory
    let entries: [WardrobeStorageEntry]
    let width: CGFloat
    let number: Int
    let showPrice: Bool
    @Environment(\.wardrobeStoragePalette) private var palette
    let onSelect: (WardrobeStorageEntry) -> Void
    private var height: CGFloat { width * category.shelfHeightRatio }

    var body: some View {
        ZStack(alignment: .topLeading) {
            furniture
            if palette.isDark { WardrobeStorageShelfLight(width: width, height: height) }
            ForEach(entries.indices, id: \.self) { index in
                Ellipse().fill(.black.opacity(palette.isDark ? 0.46 : 0.12))
                    .frame(width: width * 0.26, height: height * 0.035)
                    .blur(radius: 3)
                    .position(x: width * (index == 0 ? 0.31 : 0.69), y: height * 0.72)
                    .accessibilityHidden(true)
            }
            if category != .shoes {
                ForEach(entries.indices, id: \.self) { index in
                    displaySupport
                        .frame(width: width * 0.29, height: height * 0.07)
                        .position(x: width * (index == 0 ? 0.31 : 0.69), y: height * 0.72)
                        .accessibilityHidden(true)
                }
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button { onSelect(entry) } label: {
                    VStack(spacing: 2) {
                        WardrobeStorageItemImage(entry: entry, size: CGSize(width: width * 0.34, height: height * (showPrice ? 0.55 : 0.67)))
                            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 3)
                        WardrobeStorageItemLabel(entry: entry, showPrice: showPrice)
                    }
                    .frame(width: width * 0.36, height: height * 0.85)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    if let status = entry.statusLabel {
                        Text(status.appLocalized).font(.system(size: 9, weight: .medium))
                            .padding(4).background(palette.label.color, in: Capsule())
                            .foregroundStyle(palette.accent.color)
                            .allowsHitTesting(false)
                    }
                }
                .position(x: width * (index == 0 ? 0.31 : 0.69), y: height * 0.44)
                .accessibilityLabel(entry.title + (entry.statusLabel.map { "，" + $0.appLocalized } ?? ""))
                .accessibilityValue(showPrice ? entry.price.map { $0.formatted(.currency(code: "CNY")) } ?? "" : "")
                .accessibilityHint("查看收藏详情".appLocalized)
            }

        }
        .frame(width: width, height: height)
        .environment(\.wardrobeStorageCabinetLighting, true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 %lld 层".appLocalized(Int64(number)))
    }

    @ViewBuilder
    private var displaySupport: some View {
        if category == .beauty {
            Ellipse().fill(LinearGradient(colors: [.white, Color(red: 0.86, green: 0.76, blue: 0.66)], startPoint: .top, endPoint: .bottom))
                .wardrobeFurnitureLight(size: CGSize(width: width * 0.29, height: height * 0.07), part: .base, enabled: palette.isDark)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 3)
        } else {
            RoundedRectangle(cornerRadius: category == .accessories ? 9 : 3)
                .fill(LinearGradient(colors: category == .accessories
                                     ? [Color(red: 0.91, green: 0.73, blue: 0.74), Color(red: 0.72, green: 0.49, blue: 0.50)]
                                     : [WardrobeStorageArt.cream, Color(red: 0.83, green: 0.72, blue: 0.61)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.45)).frame(height: 1) }
                .wardrobeFurnitureLight(size: CGSize(width: width * 0.29, height: height * 0.07), part: .base, enabled: palette.isDark)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 3)
        }
    }

    @ViewBuilder
    private var furniture: some View {
        if UIImage(named: "storage_cabinet_shelf") != nil {
            Image("storage_cabinet_shelf").resizable().frame(width: width, height: height)
                .wardrobeFurnitureLight(size: CGSize(width: width, height: height), part: .shelf, enabled: palette.isDark)
        } else {
            // An absent art asset must not prevent browsing the collection.
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.77, green: 0.66, blue: 0.55), WardrobeStorageArt.cream], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(WardrobeStorageArt.cream).frame(height: 14)
                        .shadow(color: .black.opacity(0.17), radius: 3, y: -2)
                }
                .overlay {
                    HStack {
                        Rectangle().fill(WardrobeStorageArt.cream).frame(width: 16)
                        Spacer()
                        Rectangle().fill(WardrobeStorageArt.cream).frame(width: 16)
                    }
                }
                .wardrobeFurnitureLight(size: CGSize(width: width, height: height), part: .shelf, enabled: palette.isDark)
        }
    }
}

struct WardrobeStorageCabinet: View {
    let category: WardrobeStorageCategory
    let entries: [WardrobeStorageEntry]
    let width: CGFloat
    let showPrice: Bool
    @Environment(\.wardrobeStoragePalette) private var palette
    let onSelect: (WardrobeStorageEntry) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowCount: Int { max(4, (entries.count + 1) / 2) }
    // Leave room for the furniture's silhouette and cast shadow within the rear plane.
    private var cabinetWidth: CGFloat { max(1, width - 28) }

    var body: some View {
        let shouldReduceMotion = reduceMotion
        VStack(spacing: 0) {
            // The crown stays outside the clipped / snapping viewport, so scrolling cannot
            // tuck its bow and carved tip underneath the room controls.
            crown
                .zIndex(1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        let start = min(row * 2, entries.count)
                        let end = min(start + 2, entries.count)
                        WardrobeStorageShelf(category: category, entries: Array(entries[start..<end]), width: cabinetWidth, number: row + 1, showPrice: showPrice, onSelect: onSelect)
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content
                                    .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.94)
                            }
                    }
                    if UIImage(named: "storage_cabinet_base") != nil {
                        Image("storage_cabinet_base")
                            .resizable().frame(width: cabinetWidth, height: cabinetWidth * 274 / 780)
                            .wardrobeFurnitureLight(size: CGSize(width: cabinetWidth, height: cabinetWidth * 274 / 780), part: .base, enabled: palette.isDark)
                            .accessibilityHidden(true)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .defaultScrollAnchor(.top)
        }
        .frame(width: cabinetWidth)
        // One shadow for the visible silhouette avoids dark bands between individual shelves.
        .compositingGroup()
        .shadow(color: Color(red: 0.32, green: 0.20, blue: 0.18).opacity(palette.isDark ? 0.55 : 0.23), radius: 9, x: -4, y: 7)
        .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.09), radius: 2, x: -1, y: 2)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .accessibilityIdentifier("storage.cabinet")
    }

    @ViewBuilder
    private var crown: some View {
        if UIImage(named: "storage_cabinet_crown") != nil {
            Image("storage_cabinet_crown")
                .resizable().frame(width: cabinetWidth, height: cabinetWidth * 281 / 780)
                .wardrobeFurnitureLight(size: CGSize(width: cabinetWidth, height: cabinetWidth * 281 / 780), part: .crown, enabled: palette.isDark)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gift")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(palette.accent.color)
                .frame(width: cabinetWidth, height: 72)
                .accessibilityHidden(true)
        }
    }
}

struct WardrobeStorageGrid: View {
    let entries: [WardrobeStorageEntry]
    let width: CGFloat
    let showPrice: Bool
    @Environment(\.wardrobeStoragePalette) private var palette
    let onSelect: (WardrobeStorageEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 16) {
                ForEach(entries) { entry in
                    Button { onSelect(entry) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            WardrobeStorageItemImage(entry: entry, size: CGSize(width: (width - 34) / 2, height: (width - 34) / 2))
                                .background(palette.card.color, in: RoundedRectangle(cornerRadius: 12))
                            Text(entry.title.isEmpty ? "未命名".appLocalized : entry.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(2)
                                .foregroundStyle(palette.primary.color)
                            if showPrice, let price = entry.price {
                                Text(price, format: .currency(code: "CNY"))
                                    .font(.system(size: 11)).foregroundStyle(palette.secondary.color)
                            }
                            if let status = entry.statusLabel {
                                Text(status.appLocalized).font(.caption2).foregroundStyle(palette.accent.color)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("storage.grid")
    }
}
