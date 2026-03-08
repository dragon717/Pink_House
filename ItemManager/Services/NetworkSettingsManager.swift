//
//  NetworkSettingsManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2026/3/9.
//

import Foundation
import SwiftUI
import Combine

// MARK: - 联网设置管理器
final class NetworkSettingsManager: ObservableObject {
    static let shared = NetworkSettingsManager()
    
    // 发布状态供UI绑定
    @Published var isNetworkEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isNetworkEnabled, forKey: networkEnabledKey)
        }
    }
    
    // 是否已经通过答题解锁
    @Published var isQuizUnlocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isQuizUnlocked, forKey: quizUnlockedKey)
        }
    }
    
    // UserDefaults Keys
    private let networkEnabledKey = "networkSettings.enabled"
    private let quizUnlockedKey = "networkSettings.quizUnlocked"
    
    // 通知名称
    static let networkSettingsChangedNotification = Notification.Name("NetworkSettingsChanged")
    
    private init() {
        loadSettings()
        // 监听功能解锁状态变化
        setupFeatureUnlockObserver()
    }
    
    private func loadSettings() {
        isNetworkEnabled = UserDefaults.standard.bool(forKey: networkEnabledKey)
        isQuizUnlocked = UserDefaults.standard.bool(forKey: quizUnlockedKey)
    }
    
    private func setupFeatureUnlockObserver() {
        // 监听功能解锁通知
        NotificationCenter.default.addObserver(
            forName: FeatureUnlockManager.featureUnlockedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let featureRawValue = notification.userInfo?["feature"] as? String,
               featureRawValue == FeatureItem.networkCommunity.rawValue {
                // 联网功能已解锁，自动开启联网开关
                self?.isQuizUnlocked = true
                self?.isNetworkEnabled = true
                self?.sendSettingsChangedNotification()
            }
        }
    }
    
    /// 设置联网开关状态
    func setNetworkEnabled(_ enabled: Bool) {
        // 只有解锁后才能开启
        guard isQuizUnlocked || !enabled else {
            return
        }
        isNetworkEnabled = enabled
        sendSettingsChangedNotification()
    }
    
    /// 标记答题已解锁
    func markQuizAsUnlocked() {
        isQuizUnlocked = true
        isNetworkEnabled = true
        // 同时解锁功能
        FeatureUnlockManager.shared.unlock(.networkCommunity, force: true)
        sendSettingsChangedNotification()
    }
    
    /// 检查联网功能是否可用（已解锁且已开启）
    func isNetworkAvailable() -> Bool {
        return isQuizUnlocked && isNetworkEnabled
    }
    
    /// 检查是否可以显示联网相关UI
    func canShowNetworkUI() -> Bool {
        return FeatureUnlockManager.shared.isUnlocked(.networkCommunity) && isNetworkEnabled
    }
    
    private func sendSettingsChangedNotification() {
        NotificationCenter.default.post(
            name: Self.networkSettingsChangedNotification,
            object: nil,
            userInfo: ["enabled": isNetworkEnabled]
        )
    }
}

// MARK: - 答题数据模型
struct QuizQuestion: Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
    let correctAnswer: Int // 正确答案的索引
    let explanation: String // 答案解析
}

// MARK: - 答题管理器
final class QuizManager: ObservableObject {
    static let shared = QuizManager()
    
    // 预设的题库
    let questions: [QuizQuestion] = [
        QuizQuestion(
            question: "少女衣橱是一款什么类型的应用？",
            options: ["游戏", "Lolita裙子管理工具", "社交软件", "购物平台"],
            correctAnswer: 1,
            explanation: "少女衣橱是一款专为Lolita爱好者设计的裙子管理工具。"
        ),
        QuizQuestion(
            question: "在少女衣橱中，'尾款天使'功能是用来做什么的？",
            options: ["记录已付尾款", "提醒尾款支付时间", "计算尾款金额", "预约裙子"],
            correctAnswer: 1,
            explanation: "尾款天使功能用于提醒用户尾款支付时间，避免错过付款期限。"
        ),
        QuizQuestion(
            question: "以下哪个不是少女衣橱的功能模块？",
            options: ["梦幻衣橱", "穿搭手帐", "股票交易", "萌宠"],
            correctAnswer: 2,
            explanation: "股票交易不是少女衣橱的功能，其他都是应用内的功能模块。"
        ),
        QuizQuestion(
            question: "在少女衣橱社区分享裙子时，应该注意什么？",
            options: ["随意分享他人图片", "尊重版权，分享原创内容", "不需要标注品牌", "可以分享盗版信息"],
            correctAnswer: 1,
            explanation: "在社区分享时应尊重版权，分享原创内容，这是社区的基本准则。"
        ),
        QuizQuestion(
            question: "'追根溯源'功能可以帮助你做什么？",
            options: ["找到裙子的购买链接", "了解裙子的品牌历史", "查看裙子的原价信息", "联系卖家"],
            correctAnswer: 1,
            explanation: "追根溯源功能帮助用户了解裙子的品牌历史和相关信息。"
        )
    ]
    
    // 需要答对的题目数量
    let requiredCorrectAnswers = 3
    
    private init() {}
    
    /// 获取随机题目
    func getRandomQuestions(count: Int = 3) -> [QuizQuestion] {
        let shuffled = questions.shuffled()
        return Array(shuffled.prefix(min(count, shuffled.count)))
    }
    
    /// 检查是否通过答题
    func checkPass(correctCount: Int) -> Bool {
        return correctCount >= requiredCorrectAnswers
    }
}
