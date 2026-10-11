import SwiftUI

struct ShopCatalogCarouselSlide: Identifiable, Equatable {
    /// 图片资产的稳定标识；URL 刷新或调整顺序不会替换页面身份。
    let id: String
    let ref: String
    let mediaKey: String?
    let colorLabel: String?

    static func selectedID(_ current: String?, in slides: [Self]) -> String? {
        if let current, slides.contains(where: { $0.id == current }) { return current }
        return slides.first?.id
    }
}

/// 翻页状态留在图集内，避免每次滑动都重算详情页的表格和价格档案。
struct ShopCatalogProductGallery: View {
    let slides: [ShopCatalogCarouselSlide]
    let height: CGFloat
    let onOpen: ([String], Int) -> Void
    @State private var selectedSlideID: String?

    private var selection: Binding<String?> {
        Binding(
            get: { ShopCatalogCarouselSlide.selectedID(selectedSlideID, in: slides) },
            set: { selectedSlideID = $0 })
    }

    var body: some View {
        let selectedID = selection.wrappedValue
        let index = slides.firstIndex(where: { $0.id == selectedID }) ?? 0
        ZStack(alignment: .bottom) {
            if slides.isEmpty {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "tshirt")
                            .font(.system(size: 60))
                            .foregroundStyle(.pink.opacity(0.3))
                    }
            } else {
                TabView(selection: selection) {
                    ForEach(slides) { slide in
                        ShopCatalogAssetImage(reference: slide.ref, mediaKey: slide.mediaKey)
                            .frame(height: height)
                            .clipped()
                            .tag(Optional(slide.id))
                            .onTapGesture { onOpen(slides.map(\.ref), index) }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if let colorLabel = slides[index].colorLabel {
                    HStack {
                        Text(colorLabel.appLocalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
                }

                HStack(spacing: 4) {
                    Text("\(index + 1)")
                    Text("/")
                    Text("\(slides.count)")
                }
                .font(.caption2)
                .foregroundStyle(.white)
                .themeSkinLegibleText(level: .badge, slot: .sectionCard)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, 12)
            }
        }
        .frame(height: height)
        .onChange(of: slides.map(\.id), initial: true) { _, _ in
            selectedSlideID = ShopCatalogCarouselSlide.selectedID(selectedSlideID, in: slides)
        }
    }
}
