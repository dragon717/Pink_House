//
//  PetChatMenuComponents.swift
//  ItemManager
//
//  萌宠对话菜单 - 可复用的菜单组件
//

import SwiftUI
import SwiftData

// MARK: - 菜单回调协议
struct PetChatMenuCallbacks {
    // AI搭配
    let handleOutfitSuggestion: (String) -> Void
    let createQuickOutfit: (String, String) -> Void
    
    // 快捷功能
    let handleWardrobeStatistics: () -> Void
    let handlePetStatusOverview: () -> Void
    let handleSwitchPetIntent: () -> Void
    let handleSecondPetAdoptionIntent: () -> Void
    let handleRenamePetIntent: () -> Void
    let handleInventoryPanel: () -> Void
    let handleShopPanel: () -> Void
    let handleWeatherOutfitGuidance: () -> Void
    let handleDepositPlanQuery: () -> Void
    let handleMoneyCounterPanel: () -> Void
    let handleDivinationPanel: () -> Void
    
    // 查找
    let onSearchWardrobe: () -> Void
    let onShowHistorySearch: () -> Void
}

// MARK: - 菜单数据上下文
struct PetChatMenuContext {
    let clothings: [Clothing]
    let quickMenuOwnedPets: [PetCharacter]
    let quickMenuAdoptionTitle: String?
}

// MARK: - 可复用的菜单项组件
struct PetChatMenuContent: View {
    let callbacks: PetChatMenuCallbacks
    let context: PetChatMenuContext
    let useSectionLayout: Bool  // 是否使用 Section 布局（iOS26+ 风格）
    
    var body: some View {
        if useSectionLayout {
            sectionBasedLayout
        } else {
            nestedMenuLayout
        }
    }
    
    // iOS26+ 风格：使用 Section 布局
    private var sectionBasedLayout: some View {
        Group {
            Section("AI搭配") {
                aiOutfitButtons
            }
            
            Menu {
                shortcutFunctionButtons
            } label: {
                Label("快捷功能", systemImage: "sparkles")
            }
            
            Section("查找") {
                searchButtons
            }
            
            Section("其他") {
                Button {
                    callbacks.handleDivinationPanel()
                } label: {
                    Label("今日运势", systemImage: "star.fill")
                }
            }
        }
    }
    
    // iOS18 以下风格：使用嵌套 Menu 布局
    private var nestedMenuLayout: some View {
        Group {
            Menu("AI搭配") {
                aiOutfitButtons
            }
            
            Menu("快捷功能") {
                shortcutFunctionButtons
            }
            
            searchButtons
        }
    }
    
    // AI搭配按钮组
    private var aiOutfitButtons: some View {
        Group {
            Button {
                callbacks.handleOutfitSuggestion("帮我搭配一套")
            } label: {
                Label("智能搭配", systemImage: "wand.and.stars")
            }
            
            if useSectionLayout {
                Menu {
                    quickOutfitButtons
                } label: {
                    Label("快速搭配", systemImage: "sparkles")
                }
            } else {
                quickOutfitButtons
            }
        }
    }
    
    // 快速搭配按钮
    private var quickOutfitButtons: some View {
        Group {
            Button {
                callbacks.createQuickOutfit("甜美", "约会")
            } label: {
                Label("甜美约会", systemImage: useSectionLayout ? "heart.fill" : "heart")
            }
            
            Button {
                callbacks.createQuickOutfit("优雅", "茶会")
            } label: {
                Label("优雅茶会", systemImage: useSectionLayout ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
            
            Button {
                callbacks.createQuickOutfit("日常", "出门")
            } label: {
                Label("日常出门", systemImage: useSectionLayout ? "bag.fill" : "bag")
            }
        }
    }
    
    // 快捷功能按钮组
    private var shortcutFunctionButtons: some View {
        Group {
            Button {
                callbacks.handleWardrobeStatistics()
            } label: {
                Label("统计裙子", systemImage: useSectionLayout ? "chart.pie.fill" : "chart.pie")
            }
            
            Button {
                callbacks.handlePetStatusOverview()
            } label: {
                Label("查看萌宠状态", systemImage: "heart.text.square.fill")
            }
            
            if context.quickMenuOwnedPets.count > 1 {
                Button {
                    callbacks.handleSwitchPetIntent()
                } label: {
                    Label("切换萌宠", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            
            if let adoptionTitle = context.quickMenuAdoptionTitle {
                Button {
                    callbacks.handleSecondPetAdoptionIntent()
                } label: {
                    Label(adoptionTitle, systemImage: "plus.circle.fill")
                }
            }
            
            Button {
                callbacks.handleRenamePetIntent()
            } label: {
                Label("改名", systemImage: "pencil")
            }
            
            Button {
                callbacks.handleInventoryPanel()
            } label: {
                Label("看看我的背包", systemImage: "shippingbox.fill")
            }
            
            Button {
                callbacks.handleShopPanel()
            } label: {
                Label("带我逛逛商店", systemImage: "cart.fill")
            }
            
            Button {
                callbacks.handleWeatherOutfitGuidance()
            } label: {
                Label("查看天气穿搭", systemImage: "cloud.sun.rain.fill")
            }
            
            Button {
                callbacks.handleDepositPlanQuery()
            } label: {
                Label("尾款提醒", systemImage: useSectionLayout ? "tag.fill" : "tag")
            }
            
            Button {
                callbacks.handleMoneyCounterPanel()
            } label: {
                Label("去来财数钞票", systemImage: "yensign.circle.fill")
            }
            
            Button {
                callbacks.handleDivinationPanel()
            } label: {
                Label("今日求签", systemImage: "wand.and.stars")
            }
        }
    }
    
    // 查找按钮组
    private var searchButtons: some View {
        Group {
            Button {
                callbacks.onSearchWardrobe()
            } label: {
                Label("查找衣柜", systemImage: "magnifyingglass")
            }
            
            Button {
                callbacks.onShowHistorySearch()
            } label: {
                Label("历史消息查询", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

// MARK: - iPad 专用内嵌菜单输入组件
@available(iOS 18.0, *)
struct PetChatiPadInputBar: View {
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void
    let callbacks: PetChatMenuCallbacks
    let context: PetChatMenuContext
    let focusRequestID: Int
    let onFocusChange: ((Bool) -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // iPad 版左侧内嵌原生菜单
            Menu {
                PetChatMenuContent(
                    callbacks: callbacks,
                    context: context,
                    useSectionLayout: false
                )
            } label: {
                ThemeSkinIconBadge(systemName: "plus", fallbackColor: .pink, size: 40, symbolSize: 20)
            }
            
            // 输入框部分（复用 PetDialogueInputView 的样式，但不带左侧按钮）
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.gray.opacity(0.6))
                        .padding(.horizontal, 16)
                }
                
                PetDialogueInputTextFieldWrapper(
                    text: $text,
                    focusRequestID: focusRequestID,
                    onFocusChange: onFocusChange,
                    onSend: onSend
                )
            }
            .themeSkinAdaptiveSectionCard(slot: .searchBar, cornerRadius: 22, showsDecoration: false) {
                Capsule().fill(Color(.systemBackground))
            }
            
            // 右侧发送按钮
            Button {
                if !text.isEmpty {
                    onSend()
                }
            } label: {
                ThemeSkinIconBadge(systemName: "pawprint.fill", fallbackColor: .pink, size: 44, symbolSize: 20)
            }
            .disabled(text.isEmpty)
            .opacity(text.isEmpty ? 0.5 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFD1DC"), Color(hex: "FFC0CB")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
                
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 30, y: geo.size.height - 25))
                        path.addLine(to: CGPoint(x: 18, y: geo.size.height + 6))
                        path.addLine(to: CGPoint(x: 50, y: geo.size.height - 15))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "FFC0CB"))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - TextField 包装器
@available(iOS 18.0, *)
private struct PetDialogueInputTextFieldWrapper: View {
    @Binding var text: String
    let focusRequestID: Int
    let onFocusChange: ((Bool) -> Void)?
    let onSend: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("", text: $text)
            .focused($isFocused)
            .font(.system(size: 17))
            .foregroundStyle(.primary)
            .submitLabel(.send)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(onSend)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onChange(of: isFocused) { _, newValue in
                onFocusChange?(newValue)
            }
            .onChange(of: focusRequestID) { _, newValue in
                guard newValue > 0 else { return }
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
    }
}
