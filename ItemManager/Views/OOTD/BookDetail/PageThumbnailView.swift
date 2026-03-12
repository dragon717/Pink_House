import SwiftUI
import SwiftData

struct PageThumbnailView: View {
    let page: Outfit
    var gridMode: GridMode = .double
    @Environment(\.colorScheme) private var colorScheme
    
    private var targetSize: CGSize {
        switch gridMode {
        case .single:
            return CGSize(width: 800, height: 1066)
        case .double:
            return CGSize(width: 400, height: 533)
        case .triple:
            return CGSize(width: 300, height: 400)
        }
    }

    // 书页封面比例 4:3（竖4，横3）-> 宽:高 = 3:4
    private var aspectRatio: CGFloat {
        3.0 / 4.0
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 使用 Color.clear + overlay 技巧来强制 4:3 比例
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        Group {
                            if let path = page.snapshotPath {
                                AsyncDownsampledImage(
                                    fileName: path,
                                    targetSize: targetSize,
                                    content: { uiImage in
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()  // 使用 fill 模式裁剪填充
                                    },
                                    placeholder: {
                                        placeholderView
                                            .overlay {
                                                ProgressView()
                                            }
                                    }
                                )
                            } else {
                                placeholderView
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()  // 裁剪超出部分
                    }
                }
                .background(Color.white)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(page.note)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(8)
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        switch page.canvasType {
        case "mannequin":
            ZStack {
                colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
                Image(systemName: "tshirt")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray.opacity(0.3))
                Text("人台")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .offset(y: 24)
            }
        case "blank":
            ZStack {
                colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.gray.opacity(0.3))
                    .padding(16)
                Text("空白")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        case "custom":
            ZStack {
                colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray.opacity(0.3))
                Text("图片丢失")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .offset(y: 24)
            }
        default:
            ZStack {
                colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray.opacity(0.3))
            }
        }
    }
}
