//
//  MainTabView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI

private struct IsSimulationActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isSimulationActive: Bool {
        get { self[IsSimulationActiveKey.self] }
        set { self[IsSimulationActiveKey.self] = newValue }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @State private var homeTabSelection: HomeTab = .wardrobe
    @State private var smallWorldDestination: SmallWorldDestination = .menu
    @State private var isPlayingOpeningAnimation = false
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    
    var body: some View {
        ZStack {
            TabView(selection: tabSelectionBinding) {
                // Tab 0: 衣橱 (Wardrobe)
                HomeView(selectedTab: $homeTabSelection)
                    .tabItem {
                        Image(systemName: selectedTab == 0 ? "cabinet" : "cabinet.fill")
                            .renderingMode(.original)
                        Text("衣橱")
                    }
                    .tag(0)
                
                // Tab 1: 小世界 (Small World) / 功能页
                Group {
                    switch smallWorldDestination {
                    case .menu:
                        SmallWorldView(
                            selectedTab: $selectedTab,
                            homeTab: $homeTabSelection,
                            destination: $smallWorldDestination,
                            isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                        )
                    case .ootd:
                        OOTDView()
                    case .pet:
                        PetHomeView()
                    case .wealth:
                        WealthView()
                    case .calendar:
                        DreamDressCalendarView()
                    }
                }
                .tabItem {
                    switch smallWorldDestination {
                    case .menu:
                        Label("小世界", systemImage: "map")
                    case .ootd:
                        Label("穿搭手帐", systemImage: "tshirt")
                    case .pet:
                        Label(petDataManager.status.displayName, systemImage: "pawprint")
                    case .wealth:
                        Label("马上来财", systemImage: "yensign.circle")
                    case .calendar:
                        Label("梦裙日历", systemImage: "calendar")
                    }
                }
                .tag(1)

                // Tab 2: 我的 (Me)
                MeView()
                    .tabItem {
                        Label("我的", systemImage: "face.smiling")
                    }
                    .tag(2)
            }
            .environment(\.isSimulationActive, isSimulationActive)
            
            // Existing Overlay
            RewardBubbleView()
            
            // New Pet Overlay (ZStack 顶层)
            PetOverlayView(action: {
                selectedTab = 1
                smallWorldDestination = .pet
            }, petName: petDataManager.status.displayName)
            
            // Small World Long Press Menu Overlay
            SmallWorldMenuOverlay(selectedTab: $selectedTab, smallWorldDestination: $smallWorldDestination)
            
            // Video Player Overlay
            if isPlayingOpeningAnimation {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    
                    PetVideoPlayer(videoName: "open_dress", isLooping: false, onFinished: {
                        // 1. Switch Tab behind the scene
                        homeTabSelection = .wardrobe
                        selectedTab = 0
                        
                        // 2. Fade out video
                        // 延迟一点点执行，确保 Tab 切换已生效
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                isPlayingOpeningAnimation = false
                            }
                        }
                    })
                    .ignoresSafeArea()
                    
                    // Skip Button
                    Button {
                        homeTabSelection = .wardrobe
                        selectedTab = 0
                        withAnimation(.easeOut(duration: 0.5)) {
                            isPlayingOpeningAnimation = false
                        }
                    } label: {
                        Text("跳过")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.4))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                }
                .transition(.opacity)
                .zIndex(200) // Ensure it's on top of everything
                .id("OpeningVideoOverlay") // 强制刷新
            }
        }
        .onChange(of: smallWorldDestination) { oldValue, newValue in
            // 当小世界内部页面切换时，更新媒体状态
            print("🔄 MainTabView: 小世界内部切换从 \(oldValue) 到 \(newValue), selectedTab: \(selectedTab)")
            if selectedTab == 1 {
                handleSmallWorldDestinationChange()
            }
        }
    }
    
    // 自定义 Binding 处理 Tab 点击逻辑
    private var tabSelectionBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                // 如果用户再次点击当前的 Tab 1 (且不在菜单页)，则返回菜单
                // 注意：由于我们在 SmallWorldMenuOverlay 中已经处理了 Tab 1 的点击逻辑，
                // 这里的逻辑主要用于原生 TabBarItem 的点击。
                // 如果 Overlay 拦截了点击，这里可能不会触发。
                if newValue == selectedTab && newValue == 1 {
                    if smallWorldDestination != .menu {
                        smallWorldDestination = .menu
                    }
                }
                selectedTab = newValue
                
                // 处理媒体状态切换
                handleTabChange(newTab: newValue)
            }
        )
    }
    
    /// 处理 Tab 切换时的媒体状态
    private func handleTabChange(newTab: Int) {
        print("🔄 MainTabView: Tab 切换到 \(newTab), 小世界目标: \(smallWorldDestination)")
        switch newTab {
        case 0:
            // 切换到衣橱页面
            print("🏠 切换到衣橱页面")
            mediaStateManager.switchToPage(.wardrobe)
        case 1:
            // 小世界页面，根据具体子页面决定
            switch smallWorldDestination {
            case .pet:
                print("🐱 切换到萌宠页面")
                mediaStateManager.switchToPage(.pet)
            case .wealth:
                print("💰 切换到财富页面")
                mediaStateManager.switchToPage(.wealth)
            default:
                print("🌍 切换到小世界其他页面")
                mediaStateManager.switchToPage(.other)
            }
        case 2:
            // 我的页面
            print("👤 切换到我的页面")
            mediaStateManager.switchToPage(.other)
        default:
            print("❓ 切换到未知页面")
            mediaStateManager.switchToPage(.other)
        }
    }
    
    /// 处理小世界内部页面切换
    private func handleSmallWorldDestinationChange() {
        print("🔄 MainTabView: 处理小世界内部切换, 目标: \(smallWorldDestination)")
        switch smallWorldDestination {
        case .pet:
            print("🐱 小世界切换到萌宠")
            mediaStateManager.switchToPage(.pet)
        case .wealth:
            print("💰 小世界切换到财富")
            mediaStateManager.switchToPage(.wealth)
        default:
            print("🌍 小世界切换到其他")
            mediaStateManager.switchToPage(.other)
        }
    }
    
    // 计算属性判断是否激活模拟 (针对 WealthView)
    private var isSimulationActive: Bool {
        return selectedTab == 1 && smallWorldDestination == .wealth
    }
}

#Preview {
    MainTabView()
}
