import SwiftUI

struct VIPCenterView: View {
    @ObservedObject var vipManager = VIPManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showingPurchaseAlert = false
    @State private var alertMessage = ""
    @State private var showSkinSelection = false
    
    // Redeem Logic
    @State private var showingVIPRedeemAlert = false
    @State private var vipCodeInput = ""
    @State private var showingRedeemResultAlert = false
    @State private var redeemResultMessage = ""
    @Environment(ThemeManager.self) private var themeManager
    
    // VIP试用期弹窗状态
    @State private var showTrialPopup = false
    @State private var hasCheckedTrialOnAppear = false
    
    // MARK: - Style Helpers
    private var privilegeTitleColor: Color {
        vipManager.cardStyle == .monicaPink ? Color(hex: "FF69B4") : Color(hex: "FFD700")
    }
    
    private var privilegeIconColor: Color {
        vipManager.cardStyle == .monicaPink ? Color(hex: "FF69B4") : Color(hex: "FFD700")
    }
    
    private var privilegeBgColor: Color {
        vipManager.cardStyle == .monicaPink ? Color.white.opacity(0.9) : Color(hex: "1E1E1E")
    }
    
    private var privilegeTextColor: Color {
        vipManager.cardStyle == .monicaPink ? .black.opacity(0.8) : .white
    }
    
    private var privilegeDescColor: Color {
        vipManager.cardStyle == .monicaPink ? .black.opacity(0.6) : .gray
    }
    
    // 将复杂的渐变颜色计算提取为计算属性，避免body中类型检查超时
    private var purchaseButtonGradientColors: [Color] {
        if vipManager.cardStyle == .monicaPink {
            return [Color(hex: "FF69B4"), Color(hex: "FFC0CB")]
        } else {
            return [Color(hex: "FFD700"), Color(hex: "B8860B")]
        }
    }
    
    private var purchaseButtonForegroundColor: Color {
        vipManager.cardStyle == .monicaPink ? .white : .black
    }
    
    var body: some View {
        ZStack {
            // Background - Unified Style
            // Use App Background Image or Color
            Group {
                if themeManager.backgroundStyle == .image, let image = themeManager.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    themeManager.backgroundColor
                        .ignoresSafeArea()
                }
            }
            
            // Dark overlay for better contrast
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    // Title
                    Text("会员中心")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.top)
                    
                    // Card
                    VIPCardView(
                        vipNumber: vipManager.vipNumber ?? "00000000",
                        expireDate: vipManager.vipExpireDate,
                        isVIP: vipManager.isVIP,
                        cardStyle: vipManager.cardStyle
                    )
                    .aspectRatio(1.58, contentMode: .fit) // 保持信用卡比例
                    .padding(.horizontal)
                    .onTapGesture {
                        // Secret way to trigger redeem? Or maybe add a dedicated button.
                        // User asked to move the redeem code from General Settings to here.
                        // I will add a button below the privileges or at the bottom.
                    }
                    
                    // Privileges
                    VStack(alignment: .leading, spacing: 20) {
                        Text("会员特权")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(privilegeTitleColor)
                        
                        privilegeRow(icon: "brain.head.profile", title: "智能对话", desc: "解锁基于语言大模型 的超强 AI 对话能力，萌宠变身贴心管家。")
                        // privilegeRow(icon: "mic.fill", title: "语音交互", desc: "支持自然语言语音对话，无需打字。") // todo 暂时相关功能还没整合到萌宠对话
                        privilegeRow(icon: "crown.fill", title: "尊贵身份", desc: getCardDescription())
                    }
                    .padding()
                    .background(privilegeBgColor)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Purchase Action
                    VStack(spacing: 16) {
                        Button {
                            handlePurchase()
                        } label: {
                            HStack {
                                Text("兑换会员时长")
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(VIPManager.monthlyPrice) 喵币 / 月")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: purchaseButtonGradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(purchaseButtonForegroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .captureGlobalFrame { frame in
                            AppFirstLaunchGuideManager.shared.updateAIAnalysisExchangeButtonFrame(frame)
                        }
                        
                        if vipManager.isVIP {
                            /*
                            Button {
                                showSkinSelection = true
                            } label: {
                                HStack {
                                    Text("设置卡片")
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text(vipManager.cardStyle.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }
                                .padding()
                                .background(Color(hex: "1E1E1E"))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            */
                        }
                        
                        Text("喵币不足？前往商店充值")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .underline()
                            .onTapGesture {
                                // TODO: Navigate to shop or show recharge sheet
                                // For now, maybe just show a hint
                            }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: 500) // iPad 适配：限制内容最大宽度
                .frame(maxWidth: .infinity) // 确保在 ScrollView 中居中
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showSkinSelection = true
                    } label: {
                        Label("设置卡片", systemImage: "creditcard")
                    }
                    
                    Button {
                        vipCodeInput = ""
                        showingVIPRedeemAlert = true
                    } label: {
                        Label("使用兑换码", systemImage: "gift")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showSkinSelection) {
            VIPCardSkinSelectionView()
        }
        .alert("会员订阅", isPresented: $showingPurchaseAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("VIP 兑换", isPresented: $showingVIPRedeemAlert) {
            TextField("请输入兑换码", text: $vipCodeInput)
            Button("取消", role: .cancel) { }
            Button("兑换") {
                redeemVIPCode()
            }
        } message: {
            Text("输入神秘代码获取奖励")
        }
        .alert("兑换结果", isPresented: $showingRedeemResultAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(redeemResultMessage)
        }
        // VIP试用期弹窗
        .overlay {
            if showTrialPopup {
                VIPTrialPopupView(
                    isPresented: $showTrialPopup,
                    onConfirm: {
                        // 用户点击确认体验，开始试用期
                        let result = vipManager.startTrialPeriod()
                        alertMessage = result.message
                        showingPurchaseAlert = true
                    },
                    onDismiss: {
                        // 用户点击稍后，只是关闭弹窗，下次还会显示
                        print("用户选择稍后体验VIP")
                    }
                )
            }
        }
        .onAppear {
            // 发送VIP中心打开通知，用于新手引导
            NotificationCenter.default.post(name: .vipCenterOpened, object: nil)
            
            // 每次进入VIP界面时检查是否需要显示试用期弹窗
            // 使用延迟确保视图已完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !hasCheckedTrialOnAppear && vipManager.canShowTrialOffer {
                    showTrialPopup = true
                }
                hasCheckedTrialOnAppear = true
            }
        }
    }
    
    private func getCardDescription() -> String {
        switch vipManager.cardStyle {
        case .blackGold:
            return "拥有独一无二的黑金靓号卡片。"
        case .monicaPink:
            return "拥有独一无二的莫妮卡粉色萌梦幻靓号卡片。"
        }
    }
    
    private func privilegeRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(privilegeIconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(privilegeTextColor)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(privilegeDescColor)
            }
        }
    }
    
    private func handlePurchase() {
        let result = vipManager.purchaseVIP()
        alertMessage = result.message
        showingPurchaseAlert = true
    }
    
    // 实验室入口状态
    @State private var showLabEntry = false
    
    private func redeemVIPCode() {
        let code = vipCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 先检查是否是功能解锁兑换码
        let featureResult = FeatureUnlockManager.shared.redeemCode(code)
        if featureResult.success {
            redeemResultMessage = featureResult.message
            showingRedeemResultAlert = true
            return
        }
        
        // 2. 检查是否是VIP兑换码
        if code == "太子爷" {
            let key = "HasRedeemedVIP_Prince"
            if UserDefaults.standard.bool(forKey: key) {
                redeemResultMessage = "您已经领取过该奖励啦！"
                showingRedeemResultAlert = true
            } else {
                UserDefaults.standard.set(true, forKey: key)
                
                // Use PetDataManager to update currency
                _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 666)
                _ = PetDataManager.shared.updateCurrency(type: .fishCoin, delta: 88888)
                
                redeemResultMessage = "兑换成功！\n获得 666 喵币\n88888 鱼币"
                showingRedeemResultAlert = true
            }
            return
        }
        
        // 3. 检查是否是管理员兑换码
        if code == "adminmuniao" {
            // 管理员兑换码：唤出实验室入口
            UserDefaults.standard.set(true, forKey: "LabEntryEnabled")
            redeemResultMessage = "实验室入口已开启！\n请前往「我的」页面查看"
            showingRedeemResultAlert = true
            return
        }
        
        // 4. 都不是，显示功能解锁的失败消息或其他提示
        if let feature = featureResult.feature {
            // 是功能兑换码但已经解锁过了
            redeemResultMessage = featureResult.message
        } else {
            redeemResultMessage = "兑换码无效"
        }
        showingRedeemResultAlert = true
    }
}

private extension View {
    func captureGlobalFrame(onChange: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        guard frame.width > 0, frame.height > 0 else { return }
                        onChange(frame)
                    }
                    .onChange(of: frame) { newValue in
                        guard newValue.width > 0, newValue.height > 0 else { return }
                        onChange(newValue)
                    }
            }
        )
    }
}

#Preview {
    VIPCenterView()
}
