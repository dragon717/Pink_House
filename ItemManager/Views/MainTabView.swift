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
                        SmallWorldView(selectedTab: $selectedTab, homeTab: $homeTabSelection, destination: $smallWorldDestination)
                    case .ootd:
                        OOTDView()
                    case .pet:
                        PetHomeView()
                    case .wealth:
                        WealthView()
                    }
                }
                .tabItem {
                    switch smallWorldDestination {
                    case .menu:
                        Label("小世界", systemImage: "map")
                    case .ootd:
                        Label("OOTD", systemImage: "tshirt.fill")
                    case .pet:
                        Label("萌宠", systemImage: "pawprint.fill")
                    case .wealth:
                        Label("来财", systemImage: "yensign.circle.fill")
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
            })
        }
    }
    
    // 自定义 Binding 处理 Tab 点击逻辑
    private var tabSelectionBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                // 如果用户再次点击当前的 Tab 1 (且不在菜单页)，则返回菜单
                if newValue == selectedTab && newValue == 1 {
                    if smallWorldDestination != .menu {
                        smallWorldDestination = .menu
                    }
                }
                selectedTab = newValue
            }
        )
    }
    
    // 计算属性判断是否激活模拟 (针对 WealthView)
    private var isSimulationActive: Bool {
        return selectedTab == 1 && smallWorldDestination == .wealth
    }
}

#Preview {
    MainTabView()
}
