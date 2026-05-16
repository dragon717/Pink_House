
import SwiftUI
import SwiftData

/// 3D 手帐翻页动画组件
struct BookOpeningAnimationView: View {
    let book: BookGroup
    // 回调：动画完成
    var onAnimationComplete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    // 动画状态
    @State private var isMovingToCenter = false
    @State private var isOpening = false
    @State private var pagesFlipped: [Bool] = Array(repeating: false, count: 6)
    
    // 书页图片缓存
    @State private var pageImages: [UIImage?] = Array(repeating: nil, count: 6)
    // 封面图片缓存 - 确保使用最新数据
    @State private var coverImage: UIImage? = nil
    
    // 配置参数
    private let bookWidth: CGFloat = 200
    private let bookHeight: CGFloat = 280
    private let coverColor = Color(hex: "8D6E63") // 棕色封面
    private let pageColor = Color(hex: "F5F5DC") // 米色纸张
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .opacity(isMovingToCenter ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: isMovingToCenter)
            
            // 3D 书本容器
            ZStack {
                // 1. 封底 (固定不动，或者稍微调整角度)
                BookCover(book: book, width: bookWidth, height: bookHeight, color: coverColor, image: coverImage)
                
                // 2. 书页 (多层)
                ForEach(0..<6) { index in
                    BookPage(width: bookWidth - 10, height: bookHeight - 10, color: pageColor, image: pageImages[index])
                        .rotation3DEffect(
                            .degrees(pagesFlipped[index] ? -175 + Double.random(in: -5...5) : 0),
                            axis: (x: 0.0, y: 1.0, z: 0.0),
                            anchor: .leading,
                            anchorZ: 0,
                            perspective: 0.5
                        )
                        .offset(x: 5, y: 0) // 稍微向右偏移，居中于封面
                        .zIndex(Double(6 - index)) // 索引小的在上面
                }
                
                // 3. 封面
                BookCover(book: book, width: bookWidth, height: bookHeight, color: coverColor, isFront: true, image: coverImage)
                    .rotation3DEffect(
                        .degrees(isOpening ? -180 : 0),
                        axis: (x: 0.0, y: 1.0, z: 0.0),
                        anchor: .leading,
                        anchorZ: 0,
                        perspective: 0.5
                    )
                    .zIndex(10)
            }
            // 整体变换：移动到中心并放大
            .scaleEffect(isMovingToCenter ? 1.5 : 0.2)
            .rotation3DEffect(
                .degrees(isMovingToCenter ? 0 : 45),
                axis: (x: 0.0, y: 1.0, z: 0.0)
            )
            .offset(y: isMovingToCenter ? 0 : 300) // 从下方飞入
        }
        .onAppear {
            loadPageImages()
            startAnimationSequence()
        }
    }
    
    private func loadPageImages() {
        // 保底逻辑：重新从数据库获取最新的书页数据，确保不包含已删除的书页
        let bookID = book.id
        let descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate { outfit in
                outfit.book?.id == bookID && outfit.isDeleted == false
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        let validPages = (try? modelContext.fetch(descriptor)) ?? []
        
        // 加载封面图片 - 优先使用用户设置的封面，否则使用第一页的快照
        if let coverPath = book.coverImage,
           let image = ImageManager.shared.loadImage(fileName: coverPath) {
            coverImage = image
        } else if let firstPage = validPages.first,
                  firstPage.shouldUseStoredSnapshot,
                  let snapshotPath = firstPage.snapshotPath,
                  let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
            coverImage = image
        }
        
        // 如果没有书页，直接返回
        if validPages.isEmpty { return }
        
        // 填充 6 张图片
        for i in 0..<6 {
            // 循环使用书页内容，如果书页少于 6 页
            let pageIndex = i % validPages.count
            let page = validPages[pageIndex]
            
            if page.shouldUseStoredSnapshot,
               let snapshotPath = page.snapshotPath,
               let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
                pageImages[i] = image
            }
        }
    }
    
    private func startAnimationSequence() {
        // 1. 移动到中心并放大
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            isMovingToCenter = true
        }
        
        // 2. 打开封面 (延迟 0.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.8)) {
                isOpening = true
            }
        }
        
        // 3. 随机翻页 (延迟 1.2s 开始，每隔 0.15s 翻一页)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            for i in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        pagesFlipped[i] = true
                    }
                }
            }
        }
        
        // 4. 动画结束，进入列表 (延迟 2.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            onAnimationComplete()
        }
    }
}

// MARK: - Subviews

struct BookCover: View {
    let book: BookGroup
    let width: CGFloat
    let height: CGFloat
    let color: Color
    var isFront: Bool = false
    var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            // Base Cover - 优先使用传入的图片，确保实时更新
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: width, height: height)
                    .cornerRadius(4)
            }
            
            // Shadow
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                .frame(width: width, height: height)
                .shadow(radius: 5)
            
            // 装饰线条 (仅封面)
            if isFront {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: width - 20, height: height - 20)
                
                Text(book.title)
                    .font(.custom("Didot", size: 24))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .padding()
                    .multilineTextAlignment(.center)
            }
            
            // 书脊纹理
            HStack {
                LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
                Spacer()
            }
        }
        .frame(width: width, height: height)
    }
}

struct BookPage: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color
    var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: width, height: height)
                .cornerRadius(2)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 1, y: 0)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width - 20, height: height - 20)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookGroup.self, configurations: config)
    let book = BookGroup(title: "Preview Book")
    
    return BookOpeningAnimationView(book: book) {
        print("Animation Completed")
    }
    .modelContainer(container)
}
