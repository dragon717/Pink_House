import SwiftUI

struct PetInteractionAreaView: View {
    @ObservedObject var viewModel: PetViewModel
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var soundManager = SoundManager.shared // 引入 SoundManager
    let videoHeight: CGFloat
    var isLandscape: Bool = false
    
    @State private var showStatusIcon = false
    @State private var videoProgress: Double = 0.0
    @State private var videoDuration: Double = 1.0
    @State private var isVisible: Bool = true // 追踪视图可见性以优化内存
    
    // Media State Manager
    @StateObject private var mediaStateManager = MediaStateManager.shared
    
    // 需要显示进度条的状态
    var shouldShowProgressBar: Bool {
        switch viewModel.currentState {
        case .eating, .cleaning, .playing, .sleeping:
            return true
        case .interacting:
            // 只有洗脸(grooming)是明确的进度任务，其他点击互动(interacting)通常很快且是反馈性质
            // 但如果用户把 interacting 也算作"洗脸"，那就显示。
            // 检查当前视频是否是 grooming
            return viewModel.currentVideoName == PetViewModel.PetVideoPaths.grooming
        default:
            return false
        }
    }
    
    var body: some View {
        ZStack {
            Group {
                if isVisible {
                    SeamlessVideoPlayer(
                        videoName: viewModel.currentVideoFileName, // 使用实际文件名前缀
                        isLooping: viewModel.isCurrentLooping, // 使用动态控制的 looping 属性
                        // listening 视频强制静音，避免录音时录入视频声音
                        isMuted: !soundManager.isSoundEnabled || viewModel.currentVideoName == PetViewModel.PetVideoPaths.listening,
                        volume: 0.6,
                        isPaused: mediaStateManager.isVideoPaused, // 根据媒体状态管理器暂停视频
                        onFinished: {
                            viewModel.onAnimationFinished()
                        },
                        onProgress: { current, duration in
                            self.videoProgress = current
                            self.videoDuration = duration
                        }
                    )
                } else {
                    Color.clear
                }
            }
            .frame(height: videoHeight) // 动态高度
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // 接收拖拽区域 (作为 Overlay 确保尺寸一致)
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // 按下或移动时触发
                                // 限制频率，或者 viewModel 内部有状态锁 (isTouching)
                                viewModel.startTouching(at: value.location, in: CGSize(width: videoHeight, height: videoHeight))
                            }
                            .onEnded { _ in
                                // 松开时触发
                                viewModel.stopTouching()
                            }
                    )
                    .dropDestination(for: String.self) { items, location in
                        print("DEBUG: Drop at \(location)")
                        guard let itemString = items.first else { return false }
                        
                        // 解析来源
                        if itemString.hasPrefix("shop:") {
                            let rawValue = String(itemString.dropFirst(5))
                            // 尝试使用 ConfigManager 获取物品定义 (新逻辑)
                            if let itemDef = PetConfigManager.shared.getItem(byId: rawValue) {
                                print("DEBUG: Drop source: Shop, Item: \(rawValue)")
                                viewModel.purchaseAndConsumeItem(itemDef)
                                viewModel.onDragEnded()
                                return true
                            }
                            // 兼容旧逻辑 (尝试作为 PetItemType 解析)
                            else if let itemType = PetItemType(rawValue: rawValue) {
                                print("DEBUG: Drop source: Shop, Legacy Item: \(rawValue)")
                                viewModel.purchaseAndConsumeItem(itemType)
                                viewModel.onDragEnded()
                                return true
                            }
                        } else if itemString.hasPrefix("inventory:") {
                            let rawValue = String(itemString.dropFirst(10))
                            // 尝试使用 ConfigManager 获取物品定义 (新逻辑)
                            if let itemDef = PetConfigManager.shared.getItem(byId: rawValue) {
                                print("DEBUG: Drop source: Inventory, Item: \(rawValue)")
                                viewModel.consumeItem(itemDef)
                                viewModel.onDragEnded()
                                return true
                            }
                            // 兼容旧逻辑
                            else if let itemType = PetItemType(rawValue: rawValue) {
                                print("DEBUG: Drop source: Inventory, Legacy Item: \(rawValue)")
                                viewModel.consumeItem(itemType)
                                viewModel.onDragEnded()
                                return true
                            }
                        } else {
                            // 兼容旧逻辑 (没有前缀的情况)
                            if let itemType = PetItemType(rawValue: itemString) {
                                print("DEBUG: Drop source: Unknown, Item: \(itemString)")
                                viewModel.consumeItem(itemType)
                                viewModel.onDragEnded()
                                return true
                            }
                        }
                        return false
                    } isTargeted: { isTargeted in
                        if isTargeted {
                            viewModel.onDragStarted()
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if viewModel.currentState == .expecting {
                                    viewModel.onDragEnded()
                                }
                            }
                        }
                    }
            )
            
            // 进度条显示 (在视频右下角)
            if shouldShowProgressBar && videoDuration > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            // 背景槽
                            Capsule()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 80, height: 8)
                            
                            // 进度
                            Capsule()
                                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 80 * CGFloat(min(max(videoProgress / videoDuration, 0), 1)), height: 8)
                                .animation(.linear(duration: 0.1), value: videoProgress)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            
            // 期待状态 UI 反馈
            if showStatusIcon && viewModel.currentState == .expecting {
                VStack {
                    HStack {
                        Image(systemName: "face.smiling.fill") // 临时表情
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)
                            .shadow(radius: 5)
                            .padding(16)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
            
            // 浮动文字层
            // 使用 drawingGroup 优化多层渲染性能
            ZStack {
                ForEach(viewModel.floatingTexts) { textData in
                    StyledFloatingText(text: textData.text, style: textData.style)
                        .transition(
                            .asymmetric(
                                // 入场：快速弹跳 (Pop)
                                insertion: .scale(scale: 0.5, anchor: .bottom) // 稍微调大初始比例，防止完全看不见
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 40)), // 从下方一点点弹出来
                                // 离场：飘散消失 (Disperse)
                                // 结合放大 (Scale Up) + 淡出 (Fade Out) + 轻微上浮 (Float Up)
                                // 模拟烟雾或云朵消散的感觉
                                removal: .opacity.animation(.easeOut(duration: 0.8))
                                    .combined(with: .scale(scale: 1.5).animation(.easeOut(duration: 0.8))) // 放大消散
                                    .combined(with: .offset(y: -40).animation(.easeOut(duration: 0.8))) // 轻微上浮
                            )
                        )
                        // 确保最新的在最上面 (ZStack 默认顺序也是如此，但为了保险)
                        .zIndex(Double(textData.id.hashValue))
                        // 位置由数据决定 (X随机，Y固定)
                        .offset(x: textData.offset.width, y: -120 + textData.offset.height)
                }
            }
            // 移除 drawingGroup，因为它可能导致转场动画中的视图不可见
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.floatingTexts.count)
            
            // 语音识别和互动状态层
            VStack {
                if isLandscape {
                    // 横屏模式：字幕在顶部
                    speechBubbleView()
                        .padding(.top, 0) // 调整位置更高一些
                    
                    Spacer()
                } else {
                    // 竖屏模式：字幕在底部
                    Spacer()
                    
                    speechBubbleView()
                        .padding(.bottom, 20)
                }
                
                // 互动状态指示器
                if audioManager.isInteractionEnabled {
                    HStack {
                        HStack {
                            Image(systemName: getInteractionIcon(for: audioManager.interactionState))
                                .symbolEffect(.bounce, value: audioManager.interactionState)
                            Text(getInteractionText(for: audioManager.interactionState))
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Capsule().fill(Color.blue.opacity(0.8)))
                        
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(), value: viewModel.recognizedSpeechText)
            .animation(.spring(), value: audioManager.interactionState)
        }
        .onChange(of: viewModel.currentState) { newState in
            if newState == .expecting {
                withAnimation {
                    showStatusIcon = true
                }
                // 3秒后自动消失
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if viewModel.currentState == .expecting {
                        withAnimation {
                            showStatusIcon = false
                        }
                    }
                }
            } else {
                withAnimation {
                    showStatusIcon = false
                }
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
    
    @ViewBuilder
    private func speechBubbleView() -> some View {
        if !viewModel.recognizedSpeechText.isEmpty {
            Text(viewModel.recognizedSpeechText)
                .font(.body)
                .padding()
                .background(Material.regular)
                .cornerRadius(12)
                .shadow(radius: 2)
                .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func getInteractionIcon(for state: PetInteractionState) -> String {
        switch state {
        case .idle: return "mic.slash"
        case .preparing: return "hourglass" // 准备中
        case .listening: return "ear"
        case .recording: return "waveform"
        case .processing: return "gear"
        case .playing: return "speaker.wave.3.fill"
        }
    }
    
    private func getInteractionText(for state: PetInteractionState) -> String {
        switch state {
        case .idle: return "未开启"
        case .preparing: return "准备中..."
        case .listening: return "倾听中..."
        case .recording: return "正在听..."
        case .processing: return "思考中..."
        case .playing: return "复述中..."
        }
    }
}

// MARK: - Components

struct StyledFloatingText: View {
    let text: String
    let style: FloatingTextStyle
    
    var body: some View {
        switch style {
        case .meowCoin, .fishCoin, .boneCoin:
            SparklingCurrencyText(text: text, style: style)
        default:
            StandardFloatingText(text: text, color: style.color)
        }
    }
}

struct StandardFloatingText: View {
    let text: String
    let color: Color
    
    @AppStorage("petBubbleSize") private var bubbleSize: PetBubbleSize = .medium
    @AppStorage("petBubbleUseCustomFont") private var useCustomFont: Bool = true
    @ObservedObject private var fontManager = FontManager.shared
    
    var font: Font {
        if useCustomFont, let fontName = fontManager.getCustomFontName() {
            return .custom(fontName, size: bubbleSize.fontSize)
        } else {
            return .system(size: bubbleSize.fontSize, weight: .black, design: .rounded)
        }
    }
    
    var body: some View {
        // 优化：使用 Shadow 替代 8向 Text 描边，大幅减少视图节点数量 (10 -> 2)
        // 虽然阴影稍微柔和一点，但性能提升巨大，适合小内存设备
        ZStack {
            // 主体 + 描边 (通过多重阴影模拟)
            Text(text)
                .font(font)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // 模拟描边：4个方向的硬阴影
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .shadow(color: .black, radius: 0, x: -1, y: -1)
                .shadow(color: .black, radius: 0, x: 1, y: -1)
                .shadow(color: .black, radius: 0, x: -1, y: 1)
                // 增加一层扩散阴影增加立体感
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
            
            // 顶部高光 (保留，增加精致感)
            Text(text)
                .font(font)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .mask(
                    Text(text)
                        .font(font)
                )
                .offset(y: -1)
                .allowsHitTesting(false)
        }
    }
}

struct SparklingCurrencyText: View {
    let text: String
    let style: FloatingTextStyle
    
    @State private var shineOffset: CGFloat = -1.0
    @AppStorage("petBubbleSize") private var bubbleSize: PetBubbleSize = .medium
    
    var config: (icon: String, color: Color, gradient: [Color]) {
        switch style {
        case .meowCoin:
            return (
                icon: "pawprint.circle.fill",
                color: .yellow,
                gradient: [.yellow, .orange, .yellow]
            )
        case .fishCoin:
            return (
                icon: "fish.circle.fill",
                color: .orange, // 铜色近似
                gradient: [Color(hex: "CD7F32"), Color(hex: "8B4513"), Color(hex: "CD7F32")] // 铜色渐变
            )
        case .boneCoin:
            return (
                icon: "circle.fill", // 基础图标，后面会特殊处理骨头
                color: Color(hex: "CD7F32"), // Bronze
                gradient: [Color(hex: "CD7F32"), Color(hex: "8B4513"), Color(hex: "CD7F32")]
            )
        default:
            return ("circle.fill", .white, [.white, .gray])
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // 文本部分
            StandardFloatingText(text: text, color: config.color)
            
            // 图标部分
            if style == .boneCoin {
                ZStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: bubbleSize.fontSize, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: config.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("🦴")
                        .font(.system(size: bubbleSize.fontSize * 0.6)) // 稍微小一点适配圆圈
                        .shadow(radius: 1)
                }
                .shadow(color: .black, radius: 1, x: 1, y: 1)
            } else {
                Image(systemName: config.icon)
                    .font(.system(size: bubbleSize.fontSize, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: config.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
                    .overlay(
                        // 闪光效果
                        GeometryReader { geo in
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.8), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .rotationEffect(.degrees(30))
                                .offset(x: shineOffset * geo.size.width * 2)
                        }
                        .mask(Image(systemName: config.icon).font(.system(size: 36, weight: .bold)))
                    )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                shineOffset = 1.0
            }
        }
    }
}
