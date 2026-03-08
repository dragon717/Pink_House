//
//  NetworkSettingsView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2026/3/9.
//

import SwiftUI

// MARK: - 联网设置视图
struct NetworkSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var networkManager = NetworkSettingsManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared
    
    @State private var showQuizView = false
    @State private var showDisableConfirmAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                List {
                    // 功能状态卡片
                    statusCardSection
                    
                    // 功能说明
                    featureDescriptionSection
                    
                    // 控制选项
                    if networkManager.isQuizUnlocked {
                        controlOptionsSection
                    }
                    
                    // 相关功能列表
                    if networkManager.canShowNetworkUI() {
                        relatedFeaturesSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("联网设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showQuizView) {
                NetworkQuizView()
            }
            .alert("确认关闭联网功能？", isPresented: $showDisableConfirmAlert) {
                Button("取消", role: .cancel) { }
                Button("关闭", role: .destructive) {
                    networkManager.setNetworkEnabled(false)
                }
            } message: {
                Text("关闭后，社区按钮、追根溯源等联网功能将不再显示。确定要关闭吗？")
            }
        }
    }
    
    // MARK: - 状态卡片区域
    private var statusCardSection: some View {
        Section {
            VStack(spacing: 20) {
                // 图标
                ZStack {
                    Circle()
                        .fill(statusIconBackgroundColor)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: statusIconName)
                        .font(.system(size: 36))
                        .foregroundStyle(statusIconColor)
                }
                
                // 标题
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(themeManager.primaryTextColor)
                
                // 描述
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // 操作按钮
                if !networkManager.isQuizUnlocked {
                    Button {
                        showQuizView = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.open.fill")
                            Text("答题解锁")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(themeManager.accentTextColor)
                        .cornerRadius(12)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(statusBorderColor, lineWidth: 1)
            )
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
    
    // MARK: - 功能说明区域
    private var featureDescriptionSection: some View {
        Section("功能说明") {
            VStack(alignment: .leading, spacing: 16) {
                FeatureDescriptionRow(
                    icon: "bubble.left.and.bubble.right",
                    title: "社区功能",
                    description: "在裙子详情页显示社区按钮，可以与其他用户交流分享",
                    themeManager: themeManager
                )
                
                FeatureDescriptionRow(
                    icon: "arrow.right.circle.fill",
                    title: "追根溯源",
                    description: "查看裙子的品牌历史和详细信息",
                    themeManager: themeManager
                )
                
                FeatureDescriptionRow(
                    icon: "square.and.arrow.up",
                    title: "加入联网",
                    description: "在创建或编辑裙子时，可以选择将裙子加入联网社区",
                    themeManager: themeManager
                )
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - 控制选项区域
    private var controlOptionsSection: some View {
        Section("联网控制") {
            // 联网开关
            HStack {
                Image(systemName: "network")
                    .frame(width: 24)
                    .foregroundStyle(themeManager.accentTextColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("启用联网功能")
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text("开启后可以使用社区相关功能")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { networkManager.isNetworkEnabled },
                    set: { newValue in
                        if !newValue {
                            // 关闭时需要确认
                            showDisableConfirmAlert = true
                        } else {
                            networkManager.setNetworkEnabled(true)
                        }
                    }
                ))
                .labelsHidden()
            }
            
            // 重新答题按钮
            Button {
                showQuizView = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 24)
                        .foregroundStyle(themeManager.accentTextColor)
                    
                    Text("重新答题")
                        .foregroundStyle(themeManager.primaryTextColor)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
            }
        }
    }
    
    // MARK: - 相关功能区域
    private var relatedFeaturesSection: some View {
        Section("相关功能") {
            NavigationLink(destination: Text("社区管理")) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .frame(width: 24)
                        .foregroundStyle(.pink)
                    Text("社区管理")
                        .foregroundStyle(themeManager.primaryTextColor)
                }
            }
            
            NavigationLink(destination: Text("我的分享")) {
                HStack {
                    Image(systemName: "person.2")
                        .frame(width: 24)
                        .foregroundStyle(.blue)
                    Text("我的分享")
                        .foregroundStyle(themeManager.primaryTextColor)
                }
            }
        }
    }
    
    // MARK: - 计算属性
    private var statusIconName: String {
        if networkManager.canShowNetworkUI() {
            return "network"
        } else if networkManager.isQuizUnlocked {
            return "network.slash"
        } else {
            return "lock.fill"
        }
    }
    
    private var statusIconColor: Color {
        if networkManager.canShowNetworkUI() {
            return .green
        } else if networkManager.isQuizUnlocked {
            return .orange
        } else {
            return themeManager.tertiaryTextColor
        }
    }
    
    private var statusIconBackgroundColor: Color {
        if networkManager.canShowNetworkUI() {
            return Color.green.opacity(colorScheme == .dark ? 0.3 : 0.2)
        } else if networkManager.isQuizUnlocked {
            return Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2)
        } else {
            return themeManager.secondaryTextColor.opacity(colorScheme == .dark ? 0.2 : 0.1)
        }
    }
    
    private var statusBorderColor: Color {
        if networkManager.canShowNetworkUI() {
            return Color.green.opacity(0.3)
        } else if networkManager.isQuizUnlocked {
            return Color.orange.opacity(0.3)
        } else {
            return themeManager.accentTextColor.opacity(0.2)
        }
    }
    
    private var statusTitle: String {
        if networkManager.canShowNetworkUI() {
            return "联网功能已开启"
        } else if networkManager.isQuizUnlocked {
            return "联网功能已关闭"
        } else {
            return "联网功能未解锁"
        }
    }
    
    private var statusDescription: String {
        if networkManager.canShowNetworkUI() {
            return "你可以使用社区、追根溯源等联网功能"
        } else if networkManager.isQuizUnlocked {
            return "联网功能已解锁但当前处于关闭状态"
        } else {
            return "完成答题挑战即可解锁联网功能"
        }
    }
}

// MARK: - 功能说明行
struct FeatureDescriptionRow: View {
    let icon: String
    let title: String
    let description: String
    let themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(themeManager.accentTextColor)
                .frame(width: 32, height: 32)
                .background(themeManager.accentTextColor.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.primaryTextColor)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - 预览
#Preview {
    NetworkSettingsView()
        .environment(ThemeManager.shared)
}
