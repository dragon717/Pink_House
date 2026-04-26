//
//  SharedTypes.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import Foundation

enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"
    
    var id: String { self.rawValue }
}

enum HomeTab {
    case wardrobe
    case depositPlan
}

enum LegalLinks {
    static let privacyURL = URL(string: "https://sangsang.online/privacy/")!
    static let userAgreementURL = URL(string: "https://sangsang.online/user-agreement/")!
    static let vipAgreementURL = URL(string: "https://sangsang.online/vip-agreement/")!
    static let contactURL = URL(string: "https://sangsang.online/contact/")!
    static let supportEmailAddress = "huangsangmuniao@126.com"
    static let supportEmailURL = URL(string: "mailto:\(supportEmailAddress)")!

    static let xiaohongshuHandle = "@少女心愿（衣橱管家）"
    static let xiaohongshuID = "3621744284"

    static let icpText = "沪ICP备2026008696号-1A"
    static let copyrightText = "© 2026 桑桑桑 Inc."
}
