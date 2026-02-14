import SwiftUI

struct BookOpeningOverlay: View {
    let book: BookGroup
    let namespace: Namespace.ID
    let onAnimationComplete: () -> Void
    
    @State private var isOpened = false
    @State private var showContent = false
    
    // 动画配置
    private var openDuration: Double {
        // 根据书页数量动态调整动画时长
        let pageCount = book.pages.filter({ !$0.isDeleted }).count
        if pageCount > 20 {
            return 2.0 // 书页多，播放慢一点
        } else {
            return 1.2 // 正常速度，至少 1s 以上
        }
    }
    
    // 第一帧停留时间
    private let holdDuration: Double = 0.3
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.1) // 降低透明度，减少黑色感
                .ignoresSafeArea()
                .onTapGesture {
                    // 阻止点击穿透
                }
            
            // 书本主体
            ZStack {
                // 1. 厚度层（模拟书页侧边）
                // 在 ThreeDBookView 中是 5 层 RoundedRectangle
                // 这里我们也保留，但在打开状态下可能不需要或者调整位置
                if !isOpened {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(uiColor: .systemGray6))
                            .frame(width: UIScreen.main.bounds.width * 0.9,
                                   height: UIScreen.main.bounds.height * 0.8)
                            .offset(x: CGFloat(index) * 2.5, y: 0)
                            .shadow(color: .black.opacity(0.05), radius: 1, x: 1, y: 0)
                    }
                } else {
                    // 打开后显示的底面（封底）
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white) // 明确背景为白色
                        .frame(width: UIScreen.main.bounds.width * 0.9, height: UIScreen.main.bounds.height * 0.8)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 5, y: 5)
                }
                
                // 2. 内容页（第一页预览）
                if showContent {
                    // 白色背景层，确保PNG透明部分显示为白色
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: UIScreen.main.bounds.width * 0.9 - 24, height: UIScreen.main.bounds.height * 0.8 - 24)
                        .padding(12)
                    
                    Group {
                        if let firstPage = book.pages.filter({ !$0.isDeleted }).sorted(by: { $0.createdAt > $1.createdAt }).first,
                           let snapshotPath = firstPage.snapshotPath,
                           let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            // 空白页或其他占位
                            VStack {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary.opacity(0.3))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: UIScreen.main.bounds.width * 0.9 - 24, height: UIScreen.main.bounds.height * 0.8 - 24)
                    .padding(12)
                    .transition(.opacity.animation(.easeInOut(duration: openDuration * 0.5)))
                    
                    // 拟物阴影遮罩：封面翻开时，内容页从暗变亮
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.black.opacity(0.3), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: UIScreen.main.bounds.width * 0.9 - 24, height: UIScreen.main.bounds.height * 0.8 - 24)
                        .padding(12)
                        .opacity(isOpened ? 0 : 1) // 随翻页消失
                        .animation(.easeInOut(duration: openDuration), value: isOpened)
                }
                
                // 3. 封面（带翻转动画）
                BookCoverVisuals(book: book)
                    .overlay(
                        // 拟物高光/阴影：随着翻转角度变化
                        Color.white
                            .opacity(isOpened ? 0.1 : 0) // 翻开时稍微变亮（模拟反光）或变暗（模拟背光），这里简单处理
                            .animation(.easeInOut(duration: openDuration), value: isOpened)
                    )
                    .frame(width: UIScreen.main.bounds.width * 0.9,
                           height: UIScreen.main.bounds.height * 0.8)
                    .rotation3DEffect(
                        .degrees(isOpened ? -160 : -8), 
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.5
                    )
                    // 确保旋转轴心在左侧边缘
            }
            .padding(.trailing, 0) // 匹配 ThreeDBookView 的 padding
            .matchedGeometryEffect(id: "book_\(book.id)", in: namespace, isSource: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 强制占满全屏，并居中
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 1. 翻页动画
            // 先停留 holdDuration 时间，展示封面
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                withAnimation(.easeInOut(duration: openDuration)) {
                    isOpened = true
                    showContent = true
                }
            }
            
            // 2. 动画结束，回调切换
            // 总时间 = 停留时间 + 翻页时间
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration + openDuration) {
                onAnimationComplete()
            }
        }
    }
}
