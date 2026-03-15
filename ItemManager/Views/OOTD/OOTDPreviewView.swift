
import SwiftUI

struct OOTDPreviewView: View {
    let outfit: Outfit
    
    // Standard Reference Size (Same as Canvas)
    private let canvasWidth: CGFloat = 1080
    private let canvasHeight: CGFloat = 1440
    
    var body: some View {
        ZStack {
            // Always ensure a white base layer to prevent black background when saving as JPEG
            Color.white
                .frame(width: canvasWidth, height: canvasHeight)
            
            if outfit.canvasType == "blank" {
                // Already white
            } else if outfit.canvasType == "custom",
                      let path = outfit.backgroundImagePath,
                      let uiImage = ImageManager.shared.loadImage(fileName: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            } else {
                // Mannequin or fallback
                Image("ootd_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            }
            
            ForEach((outfit.items ?? []).sorted(by: { $0.zIndex < $1.zIndex })) { item in
                if let cutout = item.cutout,
                   let uiImage = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        // 200 is base size in CanvasItemView
                        .frame(width: 200, height: 200)
                        .scaleEffect(item.scale)
                        .rotationEffect(Angle(degrees: item.rotation))
                        // 兼容老数据：如果坐标大于1.5，说明是绝对坐标，需要转换为相对坐标
                        .position(
                            x: normalizedX(item.x) * canvasWidth,
                            y: normalizedY(item.y) * canvasHeight
                        )
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }

    // MARK: - 坐标兼容处理（老数据使用绝对坐标，新数据使用相对坐标 0-1）

    /// 将 X 坐标标准化为相对坐标（0-1）
    private func normalizedX(_ x: Double) -> Double {
        if x > 1.5 {
            return x / 1080.0
        }
        return x
    }

    /// 将 Y 坐标标准化为相对坐标（0-1）
    private func normalizedY(_ y: Double) -> Double {
        if y > 1.5 {
            return y / 1440.0
        }
        return y
    }
}
