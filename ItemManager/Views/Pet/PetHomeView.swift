import SwiftUI
import SwiftData
import Combine
import UIKit

struct PetHomeView: View {
    @StateObject private var viewModel = PetViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var clothings: [Clothing]
    
    @StateObject private var audioManager = AudioManager.shared
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
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
    @State private var showVIPView = false // VIP View State
    
    // 用于监听媒体状态通知
    @State private var cancellables = Set<AnyCancellable>()

    @ViewBuilder
    private func petShortcutIcon(for pet: PetCharacter, size: CGFloat) -> some View {
        if UIImage(named: pet.quickOptionIconName) != nil {
            Image(pet.quickOptionIconName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: pet == .maomao ? "dog.fill" : "cat.fill")
                .font(.system(size: size))
                .foregroundStyle(.orange)
        }
    }
    
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
                                            .foregroundColor(themeManager.primaryTextColor)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(themeManager.accentTextColor.opacity(0.3))
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
                                            .foregroundColor(themeManager.primaryTextColor)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(themeManager.secondaryTextColor.opacity(0.3))
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
                .sheet(item: $viewModel.presentedFundingSheet) { destination in
                    switch destination {
                    case .meowCoinStore:
                        MeowCoinStoreView()
                    case .currencyExchange(let preferredDirection):
                        PetCurrencyExchangeSheet(preferredDirection: preferredDirection)
                            .presentationDetents([.medium, .large])
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
                                                    petShortcutIcon(for: pet, size: 14)
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
                                petShortcutIcon(for: viewModel.currentPet, size: 16)
                                
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
            
            // 通知媒体状态管理器切换到萌宠页面
                print("🐱 PetHomeView.onAppear: 准备切换到萌宠页面")
                mediaStateManager.switchToPage(.pet)
                print("🐱 PetHomeView.onAppear: 已切换到萌宠页面")
            
            // 监听媒体停止通知（当切换到其他页面时）
            // 注意：背景音乐的状态保存和停止已经在 MediaStateManager.stopAllMedia() 中处理
            // 这里使用不保存的方法停止，避免覆盖用户的持久化设置
            NotificationCenter.default.publisher(for: .petMediaShouldStop)
                .sink { [weak audioManager, weak hapticManager] _ in
                    audioManager?.stopBackgroundMusicWithoutSaving()
                    if audioManager?.isInteractionEnabled == true {
                        audioManager?.isInteractionEnabled = false
                    }
                    hapticManager?.stopHaptics()
                }
                .store(in: &cancellables)
            
            // 监听媒体启动通知（当切换回萌宠页面时）
            // 注意：背景音乐的状态恢复已经在 MediaStateManager.startPetMedia() 中处理
            // 这里不需要再设置，避免覆盖用户的持久化设置
            NotificationCenter.default.publisher(for: .petMediaShouldStart)
                .sink { _ in
                    // 背景音乐状态已由 MediaStateManager 恢复，这里仅处理其他媒体启动逻辑
                    // 注意：萌宠页面的震动由具体交互触发，这里不需要自动启动
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            viewModel.onViewDisappear()
            
            // 清理通知监听
            cancellables.removeAll()
            
            // 如果当前页面是萌宠页面，切换到其他页面
                print("🐱 PetHomeView.onDisappear: 准备切换到其他页面")
                if mediaStateManager.currentPage == .pet {
                    mediaStateManager.switchToPage(.other)
                }
                print("🐱 PetHomeView.onDisappear: 已切换到其他页面")
        }
        .overlay {
            if let prompt = viewModel.presentedFundingPrompt {
                PetFundingPromptOverlay(
                    prompt: prompt,
                    onDismiss: { viewModel.dismissFundingPrompt() },
                    onPrimaryAction: { viewModel.continueFundingPromptFlow() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.presentedFundingPrompt?.id)
    }
}

private struct PetFundingPromptOverlay: View {
    let prompt: PetFundingPrompt
    let onDismiss: () -> Void
    let onPrimaryAction: () -> Void

    private var accentGradient: LinearGradient {
        switch prompt.currency {
        case .meowCoin:
            return LinearGradient(
                colors: [Color(hex: "FFD76A"), Color(hex: "FF9F43")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .fishCoin:
            return LinearGradient(
                colors: [Color(hex: "7DD3FC"), Color(hex: "38BDF8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .boneCoin:
            return LinearGradient(
                colors: [Color(hex: "E7C9A9"), Color(hex: "C08A5B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var accentTint: Color {
        switch prompt.currency {
        case .meowCoin:
            return Color(hex: "FFB020")
        case .fishCoin:
            return Color(hex: "0EA5E9")
        case .boneCoin:
            return Color(hex: "A16207")
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accentGradient)
                            .frame(width: 58, height: 58)
                            .shadow(color: accentTint.opacity(0.28), radius: 14, x: 0, y: 8)
                        promptIcon
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("余额不足")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accentTint.opacity(0.12))
                            .clipShape(Capsule())

                        Text(prompt.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(prompt.message)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("稍后再说")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Capsule())
                    }

                    Button(action: onPrimaryAction) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text(prompt.actionTitle)
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentGradient)
                        .clipShape(Capsule())
                        .shadow(color: accentTint.opacity(0.24), radius: 12, x: 0, y: 8)
                    }
                }
            }
            .padding(22)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: 460)
        }
    }

    @ViewBuilder
    private var promptIcon: some View {
        switch prompt.currency {
        case .meowCoin:
            Image(systemName: "pawprint.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
        case .fishCoin:
            Image(systemName: "fish.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        case .boneCoin:
            Text("🦴")
                .font(.system(size: 26))
        }
    }
}

#Preview {
    PetHomeView()
}
