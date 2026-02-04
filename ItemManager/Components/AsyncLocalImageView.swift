
import SwiftUI

/// 异步加载本地图片的视图组件
/// 针对列表滚动性能优化：
/// 1. 异步加载，不阻塞主线程
/// 2. 支持下采样 (Downsampling)，减少内存占用
/// 3. 自动利用 ImageManager 的内存缓存
struct AsyncLocalImageView: View {
    let fileName: String
    let displaySize: CGSize // UI 显示尺寸 (Points)
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    var placeholderColor: Color = Color.gray.opacity(0.1)
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholderColor
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(Rectangle()) // 确保点击区域正确
        .task(id: fileName) {
            // 计算像素尺寸 (考虑屏幕缩放因子，通常为 2.0 或 3.0)
            // 为了平衡性能和画质，我们可以限制最大缩放因子为 2.0
            let scale = min(UIScreen.main.scale, 2.0)
            let pixelSize = CGSize(
                width: displaySize.width * scale,
                height: displaySize.height * scale
            )
            
            // 异步加载并下采样
            image = await ImageManager.shared.loadImageAsync(fileName: fileName, targetSize: pixelSize)
        }
    }
}
