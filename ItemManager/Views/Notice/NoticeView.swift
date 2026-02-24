import SwiftUI
import AVKit

// MARK: - 公告视图
// 使用 notice_bg 作为边框，莫妮卡粉背景，圆角矩形
// 上方显示图片/视频，下方显示可滚动文字

struct NoticeView: View {
    let notice: Notice
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 媒体区域 (图片/视频)
            mediaSection
                .frame(maxWidth: .infinity)
                .aspectRatio(NoticeConfig.mediaAspectRatio, contentMode: .fit)
                .clipped()
            
            // 文字区域 (可滚动)
            textSection
        }
        .background(
            // 莫妮卡粉背景
            NoticeConfig.monicaPink
                .opacity(0.15)
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: NoticeConfig.cornerRadius))
        .overlay(
            // 边框图片
            Image("notice_bg")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .allowsHitTesting(false)
        )
    }
    
    // MARK: - 媒体区域
    @ViewBuilder
    private var mediaSection: some View {
        switch notice.mediaType {
        case .image:
            NoticeAsyncImage(urlString: notice.mediaURL)
                .aspectRatio(contentMode: .fill)

        case .video:
            if let urlString = notice.mediaURL,
               let url = URL(string: urlString) {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }

        case .none:
            placeholderView
        }
    }
    
    // MARK: - 文字区域
    private var textSection: some View {
        VStack(alignment: .center, spacing: 8) {
            // 标题
            Text(notice.title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            
            // 内容 (可滚动)
            ScrollView(.vertical, showsIndicators: true) {
                Text(notice.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: NoticeConfig.textMaxHeight)
            
            // 时间
            Text(notice.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(NoticeConfig.padding)
    }
    
    // MARK: - 占位视图
    private var placeholderView: some View {
        ZStack {
            Color.gray.opacity(0.1)
            
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

// MARK: - 公告列表视图
struct NoticeListView: View {
    @StateObject private var service = NoticeService.shared
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(service.notices, id: \.id) { notice in
                    NoticeView(notice: notice)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            service.setup(with: modelContext)
        }
        .refreshable {
            await service.fetchNotices()
        }
        .overlay {
            if service.isLoading {
                ProgressView()
            } else if service.notices.isEmpty {
                EmptyNoticeView()
            }
        }
    }
}

// MARK: - 空公告视图
struct EmptyNoticeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(NoticeConfig.monicaPink.opacity(0.5))
            
            Text("暂无公告")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Text("稍后再来看看吧~")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 预览
#Preview {
    let notice = Notice(
        title: "重要更新",
        content: "我们发布了新版本！这次更新包含了许多新功能和改进，包括：\n\n1. 全新的公告系统\n2. 优化的用户界面\n3. 修复了已知问题\n\n感谢您的支持！",
        mediaType: .none,
        priority: 1
    )
    
    NoticeView(notice: notice)
        .padding()
}
