import SwiftUI

/// 从原图取完整元素区域，统一等比缩放；文字始终是原图像素。
enum SplashArtworkRegion: CaseIterable {
    case title, wardrobe, enter

    static let sourceSize = CGSize(width: 1279, height: 2750)

    var unitRect: CGRect {
        switch self {
        case .title: return CGRect(x: 0.16, y: 0.12, width: 0.68, height: 0.16)
        case .wardrobe: return CGRect(x: 0, y: 0.285, width: 1, height: 0.54)
        case .enter: return CGRect(x: 0.31, y: 0.82, width: 0.39, height: 0.07)
        }
    }

    var sourceRect: CGRect {
        let rect = unitRect
        return CGRect(x: rect.minX * Self.sourceSize.width,
                      y: rect.minY * Self.sourceSize.height,
                      width: rect.width * Self.sourceSize.width,
                      height: rect.height * Self.sourceSize.height)
    }
}

struct SplashArtworkLayout {
    let isHorizontal: Bool
    let scale: CGFloat
    let spacing: CGFloat

    init(availableSize: CGSize) {
        let title = SplashArtworkRegion.title.sourceRect.size
        let wardrobe = SplashArtworkRegion.wardrobe.sourceRect.size
        let enter = SplashArtworkRegion.enter.sourceRect.size
        let gap: CGFloat = 44
        let width = max(0, availableSize.width - 32)
        let height = max(0, availableSize.height - 32)
        let verticalScale = min(width / SplashArtworkRegion.sourceSize.width,
                                height / SplashArtworkRegion.sourceSize.height)
        let horizontalScale = min(width / (title.width + wardrobe.width + gap),
                                  height / max(wardrobe.height, title.height + enter.height + gap))
        // 折叠展开、分屏与旋转都由当前可用空间决定，选能把完整元素放得更大的布局。
        isHorizontal = horizontalScale > verticalScale
        scale = max(0, max(horizontalScale, verticalScale))
        spacing = gap * scale
    }
}

private struct SplashArtworkElement: View {
    let region: SplashArtworkRegion
    let scale: CGFloat

    var body: some View {
        let rect = region.sourceRect
        Image("SplashScreen")
            .resizable()
            .frame(width: SplashArtworkRegion.sourceSize.width * scale,
                   height: SplashArtworkRegion.sourceSize.height * scale)
            .offset(x: -rect.minX * scale, y: -rect.minY * scale)
            .frame(width: rect.width * scale, height: rect.height * scale, alignment: .topLeading)
            .clipped()
            // 仅羽化原图的空白边缘；16 个源像素不触及文字、衣橱或按钮。
            .mask(edgeMask(fraction: 16 / rect.width, start: .leading, end: .trailing))
            .mask(edgeMask(fraction: 16 / rect.height, start: .top, end: .bottom))
            .accessibilityHidden(true)
    }

    private func edgeMask(fraction: CGFloat, start: UnitPoint, end: UnitPoint) -> LinearGradient {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: .white, location: fraction),
                               .init(color: .white, location: 1 - fraction),
                               .init(color: .clear, location: 1)], startPoint: start, endPoint: end)
    }
}

struct SplashScreenView: View {
    var onTapEnter: (() -> Void)? = nil

    var body: some View {
        Button {
            onTapEnter?()
        } label: {
            SplashArtworkContent()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("少女心愿，进入应用".appLocalized)
    }
}

private struct SplashArtworkContent: View {
    var body: some View {
        GeometryReader { geometry in
            let layout = SplashArtworkLayout(availableSize: geometry.size)
            ZStack {
                LinearGradient(colors: [Color(red: 1, green: 0.99, blue: 0.97),
                                        Color(red: 1, green: 0.99, blue: 0.97),
                                        Color(red: 0.97, green: 0.91, blue: 0.88)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if layout.isHorizontal {
                    HStack(spacing: layout.spacing) {
                        VStack(spacing: layout.spacing) {
                            SplashArtworkElement(region: .title, scale: layout.scale)
                            SplashArtworkElement(region: .enter, scale: layout.scale)
                        }
                        SplashArtworkElement(region: .wardrobe, scale: layout.scale)
                    }
                } else {
                    Image("SplashScreen")
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }
}

#Preview {
    SplashScreenView()
}
