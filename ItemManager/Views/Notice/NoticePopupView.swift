import SwiftUI
import AVKit
import Combine

// MARK: - 公告弹窗视图
// 置于 ZStack 最顶部，下方有灰色蒙版，点击蒙版关闭

struct NoticePopupView: View {
    let notice: Notice
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            // 灰色蒙版
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            // 公告内容
            NoticeCardView(notice: notice)
                .frame(maxWidth: 340)
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .onTapGesture {
                    // 点击公告内容不关闭
                }
        }
        .zIndex(999) // 置于最顶部
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - 公告卡片视图 (弹窗专用)
struct NoticeCardView: View {
    let notice: Notice
    
    var body: some View {
        ZStack {
            // 第1层：莫妮卡浅粉背景（圆角矩形）- 使用纯色
            RoundedRectangle(cornerRadius: NoticeConfig.cornerRadius)
                .fill(NoticeConfig.monicaPink)

            // 第2层：内容层
            VStack(spacing: 0) {
                // 媒体区域 - 上半部分
                mediaSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(NoticeConfig.borderPadding)
                    .padding(.bottom, 0)

                // 文字区域 - 下半部分
                textSection
                    .padding(NoticeConfig.borderPadding)
                    .padding(.top, 0)
            }

            // 第3层：边框图片（最上层）
            Image("notice_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .allowsHitTesting(false)
        }
        .aspectRatio(NoticeConfig.cardAspectRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    @ViewBuilder
    private var mediaSection: some View {
        GeometryReader { geometry in
            Group {
                switch notice.mediaType {
                case .image:
                    NoticeAsyncImage(urlString: notice.mediaURL)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                case .video:
                    if let urlString = notice.mediaURL,
                       let url = URL(string: urlString) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .aspectRatio(contentMode: .fit)
                    } else {
                        placeholderView
                    }

                case .none:
                    placeholderView
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    private var textSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(notice.title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            
            ScrollView(.vertical, showsIndicators: true) {
                Text(notice.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: NoticeConfig.textMaxHeight)
            
            Text(notice.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            Color.clear

            VStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(NoticeConfig.monicaPink)

                Text("公告")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 异步加载图片视图
struct NoticeAsyncImage: View {
    let urlString: String?
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.clear)
            } else if isLoading {
                ProgressView()
            } else {
                // 加载失败显示占位图
                ZStack {
                    Color.gray.opacity(0.1)
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: urlString) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        guard let urlString = urlString, !urlString.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true

        // 异步加载图片
        Task {
            if let image = await NoticeImageLoader.shared.loadImage(from: urlString) {
                await MainActor.run {
                    self.image = image
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - 图片加载器
@MainActor
class NoticeImageLoader {
    static let shared = NoticeImageLoader()
    private var cache: [String: UIImage] = [:]

    private init() {}

    func loadImage(from urlString: String) async -> UIImage? {
        // 检查缓存
        if let cached = cache[urlString] {
            return cached
        }

        // 处理内置图片 (builtin:// 前缀)
        if urlString.hasPrefix("builtin://") {
            let imageName = String(urlString.dropFirst("builtin://".count))
            if let image = UIImage(named: imageName) {
                cache[urlString] = image
                return image
            } else {
                print("❌ 无法加载内置图片: \(imageName)")
                return nil
            }
        }

        // 处理普通文件路径
        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let data = try await Task.detached {
                try Data(contentsOf: url)
            }.value

            if let image = UIImage(data: data) {
                cache[urlString] = image
                return image
            }
        } catch {
            print("❌ 加载图片失败: \(error)")
        }

        return nil
    }
}

// MARK: - 公告弹窗管理器
@MainActor
class NoticePopupManager: ObservableObject {
    static let shared = NoticePopupManager()

    @Published var currentNotice: Notice?
    @Published var isShowing = false

    private let shownNoticeIDsKey = "shownNoticeIDs"
    private let lastResetTimeKey = "noticeLastResetTime"
    private let service = NoticeService.shared

    private init() {}

    // 获取已展示过的公告ID列表
    private var shownNoticeIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: shownNoticeIDsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: shownNoticeIDsKey)
        }
    }

    // 获取上次重置时间
    var lastResetTime: Date? {
        get {
            UserDefaults.standard.object(forKey: lastResetTimeKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastResetTimeKey)
        }
    }

    // 检查公告是否已展示过
    func hasShownNotice(_ notice: Notice) -> Bool {
        print("📢 hasShownNotice: notice.id=\(notice.id), createdAt=\(notice.createdAt), lastResetTime=\(String(describing: lastResetTime)), shownNoticeIDs=\(shownNoticeIDs)")
        // 如果重置过，只检查重置时间之后的记录
        if let resetTime = lastResetTime {
            // 如果公告是在重置之后创建的，或者没有展示记录，则需要展示
            if notice.createdAt > resetTime {
                print("📢 公告在重置后创建，需要展示")
                return false
            }
        }
        let hasShown = shownNoticeIDs.contains(notice.id.uuidString)
        print("📢 hasShown: \(hasShown)")
        return hasShown
    }

    // 标记公告为已展示
    func markNoticeAsShown(_ notice: Notice) {
        var ids = shownNoticeIDs
        if !ids.contains(notice.id.uuidString) {
            ids.append(notice.id.uuidString)
            shownNoticeIDs = ids
        }
    }

    // 尝试展示公告（只展示未展示过的）
    func tryShowNotice(_ notice: Notice) {
        print("📢 tryShowNotice called for: \(notice.title)")
        guard !hasShownNotice(notice) else {
            print("📢 公告已展示过，跳过")
            return
        }

        print("📢 显示公告弹窗")
        currentNotice = notice
        isShowing = true
        markNoticeAsShown(notice)
    }

    // 尝试展示最新公告
    func tryShowLatestNotice() {
        print("📢 tryShowLatestNotice called, notices count: \(service.notices.count)")
        guard let latestNotice = service.notices.first else {
            print("📢 没有公告可显示")
            return
        }
        print("📢 最新公告: \(latestNotice.title), id: \(latestNotice.id)")
        print("📢 hasShownNotice: \(hasShownNotice(latestNotice))")
        tryShowNotice(latestNotice)
    }

    // 关闭弹窗
    func dismiss() {
        isShowing = false
        currentNotice = nil
    }

    // 重置所有展示记录（用于测试）
    func resetShownHistory() {
        shownNoticeIDs = []
        lastResetTime = Date()
    }
}

// MARK: - 公告弹窗修饰符
struct NoticePopupModifier: ViewModifier {
    @StateObject private var manager = NoticePopupManager.shared
    @StateObject private var service = NoticeService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var hasAttemptedShow = false

    func body(content: Content) -> some View {
        ZStack {
            content

            if manager.isShowing, let notice = manager.currentNotice {
                NoticePopupView(notice: notice) {
                    manager.dismiss()
                }
            }
        }
        .onAppear {
            print("📢 NoticePopupModifier onAppear")
            service.setup(with: modelContext)
            // 每次视图出现时检查是否需要重置 hasAttemptedShow
            checkAndResetAttemptState()
        }
        .onChange(of: service.notices) { _, newNotices in
            print("📢 service.notices changed: count=\(newNotices.count), hasAttemptedShow=\(hasAttemptedShow)")
            // 等待公告数据加载完成后再尝试展示
            if !hasAttemptedShow && !newNotices.isEmpty {
                hasAttemptedShow = true
                // 记录本次尝试的时间戳
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastNoticeAttemptTime")
                print("📢 准备显示公告，延迟 0.5 秒...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("📢 调用 tryShowLatestNotice()")
                    manager.tryShowLatestNotice()
                }
            }
        }
    }

    // 检查是否需要重置尝试状态（当重置历史记录后）
    private func checkAndResetAttemptState() {
        let lastResetTime = NoticePopupManager.shared.lastResetTime?.timeIntervalSince1970 ?? 0
        let lastAttemptTime = UserDefaults.standard.double(forKey: "lastNoticeAttemptTime")

        print("📢 checkAndResetAttemptState: lastResetTime=\(lastResetTime), lastAttemptTime=\(lastAttemptTime)")

        // 如果重置时间晚于上次尝试时间，说明需要重新尝试显示
        if lastResetTime > lastAttemptTime {
            print("📢 检测到重置操作，重置 hasAttemptedShow")
            hasAttemptedShow = false
        }
    }
}

// MARK: - View 扩展
extension View {
    func noticePopup() -> some View {
        modifier(NoticePopupModifier())
    }
}

// MARK: - 预览
#Preview {
    let notice = Notice(
        title: "重要更新",
        content: "我们发布了新版本！这次更新包含了许多新功能和改进。\n\n1. 全新的公告系统\n2. 优化的用户界面\n3. 修复了已知问题\n\n感谢您的支持！",
        mediaType: .none,
        priority: 1
    )
    
    NoticePopupView(notice: notice) {}
}
