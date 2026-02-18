//
//  PageFlipView.swift
//  ItemManager
//
//  3D卷轴式翻书动画视图 - 从角落卷起
//

import SwiftUI
import Darwin

/// 翻页方向
enum PageFlipDirection {
    case next     // 下一页 - 从右下角卷起翻开
    case previous // 上一页 - 从左下角卷起翻开
}

/// 3D卷轴式翻书动画视图
/// 模拟真实书页从角落卷起翻动的效果
struct PageFlipView: View {
    // 当前页图像（正在翻动的页）
    let currentPageImage: UIImage
    // 下一页/上一页图像（目标页）
    let targetPageImage: UIImage
    // 翻页方向
    let direction: PageFlipDirection
    // 动画进度 0.0 ~ 1.0
    @Binding var progress: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let aspectRatio: CGFloat = 0.75 // 3:4 书页比例
            
            // 计算书页尺寸
            let pageWidth = min(size.width * 0.8, size.height * aspectRatio * 0.8)
            let pageHeight = pageWidth / aspectRatio
            
            ZStack {
                // 背景层 - 目标页（始终在下面）
                Image(uiImage: targetPageImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: pageWidth, height: pageHeight)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                // 翻动的当前页 - 卷轴效果
                flippingPage(width: pageWidth, height: pageHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    /// 翻动的书页 - 卷轴效果
    private func flippingPage(width: CGFloat, height: CGFloat) -> some View {
        let isNext = direction == .next
        let normalizedProgress = max(0, min(1, progress))
        
        return Canvas { context, size in
            // 绘制卷轴式翻页效果
            drawCurledPage(
                context: context,
                size: size,
                image: currentPageImage,
                progress: normalizedProgress,
                isNext: isNext
            )
        }
        .frame(width: width, height: height)
        .shadow(
            color: .black.opacity(0.3 * (1 - normalizedProgress)),
            radius: 20 * (1 - normalizedProgress),
            x: isNext ? -10 : 10,
            y: 5
        )
    }
    
    /// 绘制卷曲的书页
    private func drawCurledPage(
        context: GraphicsContext,
        size: CGSize,
        image: UIImage,
        progress: CGFloat,
        isNext: Bool
    ) {
        guard let cgImage = image.cgImage else { return }
        
        let width = size.width
        let height = size.height
        
        // 卷曲参数
        let curlProgress = progress
        let maxCurlWidth: CGFloat = width * 0.5 // 最大卷曲宽度
        let curlWidth = maxCurlWidth * curlProgress
        
        // 确定卷曲的起始角
        // 下一页：从右下角开始向左上卷曲
        // 上一页：从左下角开始向右上卷曲
        let startX: CGFloat = isNext ? width : 0
        let startY: CGFloat = height
        
        // 创建渐变阴影效果
        let shadowGradient = Gradient(colors: [
            .black.opacity(0.4),
            .black.opacity(0.2),
            .clear
        ])
        
        // 绘制书页主体（未卷曲部分）
        let mainRect: CGRect
        if isNext {
            // 下一页：从左边到卷曲起点
            mainRect = CGRect(x: 0, y: 0, width: width - curlWidth, height: height)
        } else {
            // 上一页：从卷曲终点到右边
            mainRect = CGRect(x: curlWidth, y: 0, width: width - curlWidth, height: height)
        }
        
        // 绘制主图像
        context.draw(Image(uiImage: image), in: CGRect(origin: .zero, size: size))
        
        // 绘制卷曲部分
        if curlWidth > 0 {
            let curlRect: CGRect
            if isNext {
                curlRect = CGRect(x: width - curlWidth, y: 0, width: curlWidth, height: height)
            } else {
                curlRect = CGRect(x: 0, y: 0, width: curlWidth, height: height)
            }
            
            // 创建卷曲效果的遮罩
            var curlPath = Path()
            
            if isNext {
                // 下一页：右下角向左上卷曲
                // 绘制梯形表示卷曲的侧面
                let curlAngle = curlProgress * .pi / 3 // 最大60度卷曲
                let lift = curlWidth * sin(curlAngle) * 0.3
                
                curlPath.move(to: CGPoint(x: width - curlWidth, y: 0))
                curlPath.addLine(to: CGPoint(x: width - curlWidth * 0.7, y: lift))
                curlPath.addLine(to: CGPoint(x: width - curlWidth * 0.7, y: height - lift))
                curlPath.addLine(to: CGPoint(x: width - curlWidth, y: height))
                curlPath.closeSubpath()
                
                // 绘制阴影渐变
                context.fill(
                    curlPath,
                    with: .linearGradient(
                        shadowGradient,
                        startPoint: CGPoint(x: width - curlWidth, y: height / 2),
                        endPoint: CGPoint(x: width - curlWidth * 0.5, y: height / 2)
                    )
                )
                
                // 绘制背面的阴影（卷曲的内侧）
                var backPath = Path()
                backPath.move(to: CGPoint(x: width - curlWidth * 0.7, y: lift))
                backPath.addLine(to: CGPoint(x: width, y: 0))
                backPath.addLine(to: CGPoint(x: width, y: height))
                backPath.addLine(to: CGPoint(x: width - curlWidth * 0.7, y: height - lift))
                backPath.closeSubpath()
                
                context.fill(backPath, with: .color(.black.opacity(0.3)))
                
            } else {
                // 上一页：左下角向右上卷曲
                let curlAngle = curlProgress * .pi / 3
                let lift = curlWidth * sin(curlAngle) * 0.3
                
                curlPath.move(to: CGPoint(x: curlWidth, y: 0))
                curlPath.addLine(to: CGPoint(x: curlWidth * 0.7, y: lift))
                curlPath.addLine(to: CGPoint(x: curlWidth * 0.7, y: height - lift))
                curlPath.addLine(to: CGPoint(x: curlWidth, y: height))
                curlPath.closeSubpath()
                
                // 绘制阴影渐变
                context.fill(
                    curlPath,
                    with: .linearGradient(
                        shadowGradient,
                        startPoint: CGPoint(x: curlWidth, y: height / 2),
                        endPoint: CGPoint(x: curlWidth * 0.5, y: height / 2)
                    )
                )
                
                // 绘制背面的阴影
                var backPath = Path()
                backPath.move(to: CGPoint(x: curlWidth * 0.7, y: lift))
                backPath.addLine(to: CGPoint(x: 0, y: 0))
                backPath.addLine(to: CGPoint(x: 0, y: height))
                backPath.addLine(to: CGPoint(x: curlWidth * 0.7, y: height - lift))
                backPath.closeSubpath()
                
                context.fill(backPath, with: .color(.black.opacity(0.3)))
            }
        }
        
        // 添加整体阴影效果
        if progress > 0 && progress < 1 {
            let shadowRect = CGRect(x: 0, y: 0, width: width, height: height)
            context.fill(
                Path(shadowRect),
                with: .color(.black.opacity(0.1 * sin(progress * .pi)))
            )
        }
    }
}

/// 翻书角效果（翻页前的提示）
struct PageCornerPeekView: View {
    let pageImage: UIImage
    let direction: PageFlipDirection
    @Binding var dragProgress: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cornerSize: CGFloat = 80
            
            ZStack {
                // 主书页
                Image(uiImage: pageImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 书角掀起效果
                if dragProgress > 0 {
                    cornerFold(size: cornerSize, in: size)
                }
            }
        }
    }
    
    private func cornerFold(size: CGFloat, in containerSize: CGSize) -> some View {
        let isNext = direction == .next
        let maxLift: CGFloat = size * dragProgress
        
        return ZStack {
            // 阴影层
            Path { path in
                if isNext {
                    path.move(to: CGPoint(x: containerSize.width, y: containerSize.height - size))
                    path.addLine(to: CGPoint(x: containerSize.width, y: containerSize.height))
                    path.addLine(to: CGPoint(x: containerSize.width - size, y: containerSize.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: containerSize.height - size))
                    path.addLine(to: CGPoint(x: 0, y: containerSize.height))
                    path.addLine(to: CGPoint(x: size, y: containerSize.height))
                }
            }
            .fill(
                LinearGradient(
                    colors: [.black.opacity(0.3), .clear],
                    startPoint: isNext ? .bottomTrailing : .bottomLeading,
                    endPoint: isNext ? .topLeading : .topTrailing
                )
            )
            
            // 翻起的角
            Image(uiImage: pageImage)
                .resizable()
                .scaledToFit()
                .frame(width: size * 2, height: size * 2)
                .clipShape(
                    TriangleShape(isRightSide: isNext)
                        .rotation(
                            isNext 
                                ? .degrees(-45 * dragProgress)
                                : .degrees(45 * dragProgress)
                        )
                )
                .offset(
                    x: isNext 
                        ? containerSize.width - size + maxLift * 0.3
                        : -containerSize.width + size - maxLift * 0.3,
                    y: containerSize.height - size + maxLift * 0.3
                )
                .rotation3DEffect(
                    .degrees(45 * dragProgress),
                    axis: (x: 0, y: isNext ? -1 : 1, z: 0)
                )
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
        }
    }
}

/// 三角形裁剪形状
struct TriangleShape: Shape {
    let isRightSide: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isRightSide {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 预览
#Preview {
    PageFlipPreviewContainer()
}

struct PageFlipPreviewContainer: View {
    @State private var progress: CGFloat = 0
    @State private var direction: PageFlipDirection = .next
    
    // 创建测试图像
    let currentImage = createTestImage(color: .blue, text: "当前页")
    let targetImage = createTestImage(color: .green, text: "下一页")
    
    var body: some View {
        VStack(spacing: 20) {
            // 翻页动画视图
            PageFlipView(
                currentPageImage: currentImage,
                targetPageImage: targetImage,
                direction: direction,
                progress: $progress
            )
            .frame(height: 400)
            .background(Color.gray.opacity(0.1))
            
            // 控制面板
            VStack(spacing: 16) {
                // 进度滑块
                Slider(value: $progress, in: 0...1)
                    .padding(.horizontal)
                
                Text("进度: \(Int(progress * 100))%")
                    .font(.caption)
                
                // 方向切换
                Picker("方向", selection: $direction) {
                    Text("下一页").tag(PageFlipDirection.next)
                    Text("上一页").tag(PageFlipDirection.previous)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // 动画按钮
                Button("播放动画") {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        progress = progress > 0.5 ? 0 : 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// 创建测试图像
func createTestImage(color: UIColor, text: String) -> UIImage {
    let size = CGSize(width: 1080, height: 1440)
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    
    // 背景
    color.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    
    // 文字
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    
    let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 100, weight: .bold),
        .foregroundColor: UIColor.white,
        .paragraphStyle: paragraphStyle
    ]
    
    let textSize = text.size(withAttributes: attributes)
    let textRect = CGRect(
        x: (size.width - textSize.width) / 2,
        y: (size.height - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )
    
    text.draw(in: textRect, withAttributes: attributes)
    
    let image = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return image
}
