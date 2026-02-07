import SwiftUI

struct PetInteractionAreaView: View {
    @ObservedObject var viewModel: PetViewModel
    @ObservedObject var audioManager: AudioManager
    let videoHeight: CGFloat
    var isLandscape: Bool = false
    
    @State private var showStatusIcon = false
    
    var body: some View {
        ZStack {
            PetVideoPlayer(
                videoName: viewModel.currentState.videoFileName,
                isLooping: viewModel.currentState.isLooping,
                onFinished: {
                    viewModel.onAnimationFinished()
                }
            )
            .frame(height: videoHeight) // 动态高度
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // 接收拖拽区域 (作为 Overlay 确保尺寸一致)
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
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
            ForEach(viewModel.floatingTexts) { textData in
                Text(textData.text)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(textData.color)
                    .shadow(radius: 2)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    .offset(y: -120) // 初始偏移
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.5)) {
                            // 这里可以通过 viewModel 控制更复杂的动画，
                            // 或者在 View 内部做一个局部状态来控制 offset，
                            // 简单起见，这里只做出现和消失的 transition，位置由 ZStack 决定
                        }
                    }
            }
            
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
        case .listening: return "ear"
        case .recording: return "waveform"
        case .processing: return "gear"
        case .playing: return "speaker.wave.3.fill"
        }
    }
    
    private func getInteractionText(for state: PetInteractionState) -> String {
        switch state {
        case .idle: return "未开启"
        case .listening: return "倾听中..."
        case .recording: return "正在听..."
        case .processing: return "思考中..."
        case .playing: return "复述中..."
        }
    }
}
