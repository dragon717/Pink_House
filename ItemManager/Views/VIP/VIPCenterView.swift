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
    
    var body: some View {
        ZStack {
            // Background
            if vipManager.cardStyle == .blackGold {
                Color(hex: "121212")
                    .ignoresSafeArea()
            } else {
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
                
                // Add a blur/dim overlay to ensure text readability if needed
                // But user just said "use app background image", so maybe keep it clean.
                // Or maybe add a slight dark overlay for better contrast.
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
            }
            
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
                            .foregroundStyle(Color(hex: "FFD700"))
                        
                        privilegeRow(icon: "brain.head.profile", title: "智能对话", desc: "解锁基于 DeepSeek 的超强 AI 对话能力，萌宠变身贴心闺蜜。")
                        privilegeRow(icon: "mic.fill", title: "语音交互", desc: "支持自然语言语音对话，无需打字。")
                        privilegeRow(icon: "crown.fill", title: "尊贵身份", desc: getCardDescription())
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Purchase Action
                    VStack(spacing: 16) {
                        Button {
                            handlePurchase()
                        } label: {
                            HStack {
                                Text(vipManager.isVIP ? "续费会员" : "立即开通")
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(VIPManager.monthlyPrice) 喵币 / 月")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: vipManager.cardStyle == .monicaPink 
                                        ? [Color(hex: "FF69B4"), Color(hex: "FFC0CB")] 
                                        : [Color(hex: "FFD700"), Color(hex: "B8860B")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(vipManager.cardStyle == .monicaPink ? .white : .black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(Color(hex: "FFD700"))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }
    
    private func handlePurchase() {
        let result = vipManager.purchaseVIP()
        alertMessage = result.message
        showingPurchaseAlert = true
    }
    
    private func redeemVIPCode() {
        let code = vipCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
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
        } else {
            redeemResultMessage = "兑换码无效"
            showingRedeemResultAlert = true
        }
    }
}

#Preview {
    VIPCenterView()
}
