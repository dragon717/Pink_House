//
//  TabNavigationManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/24/26.
//

import SwiftUI
import Combine

// MARK: - 导航目标
enum TabNavigationDestination {
    case smallWorld(SmallWorldDestination)
    case wardrobe(HomeTab)
}

// MARK: - Tab 导航管理器
class TabNavigationManager: ObservableObject {
    static let shared = TabNavigationManager()
    
    @Published var navigateToTab: Int?
    @Published var navigateToHomeTab: HomeTab?
    @Published var navigateToSmallWorld: SmallWorldDestination?
    
    private init() {}
    
    // 导航到指定 Tab
    func navigate(to destination: TabNavigationDestination) {
        switch destination {
        case .smallWorld(let smallWorldDestination):
            navigateToTab = 1
            navigateToSmallWorld = smallWorldDestination
        case .wardrobe(let homeTab):
            navigateToTab = 0
            navigateToHomeTab = homeTab
        }
    }
    
    // 重置导航状态
    func reset() {
        navigateToTab = nil
        navigateToHomeTab = nil
        navigateToSmallWorld = nil
    }
}
