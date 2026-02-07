import SwiftUI

struct PetHomeView: View {
    @StateObject private var viewModel = PetViewModel()
    @StateObject private var audioManager = AudioManager.shared
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @Environment(\.scenePhase) var scenePhase
    @State private var isExpanded = false
    @State private var showRenameAlert = false
    @State private var showNoCardAlert = false
    @State private var showJobSelection = false
    @State private var newName = ""
    
    var body: some View {
        NavigationStack {
            if viewModel.status.petName == nil {
                PetNamingView(petName: Binding(
                    get: { viewModel.status.petName },
                    set: { viewModel.setPetName($0 ?? "") }
                )) { }
            } else {
                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height
                    let videoHeight = isLandscape ? min(geo.size.width, geo.size.height) * 0.8 : 400
                    
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
                        .offset(y: -40) // 整体向上偏移，避免视觉重心过低或被底部遮挡
                        
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
                        PetBottomPanel(viewModel: viewModel, isExpanded: $isExpanded, isLandscape: isLandscape)
                    }
                }
                .alert("修改萌宠名字", isPresented: $showRenameAlert) {
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
                .sheet(isPresented: $showJobSelection) {
                    PetJobSelectionView(viewModel: viewModel, isPresented: $showJobSelection)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
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
                            
                            Button {
                                showJobSelection = true
                            } label: {
                                Label("送去打工", systemImage: "briefcase")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "cat.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.orange)
                                
                                let petName = viewModel.status.petName
                                let rawName = petName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? petName! : "萌宠"
                                // 移除所有可能的引号
                                let cleanName = rawName.replacingOccurrences(of: "\"", with: "")
                                    .replacingOccurrences(of: "“", with: "")
                                    .replacingOccurrences(of: "”", with: "")
                                let displayName = cleanName.isEmpty ? "萌宠" : cleanName
                                
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
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                viewModel.saveStatus()
            } else if newPhase == .active {
                viewModel.onAppDidBecomeActive()
            }
        }
    }
}

#Preview {
    PetHomeView()
}
