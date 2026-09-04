//
//  DepositPlanComponents.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI

enum DepositPlanFormatters {
    static func yearText(_ year: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("y")
        return formatter.string(from: date(year: year, month: 1))
    }

    static func monthText(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date(year: 2024, month: month))
    }

    static func currencyText(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? "¥\(NSDecimalNumber(decimal: amount).stringValue)"
    }

    private static func date(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = 1
        return components.date ?? Date()
    }
}

// MARK: - 总待付尾款卡片
struct TotalBalanceCard: View {
    let totalBalance: Decimal
    let isVisible: Bool
    let onToggleVisibility: () -> Void
    let onCountMoney: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared
    
    // 未解锁功能提示弹窗
    @State private var showUnlockAlert = false
    @State private var lockedFeature: FeatureItem? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // 功能入口（放在最上方）
            HStack(spacing: 0) {
                // 梦裙日历
                Button {
                    handleQuickAccess(.calendar)
                } label: {
                    VStack(spacing: 4) {
                        ThemeSkinIconBadge(systemName: "calendar", fallbackColor: .pink, size: 30, symbolSize: 14)
                        Text("梦裙日历".appLocalized)
                            .font(.caption)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 30)

                // 萌宠管家
                Button {
                    tabNavigationManager.navigate(to: .petChat)
                } label: {
                    VStack(spacing: 4) {
                        ThemeSkinIconBadge(systemName: "pawprint.fill", fallbackColor: Color(hex: "FF7F50"), size: 30, symbolSize: 14)
                        Text("萌宠管家".appLocalized)
                            .font(.caption)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    .foregroundStyle(Color(hex: "FF7F50"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 30)
                
                // 马上来财
                Button {
                    handleQuickAccess(.wealth(nil))
                } label: {
                    VStack(spacing: 4) {
                        ThemeSkinIconBadge(systemName: "dollarsign.circle", fallbackColor: .orange, size: 30, symbolSize: 14)
                        Text("马上来财".appLocalized)
                            .font(.caption)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .alert("功能未解锁".appLocalized, isPresented: $showUnlockAlert) {
                if let feature = lockedFeature {
                    if feature.isComingSoonFeature {
                        Button("我知道啦～".appLocalized, role: .cancel) { }
                    } else {
                        Button("取消".appLocalized, role: .cancel) { }
                        Button("去解锁".appLocalized) {
                            NotificationCenter.default.post(
                                name: .navigateToMagicTasks,
                                object: nil
                            )
                        }
                    }
                } else {
                    Button("取消".appLocalized, role: .cancel) { }
                }
            } message: {
                if let feature = lockedFeature {
                    let condition = featureManager.getCondition(for: feature)
                    Text("%@ 尚未解锁\n%@".appLocalized(feature.displayName, condition.localizedDescription))
                } else {
                    Text("该功能尚未解锁，请先完成对应任务".appLocalized)
                }
            }
            
            // 分割线
            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            // 标题和按钮（始终显示）
            HStack {
                Text("总待付尾款".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                
                Spacer()
                
                // 小眼睛按钮 - 闭眼 (eye.slash) 表示当前隐藏，点击显示；睁眼 (eye) 表示当前显示，点击隐藏
                Button(action: onToggleVisibility) {
                    ThemeSkinIconBadge(
                        systemName: isVisible ? "eye" : "eye.slash",
                        fallbackColor: .pink,
                        size: 32,
                        symbolSize: 15
                    )
                }
                .buttonStyle(.plain)
                
                // 数钱按钮（仅显示时）
                if isVisible {
                    Button(action: onCountMoney) {
                        ThemeSkinIconBadge(systemName: "banknote", fallbackColor: .green, size: 32, symbolSize: 15)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            
            // 金额显示（仅显示时）
            if isVisible {
                Button(action: onCountMoney) {
                    Text(DepositPlanFormatters.currencyText(totalBalance))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color(hex: "C94C72"))
                        .themeSkinLegibleText(level: .hero, slot: .sectionCard)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 12)
            } else {
                // 隐藏状态只保留底部间距
                Spacer()
                    .frame(height: 8)
            }

        }
        .themeSkinSectionCard(cornerRadius: 20)
    }
    
    // MARK: - 处理快捷入口点击
    private func handleQuickAccess(_ destination: SmallWorldDestination) {
        // 检查功能是否已解锁
        if let feature = destination.featureItem {
            if featureManager.canAccess(feature) {
                // 已解锁，正常跳转
                tabNavigationManager.navigate(to: .smallWorld(destination))
            } else {
                // 未解锁，显示提示
                lockedFeature = feature
                showUnlockAlert = true
            }
        } else {
            // 没有对应功能项，直接跳转
            tabNavigationManager.navigate(to: .smallWorld(destination))
        }
    }
}

// MARK: - 统计视图
struct DepositStatsView: View {
    let clothings: [Clothing]
    var onCountMoney: ((Decimal) -> Void)? = nil
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    
    // Deduplicated clothings based on name, deposit, balance for Style Count
    // We ignore stock for style counting
    private var uniqueStyles: [Clothing] {
        var seenKeys: Set<String> = []
        var result: [Clothing] = []
        
        for clothing in clothings {
            // Style defined by Name + Price info
            let key = "\(clothing.name)|\(clothing.deposit)|\(clothing.balance)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                result.append(clothing)
            }
        }
        return result
    }
    
    var styleCount: Int {
        uniqueStyles.count
    }
    
    var totalCount: Int {
        // Sum of stock of ALL clothings (Inventory Count)
        clothings.reduce(0) { $0 + $1.stock }
    }
    
    var paidDeposit: Decimal {
        clothings.reduce(0) { $0 + $1.reservationPaidAmount }
    }

    var pendingBalance: Decimal {
        clothings.reduce(0) { $0 + $1.reservationListAmount }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statItem(title: "总件数/款", value: "\(totalCount)/\(styleCount)")
                
                Divider()
                    .frame(height: 30)
                
                statItem(title: "已付定金", value: DepositPlanFormatters.currencyText(paidDeposit), valueColor: Color(hex: "FF9800"))
                
                Divider()
                    .frame(height: 30)
                
                Button {
                    onCountMoney?(pendingBalance)
                } label: {
                    statItem(title: "预约金额", value: DepositPlanFormatters.currencyText(pendingBalance), showIcon: true)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 24)
    }
    
    private func statItem(title: String, value: String, valueColor: Color = .primary, showIcon: Bool = false) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title.appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .statsCard)
                
                if showIcon {
                    Image(systemName: "banknote")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .themeSkinLegibleText(level: .chip, slot: .statsCard)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 年份选择器
struct YearSelectorView: View {
    @Binding var year: Int
    var showStats: Bool = true
    var onToggleStats: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Button {
                withAnimation {
                    year -= 1
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(DepositPlanFormatters.yearText(year))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .monospacedDigit()
            
            Spacer()
            
            Button {
                withAnimation {
                    year += 1
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            // 小眼睛按钮放在年份选择器右侧 - 折叠价格时显示闭眼 (eye.slash)，显示价格时显示睁眼 (eye)
            if let onToggle = onToggleStats {
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                Button(action: onToggle) {
                    ThemeSkinIconBadge(
                        systemName: showStats ? "eye" : "eye.slash",
                        fallbackColor: .pink,
                        size: 28,
                        symbolSize: 13
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .themeSkinSectionCard(cornerRadius: 16, showsDecoration: false)
    }
}

// MARK: - 年份统计卡片
struct YearStatsCard: View {
    let stats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal)
    let year: Int
    var isVisible: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 统计内容（可折叠）
            if isVisible {
                HStack(spacing: 0) {
                    DepositStatItem(title: "总件数/款", value: "\(stats.totalCount)/\(stats.styleCount)")
                    
                    Divider()
                        .frame(height: 30)
                    
                    DepositStatItem(title: "已付定金", value: DepositPlanFormatters.currencyText(stats.paidDeposit), valueColor: Color(hex: "FF9800"))
                    
                    Divider()
                        .frame(height: 30)
                    
                    DepositStatItem(title: "预约金额", value: DepositPlanFormatters.currencyText(stats.pendingBalance), valueColor: Color(hex: "C94C72"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16, showsDecoration: false)
    }
}

struct DepositStatItem: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    var titleColor: Color = .secondary
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title.appLocalized)
                .font(.caption)
                .foregroundStyle(titleColor)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .themeSkinLegibleText(level: .chip, slot: .statsCard)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
