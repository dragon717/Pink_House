import SwiftUI
import SwiftData

struct PetHomeView: View {
    @StateObject private var viewModel = PetViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var clothings: [Clothing]
    
    @StateObject private var audioManager = AudioManager.shared
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @Environment(\.scenePhase) var scenePhase
    @State private var panelState: PanelState = .hidden
    @State private var showRenameAlert = false
    @State private var showNoCardAlert = false
    @State private var showJobSelection = false
    @State private var newName = ""
    @State private var showAdoptionView = false // 领养界面
    
    @State private var showDebugDialogueInput = false
    @State private var debugInputText = ""
    @State private var showChatView = false // ChatView State
    @State private var showMicMenu = false // Mic Menu State
    @State private var showVIPView = false // VIP View State
    
    var body: some View {
        Group {
            // 如果没有领养任何宠物，直接显示领养界面
            if viewModel.status.ownedPetIds.isEmpty {
                NavigationStack {
                    PetAdoptionView(viewModel: viewModel)
                }
            } else {
                NavigationStack {
                    // 原有内容包裹在 ZStack 中
                    ZStack {
                        GeometryReader { geo in
                            let isLandscape = geo.size.width > geo.size.height
                            // 动态计算视频高度：
                            // 横屏：取屏幕短边的 80%
                            // 竖屏：取屏幕宽度的 90%，但限制最大值（450）和最小值（280），同时考虑到屏幕高度的限制，避免遮挡
                            let screenHeight = geo.size.height
                            let screenWidth = geo.size.width
                            
                            let videoHeight: CGFloat = {
                                if isLandscape {
                                    return max(100, min(screenWidth, screenHeight) * 0.8)
                                } else {
                                    // 预留顶部 Header (约120) 和底部 Panel Collapsed (约220) 的空间
                                    // 增加预留空间，避免小屏幕太挤
                                    let availableHeight = screenHeight - 340
                                    // 稍微减小宽度占比，避免左右太满
                                    let idealSize = screenWidth * 0.85
                                    // 取 宽度适配 和 高度适配 的较小值，确保不溢出
                                    // 确保不小于 100，避免负数导致 Crash
                                    return max(100, min(idealSize, availableHeight, 450))
                                }
                            }()
                            
                            ZStack {
                                // 背景
                                LiquidBackground()
                                    .ignoresSafeArea()
                                
                                // 通用布局逻辑：
                                // 1. 底层：视频区域 (绝对居中)
                                PetInteractionAreaView(
                                    viewModel: viewModel,
                                    audioManager: audioManager,
                                    videoHeight: videoHeight,
                                    isLandscape: isLandscape
                                )
                                .frame(width: videoHeight, height: videoHeight)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                // 动态调整偏移，小屏幕减少偏移
                                .offset(y: isLandscape ? -20 : -screenHeight * 0.05)
                                
                                // 2. 上层 UI：Header
                                if isLandscape {
                                    HStack(spacing: 0) {
                                        // 左侧：状态栏和货币栏
                                        PetStatusHeaderView(viewModel: viewModel, isLandscape: true)
                                            .frame(width: 120)
                                            .padding(.leading, 10)
                                        
                                        Spacer()
                                    }
                                } else {
                                    VStack(spacing: 0) {
                                        // 顶部状态栏和货币栏
                                        PetStatusHeaderView(viewModel: viewModel, isLandscape: false)
                                        
                                        Spacer()
                                    }
                                }
                                
                                // 3. 顶层 UI：底部操作面板 (可展开)
                                PetBottomPanel(viewModel: viewModel, panelState: $panelState, showRenameAlert: $showRenameAlert, isLandscape: isLandscape)
                                
                                // 4. 悬浮按钮 (仅在隐藏状态且竖屏显示)
                                if !isLandscape && panelState == .hidden {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Button(action: {
                                                showDebugDialogueInput = true
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                                        .font(.system(size: 20))
                                                    Text("对话")
                                                    .font(.system(size: 16, weight: .bold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color(red: 0.80, green: 0.65, blue: 0.80)) // 莫妮卡紫
                                            .clipShape(Capsule())
                                            .shadow(radius: 4, x: 0, y: 2)
                                        }
                                        .padding(.leading, 20)
                                        .padding(.bottom, 100)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            withAnimation(.spring()) {
                                                panelState = .collapsed
                                            }
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "backpack.fill")
                                                    .font(.system(size: 20))
                                                Text("背包")
                                                    .font(.system(size: 16, weight: .bold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color(red: 0.62, green: 0.74, blue: 0.82)) // 莫妮卡蓝
                                            .clipShape(Capsule())
                                            .shadow(radius: 4, x: 0, y: 2)
                                            }
                                            .padding(.trailing, 20)
                                            .padding(.bottom, 100) // 稍微高一点，避免被 HomeIndicator 遮挡
                                        }
                                    }
                                    .transition(.opacity)
                                }
                                
                                // Debug: 粉色气泡对话输入框
                                if showDebugDialogueInput {
                                    Color.black.opacity(0.3)
                                        .ignoresSafeArea()
                                        .onTapGesture {
                                            showDebugDialogueInput = false
                                        }
                                        .transition(.opacity)
                                    
                                    VStack {
                                        Spacer()
                                        PetDialogueInputView(text: $debugInputText, onSend: {
                                            if !debugInputText.isEmpty {
                                                viewModel.debugTriggerDialogue(text: debugInputText)
                                                debugInputText = ""
                                                showDebugDialogueInput = false
                                            }
                                        })
                                        .padding(.bottom, 20)
                                        .padding(.horizontal, 16)
                                    }
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .zIndex(100) // 确保在最上层
                                }
                            }
                        }
                    }
                .alert("修改名字", isPresented: $showRenameAlert) {
                    TextField("输入新名字", text: $newName)
                    Button("取消", role: .cancel) { }
                    Button("确定") {
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            _ = viewModel.useRenameCard(newName: trimmed)
                        }
                    }
                } message: {
                    Text("改名将消耗一个改名项圈")
                }
                .alert("缺少道具", isPresented: $showNoCardAlert) {
                    Button("这都要买！", role: .cancel) { }
                } message: {
                    Text("修改名字需要消耗改名项圈，请前往商店购买喵～")
                }

                .sheet(isPresented: $showVIPView) {
                    NavigationStack {
                        VIPCenterView()
                    }
                }
                .sheet(isPresented: $showJobSelection) {
                    PetJobSelectionView(viewModel: viewModel, isPresented: $showJobSelection)
                        .presentationDetents([.medium])
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            // 切换萌宠 (如果有2只及以上)
                            if viewModel.status.ownedPetIds.count >= 2 {
                                Menu("切换伙伴") {
                                    ForEach(PetCharacter.allCases) { pet in
                                        if viewModel.status.ownedPetIds.contains(pet.id) {
                                            Button {
                                                viewModel.switchPet(pet)
                                            } label: {
                                                HStack {
                                                    let pName = viewModel.status.petNames[pet.id] ?? ""
                                                    let nameText = pName.isEmpty ? "" : " - \"\(pName)\""
                                                    Text("\(pet.displayName)\(nameText)")
                                                    if viewModel.status.selectedPetId == pet.id {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // 再要x胎
                            if viewModel.status.ownedPetIds.count < PetCharacter.allCases.count {
                                Button {
                                    showAdoptionView = true
                                } label: {
                                    Label("再要\(viewModel.nextAdoptionNumberText)胎", systemImage: "plus.circle")
                                }
                                
                                Divider()
                            }
                            
                            Button {
                                if viewModel.hasRenameCard() {
                                    newName = viewModel.status.petName ?? ""
                                    showRenameAlert = true
                                } else {
                                    showNoCardAlert = true
                                }
                            } label: {
                                Label("修改名字", systemImage: "pencil")
                            }
                            
                            if viewModel.status.currentJob != .none {
                                Button {
                                    viewModel.stopJob()
                                } label: {
                                    Label("结束打工", systemImage: "briefcase.fill")
                                }
                            } else {
                                Button {
                                    showJobSelection = true
                                } label: {
                                    Label("送去打工", systemImage: "briefcase")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.currentPet == .maomao ? "dog.fill" : "cat.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.orange)
                                
                                let displayName = viewModel.status.displayName
                                
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    if viewModel.status.currentJob != .none {
                                        Text(viewModel.status.currentJob.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .padding(4)
                            .contentShape(Rectangle()) // 增大点击热区
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            // Chat Button (New)
                        Button {
                            showChatView = true
                        } label: {
                            Image(systemName: "book.closed")
                                .foregroundStyle(.purple)
                        }
                            
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
                                if audioManager.isInteractionEnabled {
                                    audioManager.isInteractionEnabled = false
                                } else {
                                    showMicMenu = true
                                }
                            } label: {
                                Image(systemName: audioManager.isInteractionEnabled ? "mic.fill" : "mic.slash.fill")
                                    .foregroundStyle(audioManager.isInteractionEnabled ? .green : .gray)
                            }
                            .confirmationDialog("选择互动模式", isPresented: $showMicMenu, titleVisibility: .visible) {
                                Button("模仿你说话") {
                                    viewModel.isAIMode = false
                                    AudioManager.shared.isEchoModeEnabled = true // Enable Echo
                                    audioManager.isInteractionEnabled = true
                                }
                                
                                Button("跟“\(viewModel.status.displayName)”聊天") {
                                    if VIPManager.shared.isVIP {
                                        viewModel.isAIMode = true
                                        AudioManager.shared.isEchoModeEnabled = false // Disable Echo, AI will speak
                                        // 直接开启，不再弹二次确认
                                        audioManager.isInteractionEnabled = true
                                    } else {
                                        showVIPView = true
                                    }
                                }
                                
                                Button("取消", role: .cancel) {}
                            } message: {
                                Text("请在安静环境下使用，以获得最佳体验～")
                            }
                        }
                        .font(.system(size: 14)) // Smaller icons
                    }
                }
                .navigationDestination(isPresented: $showAdoptionView) {
                    PetAdoptionView(viewModel: viewModel)
                }
                .navigationDestination(isPresented: $showChatView) {
                    if let service = viewModel.aiService {
                        ChatView(service: service)
                    } else {
                        ProgressView("初始化\(viewModel.status.displayName)大脑...")
                            .onAppear {
                                viewModel.updateWardrobeContext(clothings: clothings)
                            }
                    }
                }
            }
        }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                viewModel.onAppDidEnterBackground()
            } else if newPhase == .active {
                viewModel.onAppDidBecomeActive()
            }
        }
        .onChange(of: clothings) { _, newClothings in
            viewModel.updateWardrobeContext(clothings: newClothings)
        }
        .onAppear {
            viewModel.onViewAppear()
            viewModel.updateWardrobeContext(clothings: clothings)
        }
        .onDisappear {
            viewModel.onViewDisappear()
        }
    }
}

#Preview {
    PetHomeView()
}
