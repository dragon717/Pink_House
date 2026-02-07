import SwiftUI

struct PetHomeView: View {
    @StateObject private var viewModel = PetViewModel()
    @StateObject private var audioManager = AudioManager.shared
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @Environment(\.scenePhase) var scenePhase
    @State private var isExpanded = false
    
    var body: some View {
        NavigationStack {
            if viewModel.status.petName == nil {
                PetNamingView(petName: Binding(
                    get: { viewModel.status.petName },
                    set: { viewModel.setPetName($0 ?? "") }
                )) { }
            } else {
                ZStack {
                // 背景
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 顶部状态栏和货币栏
                    VStack(spacing: 10) {
                    HStack(spacing: 20) {
                        StatusView(icon: "fork.knife", value: viewModel.status.hunger, color: .orange)
                        StatusView(icon: "shower.fill", value: viewModel.status.hygiene, color: .blue)
                    }
                    
                    HStack(spacing: 15) {
                        CurrencyView(type: .meowCoin, amount: viewModel.status.meowCoin) {
                            // 模拟充值喵币
                            viewModel.rechargeMeowCoin(amount: 100)
                        }
                        
                        CurrencyView(type: .fishCoin, amount: viewModel.status.fishCoin) {
                            // 模拟获取鱼币
                            viewModel.earnFishCoin(amount: 1000)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal)
                
                Spacer()
                
                // 中间萌宠区域
                ZStack {
                    PetVideoPlayer(
                        videoName: viewModel.currentState.videoFileName,
                        isLooping: viewModel.currentState.isLooping,
                        onFinished: {
                            viewModel.onAnimationFinished()
                        }
                    )
                    .frame(height: 400) // 根据视频比例调整
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // 期待状态 UI 反馈
                    if viewModel.currentState == .expecting {
                        VStack {
                            Image(systemName: "face.smiling.fill") // 临时表情
                                .font(.system(size: 50))
                                .foregroundColor(.yellow)
                                .shadow(radius: 5)
                            Spacer()
                        }
                        .padding(.top, 20)
                    }
                    
                    // 浮动文字层
                    ForEach(viewModel.floatingTexts) { textData in
                        Text(textData.text)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(textData.color)
                            .shadow(radius: 2)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                            .offset(y: -50) // 初始偏移
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
                        Spacer()
                        
                        // 语音识别文字气泡
                        if !viewModel.recognizedSpeechText.isEmpty {
                            Text(viewModel.recognizedSpeechText)
                                .font(.body)
                                .padding()
                                .background(Material.regular)
                                .cornerRadius(12)
                                .shadow(radius: 2)
                                .padding(.bottom, 20)
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // 互动状态指示器
                        if audioManager.isInteractionEnabled {
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
                            .padding(.bottom, 100) // 避免遮挡底部面板
                        }
                    }
                    .animation(.spring(), value: viewModel.recognizedSpeechText)
                    .animation(.spring(), value: audioManager.interactionState)
                    
                    // 接收拖拽区域
                    Color.clear
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, location in
                            guard let itemRawValue = items.first,
                                  let itemType = PetItemType(rawValue: itemRawValue) else { return false }
                            
                            viewModel.consumeItem(itemType)
                            viewModel.onDragEnded()
                            return true
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
                }
                
                // 底部操作面板 (可展开)
                PetBottomPanel(viewModel: viewModel, isExpanded: $isExpanded)
            }
            .navigationTitle(viewModel.status.petName ?? "萌宠")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Background Music Toggle (新增)
                        Button {
                            audioManager.isBackgroundMusicEnabled.toggle()
                        } label: {
                            Image(systemName: audioManager.isBackgroundMusicEnabled ? "music.note" : "music.note.list")
                                .foregroundStyle(audioManager.isBackgroundMusicEnabled ? .pink : .gray)
                        }

                        // Sound Toggle (原有)
                        Button {
                            soundManager.isSoundEnabled.toggle()
                        } label: {
                            Image(systemName: soundManager.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .foregroundStyle(soundManager.isSoundEnabled ? .blue : .gray)
                        }
                        
                        // Haptic Toggle
                        Button {
                            hapticManager.isHapticsEnabled.toggle()
                        } label: {
                            Image(systemName: hapticManager.isHapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                                .foregroundStyle(hapticManager.isHapticsEnabled ? .yellow : .gray)
                        }
                        
                        // Voice Interaction Toggle
                        Button {
                            audioManager.isInteractionEnabled.toggle()
                        } label: {
                            Image(systemName: audioManager.isInteractionEnabled ? "mic.fill" : "mic.slash.fill")
                                .foregroundStyle(audioManager.isInteractionEnabled ? .green : .gray)
                        }
                    }
                }
            }
            }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                viewModel.saveStatus()
            }
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



#Preview {
    PetHomeView()
}
