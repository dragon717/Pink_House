import SwiftUI
import Combine

// MARK: - 请签视图

struct DivinationView: View {
    @State private var currentFortune: Fortune?
    @State private var videoState: VideoState = .initial
    @State private var showFortuneText = false
    
    enum VideoState {
        case initial      // 显示首帧
        case playing      // 播放视频中
        case finished     // 显示尾帧+签文
    }
    
    private let fortunes: [Fortune] = [
        Fortune(level: .supreme, text: "上上签", description: "财运亨通，福星高照", detail: "今日财运极佳，适合投资理财，可能会有意外之财降临。"),
        Fortune(level: .supreme, text: "上上签", description: "财源广进，日进斗金", detail: "财神眷顾，正财偏财皆旺，把握机会必有所获。"),
        Fortune(level: .supreme, text: "上上签", description: "富贵吉祥，万事顺遂", detail: "财星高照，事业财运双丰收，好运连连。"),
        Fortune(level: .good, text: "上签", description: "财运平稳，小有收获", detail: "今日财运不错，适合稳健理财，会有小惊喜。"),
        Fortune(level: .good, text: "上签", description: "积少成多，稳步前行", detail: "财运渐入佳境，坚持储蓄必有回报。"),
        Fortune(level: .good, text: "上签", description: "贵人相助，财运可期", detail: "有望得到贵人提携，财运有所提升。"),
    ]
    
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
                // 主要内容区域 - 使用固定布局避免按钮影响
                VStack(spacing: 0) {
                    Spacer()
                    
                    // 圆角矩形容器 - 固定位置，不受按钮影响
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
                                VerticalFortuneText(fortune: currentFortune ?? fortunes[0], containerSize: containerSize)
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
                    // 固定偏移量，确保位置不变
                    .offset(y: -40)
                    
                    Spacer()
                    
                    // 解签内容区域 - 固定高度占位，不受显示/隐藏影响
                    ZStack {
                        if videoState == .finished && showFortuneText, let fortune = currentFortune {
                            FortuneInterpretationView(fortune: fortune)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .frame(height: 100)
                    
                    // 按钮区域 - 固定高度占位，保持布局稳定
                    ZStack {
                        // 开始求签按钮
                        if videoState == .initial {
                            Button {
                                startDivination()
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
                                .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 26, showsDecoration: false) {
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                        
                        // 再求一签按钮
                        if videoState == .finished && showFortuneText {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showFortuneText = false
                                    videoState = .playing
                                }
                                // 重新随机选择
                                currentFortune = fortunes.randomElement()
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
                                .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 26, showsDecoration: false) {
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    // 固定高度，确保布局稳定
                    .frame(height: 80)
                    .padding(.bottom, 40)
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
    
    private func startDivination() {
        // 随机选择一个签
        currentFortune = fortunes.randomElement()
        
        // 播放成功反馈
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            videoState = .playing
        }
    }
}

// MARK: - 签的数据模型

struct Fortune: Identifiable {
    let id = UUID()
    let level: FortuneLevel
    let text: String
    let description: String
    let detail: String
}

enum FortuneLevel {
    case supreme  // 上上签
    case good     // 上签
}

// MARK: - 解签内容视图（Lolita风格）

struct FortuneInterpretationView: View {
    let fortune: Fortune
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.6))
                
                Text(fortune.description)
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 0.45))
                
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.6))
            }
            
            // 详细解签
            Text(fortune.detail)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Color(red: 0.5, green: 0.4, blue: 0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.96, blue: 0.98).opacity(0.95),
                            Color(red: 0.98, green: 0.94, blue: 0.96).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.9, green: 0.7, blue: 0.8).opacity(0.6),
                                    Color(red: 0.8, green: 0.6, blue: 0.7).opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(red: 0.8, green: 0.5, blue: 0.6).opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - 签条视图

struct FortuneStickView: View {
    let fortune: Fortune
    
    var body: some View {
        ZStack {
            // 签条主体
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.9, blue: 0.8),
                            Color(red: 0.9, green: 0.85, blue: 0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 40, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.6, green: 0.4, blue: 0.2), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            
            // 签文
            Text(fortune.text.prefix(2))
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.6, green: 0.2, blue: 0.1))
                .rotationEffect(.degrees(-90))
        }
    }
}
