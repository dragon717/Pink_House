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

// MARK: - House页面来源
enum SmallWorldSource {
    case wardrobe      // 来自衣橱
    case depositPlan   // 来自心愿尾款
    case smallWorld    // 来自House菜单
}

// MARK: - Tab 导航管理器
class TabNavigationManager: ObservableObject {
    static let shared = TabNavigationManager()
    
    @Published var navigateToTab: Int?
    @Published var navigateToHomeTab: HomeTab?
    @Published var navigateToSmallWorld: SmallWorldDestination?
    @Published var navigateToClothingID: UUID?
    @Published var pendingWardrobeCreationDraft: ClothingEditDraft?
    /// 开售提醒深链：待打开的店家上新商品 ID（时光馆 Tab 4 栈内压入商品详情）
    @Published var pendingShopCatalogProductID: String?
    
    // 记录进入House前的来源，用于智能返回
    // 当用户从Tab 0（衣橱/心愿尾款）跳转到House时，记录当时的HomeTab
    // 当用户在House内部切换时，保持这个值不变
    @Published var lastHomeTabBeforeSmallWorld: HomeTab = .wardrobe
    
    // 标记是否是在House内部导航（而非从Tab 0进入）
    @Published var isNavigatingInsideSmallWorld: Bool = false
    
    private init() {}
    
    // 导航到指定 Tab
    func navigate(to destination: TabNavigationDestination) {
        switch destination {
        case .smallWorld(let smallWorldDestination):
            // 重置内部导航标记，因为这是从外部进入House
            isNavigatingInsideSmallWorld = false
            navigateToSmallWorld = smallWorldDestination
            navigateToTab = 1
        case .wardrobe(let homeTab):
            navigateToHomeTab = homeTab
            navigateToTab = 0
        }
    }

    func navigate(to featureID: AppFeatureID) {
        let feature = AppFeatureRegistry.descriptor(for: featureID)
        guard feature.isUnlocked else { return }

        switch feature.route {
        case .tab(let tabIndex):
            navigateToTab = tabIndex
        case .wardrobe(let homeTab):
            navigate(to: .wardrobe(homeTab))
        case .smallWorld(let destination):
            navigate(to: .smallWorld(destination))
        }
    }

    func navigateToDepositNotificationClothing(_ clothingID: UUID) {
        navigateToHomeTab = .depositPlan
        navigateToClothingID = clothingID
        navigateToTab = 0
    }

    /// 开售提醒深链：切到时光馆（Tab 4），店家上新栈随后把目标商品详情压入
    func navigateToShopCatalogProduct(_ productID: String) {
        pendingShopCatalogProductID = productID
        navigateToTab = 4
    }

    /// 切回衣橱并用外部资料打开现有的手动创建页。
    func presentWardrobeCreation(with draft: ClothingEditDraft) {
        navigate(to: .wardrobe(.wardrobe))
        pendingWardrobeCreationDraft = draft
    }
    
    // 记录从Tab 0进入House时的HomeTab状态
    func recordEnteringSmallWorldFromHomeTab(_ homeTab: HomeTab) {
        lastHomeTabBeforeSmallWorld = homeTab
        isNavigatingInsideSmallWorld = false
    }
    
    // 标记在House内部导航
    func markNavigatingInsideSmallWorld() {
        isNavigatingInsideSmallWorld = true
    }
    
    // 获取当前House页面的返回来源
    var currentSmallWorldSource: SmallWorldSource {
        // 如果是在House内部导航，返回House菜单
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
        navigateToClothingID = nil
        pendingWardrobeCreationDraft = nil
        pendingShopCatalogProductID = nil
    }
}
