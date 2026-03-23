import SwiftUI
import AVKit
import Combine
import UIKit

// MARK: - 公告弹窗视图
// 置于 ZStack 最顶部，下方有灰色蒙版，点击蒙版关闭

struct NoticePopupView: View {
    let notice: Notice
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        // 全局居中布局：公告内容在灰色蒙版中水平和垂直双轴居中
        ZStack(alignment: .center) {
            // 灰色蒙版
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            // 公告内容 - 全局居中：使用 ZStack alignment 实现水平和垂直双轴居中
            NoticeCardView(notice: notice)
                .frame(maxWidth: 320, maxHeight: 500)
                .padding(.horizontal, 32)
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
    
    // 根据屏幕尺寸计算卡片宽度
    private func cardWidth(for size: CGSize) -> CGFloat {
        let horizontalPadding: CGFloat = 32 // 左右边距各 16pt
        let maxCardWidth: CGFloat = 320
        let minCardWidth: CGFloat = 260
        
        // 可用宽度 = 屏幕宽度 - 左右边距
        let availableWidth = size.width - (horizontalPadding * 2)
        
        if size.width < size.height {
            // 竖屏：使用屏幕宽度的 85%，确保有足够边距显示完整边框
            let preferredWidth = min(size.width * 0.85, maxCardWidth)
            return max(minCardWidth, min(preferredWidth, availableWidth))
        } else {
            // 横屏：使用固定最大宽度
            return min(maxCardWidth, availableWidth)
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
    @Environment(\.colorScheme) private var colorScheme

    // 背景色统一使用 #FFE6EF
    private var backgroundColor: Color {
        Color(hex: "FFE6EF")
    }

    var body: some View {
        GeometryReader { geometry in
            // 全局居中布局：整个卡片在父容器中水平和垂直双轴居中
            ZStack {
                // 第1层：背景色（圆角矩形）
                RoundedRectangle(cornerRadius: NoticeConfig.cornerRadius)
                    .fill(backgroundColor)

                // 第2层：内容层（留出边框空间）
                VStack(spacing: 0) {
                    // 媒体区域 - 上半部分
                    mediaSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(NoticeConfig.contentPadding)
                        .padding(.bottom, 0)

                    // 文字区域 - 下半部分
                    textSection
                        .padding(NoticeConfig.contentPadding)
                        .padding(.top, 0)
                }
                .padding(NoticeConfig.borderPadding) // 为边框留出空间

                // 第3层：边框图片（最上层）
                Image("notice_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)
            }
            .aspectRatio(NoticeConfig.cardAspectRatio, contentMode: .fit)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
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
    
    // 文字统一使用白色（背景是粉色 #FFE6EF）
    private var titleColor: Color {
        .black
    }

    private var contentColor: Color {
        .black
    }

    private var dateColor: Color {
        .black
    }

    private var textSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(notice.title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(titleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.vertical, showsIndicators: true) {
                Text(notice.content)
                    .font(.subheadline)
                    .foregroundColor(contentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: NoticeConfig.textMaxHeight)

            Text(notice.createdAt, style: .date)
                .font(.caption2)
                .foregroundColor(dateColor)
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

    private let readStatusService = NoticeReadStatusService.shared
    private let service = NoticeService.shared

    private init() {}

    // 获取上次重置时间（从已读状态服务）
    var lastResetTime: Date? {
        return readStatusService.lastResetTime
    }

    // 检查公告是否已展示过
    func hasShownNotice(_ notice: Notice) -> Bool {
        print("📢 hasShownNotice: notice.id=\(notice.id), createdAt=\(notice.createdAt), lastResetTime=\(String(describing: lastResetTime))")
        let hasShown = readStatusService.hasReadNotice(notice)
        print("📢 hasShown: \(hasShown)")
        return hasShown
    }

    // 标记公告为已展示
    func markNoticeAsShown(_ notice: Notice) {
        readStatusService.markAsRead(notice)
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
        readStatusService.resetReadHistory()
        UserDefaults.standard.removeObject(forKey: NoticePopupModifier.lastAttemptedNoticeKey)
        NotificationCenter.default.post(name: .noticeReadHistoryDidReset, object: nil)
    }
}

// MARK: - 公告弹窗修饰符
struct NoticePopupModifier: ViewModifier {
    static let lastAttemptedNoticeKey = "lastAttemptedNoticeKey"

    @StateObject private var manager = NoticePopupManager.shared
    @StateObject private var service = NoticeService.shared
    @StateObject private var readStatusService = NoticeReadStatusService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var hasSyncedReadStatus = false
    @State private var sessionAttemptedNoticeKey: String?

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
            syncReadStatus()
        }
        .onChange(of: service.notices) { _, newNotices in
            print("📢 service.notices changed: count=\(newNotices.count), hasSyncedReadStatus=\(hasSyncedReadStatus), isSyncing=\(service.isSyncing)")
            attemptShowLatestNoticeIfNeeded()
        }
        .onChange(of: manager.isShowing) { _, isShowing in
            if isShowing {
                print("📢 公告弹窗已显示")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await service.syncIfNeeded(force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noticeReadHistoryDidReset)) { _ in
            sessionAttemptedNoticeKey = nil
            attemptShowLatestNoticeIfNeeded()
        }
    }
    
    // 同步已读状态
    private func syncReadStatus() {
        Task {
            await readStatusService.syncFromCloud()
            hasSyncedReadStatus = true
            attemptShowLatestNoticeIfNeeded()
        }
    }

    private func attemptShowLatestNoticeIfNeeded() {
        guard hasSyncedReadStatus, !service.isSyncing else { return }
        guard let latestNotice = service.notices.first else { return }

        let latestNoticeKey = latestNotice.readTrackingKey
        if sessionAttemptedNoticeKey == latestNoticeKey {
            return
        }

        let lastAttemptedNoticeKey = UserDefaults.standard.string(forKey: Self.lastAttemptedNoticeKey)
        if lastAttemptedNoticeKey == latestNoticeKey, manager.hasShownNotice(latestNotice) {
            sessionAttemptedNoticeKey = latestNoticeKey
            return
        }

        sessionAttemptedNoticeKey = latestNoticeKey
        UserDefaults.standard.set(latestNoticeKey, forKey: Self.lastAttemptedNoticeKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            manager.tryShowNotice(latestNotice)
        }
    }
}

extension Notification.Name {
    static let noticeReadHistoryDidReset = Notification.Name("noticeReadHistoryDidReset")
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
