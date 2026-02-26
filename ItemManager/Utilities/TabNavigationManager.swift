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

// MARK: - 小世界页面来源
enum SmallWorldSource {
    case wardrobe      // 来自衣橱
    case depositPlan   // 来自尾款天使
    case smallWorld    // 来自小世界菜单
}

// MARK: - Tab 导航管理器
class TabNavigationManager: ObservableObject {
    static let shared = TabNavigationManager()
    
    @Published var navigateToTab: Int?
    @Published var navigateToHomeTab: HomeTab?
    @Published var navigateToSmallWorld: SmallWorldDestination?
    
    // 记录进入小世界前的来源，用于智能返回
    // 当用户从Tab 0（衣橱/尾款天使）跳转到小世界时，记录当时的HomeTab
    // 当用户在小世界内部切换时，保持这个值不变
    @Published var lastHomeTabBeforeSmallWorld: HomeTab = .wardrobe
    
    // 标记是否是在小世界内部导航（而非从Tab 0进入）
    @Published var isNavigatingInsideSmallWorld: Bool = false
    
    private init() {}
    
    // 导航到指定 Tab
    func navigate(to destination: TabNavigationDestination) {
        switch destination {
        case .smallWorld(let smallWorldDestination):
            // 重置内部导航标记，因为这是从外部进入小世界
            isNavigatingInsideSmallWorld = false
            navigateToTab = 1
            navigateToSmallWorld = smallWorldDestination
        case .wardrobe(let homeTab):
            navigateToTab = 0
            navigateToHomeTab = homeTab
        }
    }
    
    // 记录从Tab 0进入小世界时的HomeTab状态
    func recordEnteringSmallWorldFromHomeTab(_ homeTab: HomeTab) {
        lastHomeTabBeforeSmallWorld = homeTab
        isNavigatingInsideSmallWorld = false
    }
    
    // 标记在小世界内部导航
    func markNavigatingInsideSmallWorld() {
        isNavigatingInsideSmallWorld = true
    }
    
    // 获取当前小世界页面的返回来源
    var currentSmallWorldSource: SmallWorldSource {
        // 如果是在小世界内部导航，返回小世界菜单
        if isNavigatingInsideSmallWorld {
            return .smallWorld
        }
        // 否则是从Tab 0进入的，根据记录的 HomeTab 判断
        return lastHomeTabBeforeSmallWorld == .depositPlan ? .depositPlan : .wardrobe
    }
    
    // 重置导航状态
    func reset() {
        navigateToTab = nil
        navigateToHomeTab = nil
        navigateToSmallWorld = nil
    }
}
