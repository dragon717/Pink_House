//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI

enum SmallWorldDestination {
    case menu
    case ootd
    case pet
    case wealth
    case calendar
}

struct SmallWorldView: View {
    @Binding var selectedTab: Int // MainTabView selection
    @Binding var homeTab: HomeTab // HomeView selection
    @Binding var destination: SmallWorldDestination
    
    // 图片原始尺寸 1919x1079
    private let imageSize = CGSize(width: 1919, height: 1079)
    
    // 调试模式：开启后显示热区范围 (仅在 Debug 模式下生效)
    private var showDebugHotspots: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Image("small_world_bg") // 确保图片已添加至 Assets
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.height * (imageSize.width / imageSize.height), height: geometry.size.height)
                            .overlay(
                                ZStack(alignment: .topLeading) {
                                    // 1. OOTD (今日穿搭) - 最左侧
                                    InteractionHotspot(rect: CGRect(x: 0.1, y: 0.5, width: 0.15, height: 0.2), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .orange) {
                                        destination = .ootd
                                    }
                                    
                                    // 2. 衣橱 (少女衣橱)
                                    InteractionHotspot(rect: CGRect(x: 0.3, y: 0.2, width: 0.25, height: 0.6), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                        homeTab = .wardrobe
                                        selectedTab = 0
                                    }
                                    
                                    // 3. 猪 (来财)
                                    InteractionHotspot(rect: CGRect(x: 0.75, y: 0.55, width: 0.12, height: 0.2), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                        destination = .wealth
                                    }
                                    
                                    // 4. 墙上的日历 (梦裙日历)
                                    CalendarHotspot(rect: CGRect(x: 0.6, y: 0.15, width: 0.1, height: 0.2), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                        destination = .calendar
                                    }
                                    
                                    // 中心锚点，用于初始定位
                                    Color.clear
                                        .frame(width: 1, height: 1)
                                        .position(x: (geometry.size.height * (imageSize.width / imageSize.height)) / 2,
                                                  y: geometry.size.height / 2)
                                        .id("centerAnchor")
                                }
                            )
                    }
                }
                .ignoresSafeArea()
                .disableScrollBounce() // 禁用边缘回弹
                .onAppear {
                    // 延迟滚动以确保视图加载完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            scrollProxy.scrollTo("centerAnchor", anchor: .center)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea() // 确保 GeometryReader 获取全屏尺寸
        // .background(Color.black) // z-index 问题，确保在 ScrollView 之上
        .toolbarBackground(.hidden, for: .tabBar) // 尝试 SwiftUI 原生隐藏
        .onAppear {
            // 强制设置 UITabBar 为完全透明
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowImage = UIImage()
            appearance.backgroundImage = UIImage()
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
        .onDisappear {
            // 恢复默认的半透明背景
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
}

/// 交互热区组件
struct InteractionHotspot: View {
    let rect: CGRect // 归一化坐标 (0.0 - 1.0)
    let geometry: GeometryProxy
    let imageSize: CGSize
    var showDebug: Bool = false
    var debugColor: Color = .red
    let action: () -> Void
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        Button(action: action) {
            if showDebug {
                Rectangle()
                    .fill(debugColor.opacity(0.3))
                    .border(debugColor)
            } else {
                Color.clear
                    .contentShape(Rectangle())
            }
        }
        .frame(width: rect.width * width, height: rect.height * height)
        .offset(x: rect.minX * width, y: rect.minY * height)
    }
}

/// 日历专属热区，带容器跟随效果
struct CalendarHotspot: View {
    let rect: CGRect
    let geometry: GeometryProxy
    let imageSize: CGSize
    var showDebug: Bool = false
    let action: () -> Void
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        ZStack(alignment: .topLeading) {
            // 点击跳转
            Button(action: action) {
                if showDebug {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .border(Color.blue)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
            
            // 随动内容：当月界面预览
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.month, from: Date()))月")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.pink)
                
                // 简单的网格模拟
                let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(0..<28) { _ in
                        Circle()
                            .fill(Color.pink.opacity(0.3))
                            .frame(width: 2, height: 2)
                    }
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.8))
            .cornerRadius(4)
            .frame(width: rect.width * width * 0.8, height: rect.height * height * 0.6)
            .position(x: rect.midX * width, y: rect.midY * height)
            .allowsHitTesting(false) // 让点击穿透到下层 Button
        }
        .frame(width: rect.width * width, height: rect.height * height)
        .offset(x: rect.minX * width, y: rect.minY * height)
    }
}

