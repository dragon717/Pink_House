import SwiftUI
import AVKit

// MARK: - 请签视频播放器视图
struct DivinationVideoView: View {
    let fortune: Fortune
    let onFinished: () -> Void
    let onReplay: () -> Void
    
    @State private var videoState: VideoState = .initial
    @State private var showFortuneText = false
    
    enum VideoState {
        case initial      // 显示首帧
        case playing      // 播放视频中
        case finished     // 显示尾帧+签文
    }
    
    // 圆角大小
    private let cornerRadius: CGFloat = 20
    // 容器尺寸比例（相对于屏幕宽度）
    private let containerScale: CGFloat = 0.75
    // 最大容器尺寸
    private let maxContainerSize: CGFloat = 360
    // 最小容器尺寸
    private let minContainerSize: CGFloat = 280
    
    var body: some View {
        GeometryReader { geometry in
            let containerSize = calculateContainerSize(for: geometry.size)
            
            ZStack {
                // 主要内容区域
                VStack(spacing: 0) {
                    Spacer()
                    
                    // 圆角矩形容器
                    ZStack {
                        // 初始状态：显示首帧
                        if videoState == .initial {
                            Image("divination_first_frame")
                                .resizable()
                                .scaledToFill()
                                .frame(width: containerSize, height: containerSize)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .transition(.opacity)
                        }
                        
                        // 播放中：显示视频
                        if videoState == .playing {
                            DivinationVideoPlayer(
                                videoName: "请签",
                                onFinished: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        videoState = .finished
                                    }
                                    // 延迟显示签文
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                            showFortuneText = true
                                        }
                                    }
                                }
                            )
                            .frame(width: containerSize, height: containerSize)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .transition(.opacity)
                        }
                        
                        // 结束状态：显示尾帧 + 签文
                        if videoState == .finished {
                            // 尾帧背景
                            Image("divination_last_frame")
                                .resizable()
                                .scaledToFill()
                                .frame(width: containerSize, height: containerSize)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .transition(.opacity)
                            
                            // 半透明遮罩，让签文更清晰
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.ultraThinMaterial.opacity(0.3))
                                .frame(width: containerSize, height: containerSize)
                            
                            // 竖向签文（居中偏上）
                            if showFortuneText {
                                VerticalFortuneText(fortune: fortune, containerSize: containerSize)
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }
                        
                        // 边框装饰
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.9, green: 0.75, blue: 0.4),
                                        Color(red: 0.7, green: 0.5, blue: 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: containerSize, height: containerSize)
                        
                        // 外发光阴影
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color(red: 0.9, green: 0.75, blue: 0.4).opacity(0.3), lineWidth: 8)
                            .frame(width: containerSize + 6, height: containerSize + 6)
                            .blur(radius: 4)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                    
                    Spacer()
                    
                    // 按钮区域
                    if videoState == .initial {
                        // 开始求签按钮
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                videoState = .playing
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                Text("开始求签")
                            }
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.8, green: 0.3, blue: 0.3).opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.bottom, 40)
                        .transition(.opacity)
                    } else if videoState == .finished && showFortuneText {
                        // 再求一签按钮
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showFortuneText = false
                                videoState = .playing
                            }
                            onReplay()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("再求一签")
                            }
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.8, green: 0.3, blue: 0.3).opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.bottom, 40)
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    // 计算自适应容器尺寸
    private func calculateContainerSize(for size: CGSize) -> CGFloat {
        let minDimension = min(size.width, size.height)
        let calculatedSize = minDimension * containerScale
        return min(max(calculatedSize, minContainerSize), maxContainerSize)
    }
}

// MARK: - 竖向签文视图
struct VerticalFortuneText: View {
    let fortune: Fortune
    let containerSize: CGFloat
    @State private var customFontName: String?
    
    // 根据容器尺寸计算字体大小
    private var titleFontSize: CGFloat {
        containerSize * 0.18
    }
    
    var body: some View {
        // 竖向文字 - 只显示签等级，背景透明无框，黑墨色
        VerticalText(
            text: fortune.text,
            fontName: customFontName,
            fontSize: titleFontSize,
            color: Color(red: 0.15, green: 0.15, blue: 0.15) // 黑墨色
        )
        .shadow(color: .white.opacity(0.6), radius: 1.5, x: 0.5, y: 0.5)
        .shadow(color: .black.opacity(0.2), radius: 1.5, x: -0.5, y: -0.5)
        .onAppear {
            // 注册并获取自定义字体
            customFontName = registerCustomFont()
        }
    }
    
    private func registerCustomFont() -> String? {
        // 优先使用临海隶书
        let fontNames = ["临海隶书", "LinhaiLishu", "linhailishu"]
        
        for fontName in fontNames {
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf") ??
                             Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "asserts") {
                return registerFont(from: fontURL)
            }
        }
        
        print("DivinationVideoView: Could not find 临海隶书.ttf")
        return nil
    }
    
    private func registerFont(from url: URL) -> String? {
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider),
              let postScriptName = font.postScriptName as String? else {
            print("DivinationVideoView: Failed to parse font file")
            return nil
        }
        
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            print("DivinationVideoView: Successfully registered font: \(postScriptName)")
        } else {
            print("DivinationVideoView: Font may already be registered")
        }
        
        return postScriptName
    }
}

// MARK: - 竖向文字组件
struct VerticalText: View {
    let text: String
    let fontName: String?
    let fontSize: CGFloat
    let color: Color
    
    var body: some View {
        VStack(spacing: fontSize * 0.15) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(fontName != nil ?
                        .custom(fontName!, size: fontSize) :
                        .system(size: fontSize, weight: .bold, design: .serif)
                    )
                    .foregroundStyle(color)
                    .shadow(color: .white.opacity(0.5), radius: 0.5, x: 0.5, y: 0.5)
            }
        }
    }
}

// MARK: - 请签视频播放器（单次播放）
struct DivinationVideoPlayer: UIViewControllerRepresentable {
    let videoName: String
    let onFinished: () -> Void
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        
        // 设置播放器
        if let url = findVideoURL() {
            let player = AVPlayer(url: url)
            controller.player = player
            
            // 监听播放结束
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                onFinished()
            }
            
            player.play()
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 不需要更新
    }
    
    private func findVideoURL() -> URL? {
        // 1. 尝试在 Bundle 根目录查找
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mov") {
            return url
        }
        
        // 2. 尝试在 asserts 子目录查找
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mov", subdirectory: "asserts") {
            return url
        }
        
        // 3. 尝试查找无后缀的文件
        if let url = Bundle.main.url(forResource: videoName, withExtension: nil) {
            return url
        }
        
        if let url = Bundle.main.url(forResource: videoName, withExtension: nil, subdirectory: "asserts") {
            return url
        }
        
        print("DivinationVideoPlayer: Could not find video: \(videoName)")
        return nil
    }
}

// MARK: - 预览
#Preview {
    DivinationVideoView(
        fortune: Fortune(
            level: .supreme,
            text: "上上签",
            description: "财运亨通",
            detail: "今日财运极佳，适合投资理财"
        ),
        onFinished: {},
        onReplay: {}
    )
}
