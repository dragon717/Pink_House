import SwiftUI

struct VIPCenterView: View {
    @ObservedObject private var vipManager = VIPManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingPurchaseAlert = false
    @State private var alertMessage = ""
    @State private var showSkinSelection = false
    @State private var showCoinStore = false
    @State private var showInfoAlert = false
    @State private var infoAlertTitle = ""
    @State private var infoAlertMessage = ""

    @State private var showingVIPRedeemAlert = false
    @State private var vipCodeInput = ""
    @State private var showingRedeemResultAlert = false
    @State private var redeemResultMessage = ""

    @State private var showTrialPopup = false
    @State private var hasCheckedTrialOnAppear = false
    @State private var selectedPlanID = "monthly"

    private var visualTheme: VIPVisualTheme {
        vipManager.preferredVisualTheme
    }

    private var selectedPlan: VIPPlan {
        vipManager.availablePlans.first(where: { $0.id == selectedPlanID }) ?? vipManager.availablePlans[0]
    }

    private var heroSubtitle: String {
        if vipManager.isVIP, let expireDate = vipManager.vipExpireDate {
            return "有效期至 \(expireDate.formatted(date: .numeric, time: .omitted))"
        }
        if vipManager.isInTrialPeriod, let expireDate = vipManager.vipExpireDate {
            return "体验中 · 截止 \(expireDate.formatted(date: .numeric, time: .omitted))"
        }
        return "开通后解锁智能能力、尊贵身份与专属优惠"
    }

    private var benefitsTopRows: [VIPBenefit] {
        [
            VIPBenefit(
                id: "statistics",
                title: "智能统计",
                subtitle: "本地分析 · 更懂你的衣橱",
                icon: "chart.bar.fill",
                preferredGlassStyle: .iceBlue
            ),
            VIPBenefit(
                id: "multimodal",
                title: "多模态智能",
                subtitle: "图片识别 · 智能互动",
                icon: "sparkles"
            ),
            VIPBenefit(
                id: "identity",
                title: "VIP身份",
                subtitle: "靓号身份 · 卡片皮肤",
                icon: "crown.fill",
                preferredGlassStyle: vipManager.cardStyle == .monicaPink ? .glossPink : .glossBlack
            ),
            VIPBenefit(
                id: "discount",
                title: "付费内容优惠",
                subtitle: "萌宠商店 \(VIPManager.petShopDiscountText)",
                icon: "ticket.fill"
            ),
            VIPBenefit(
                id: "weekly",
                title: "会员周报",
                subtitle: "每周总结 · 待做",
                icon: "doc.text.fill"
            ),
            VIPBenefit(
                id: "magicTheme",
                title: "魔法配色",
                subtitle: "主题特权 · 智能调色",
                icon: "paintpalette.fill",
                preferredGlassStyle: .glossPink
            )
        ]
    }

    private var benefitsBottomRow: [VIPBenefit] {
        [
            VIPBenefit(
                id: "icons",
                title: "个性图标",
                subtitle: "图标切换 · 专属收藏",
                icon: "square.grid.2x2.fill"
            ),
            VIPBenefit(
                id: "updates",
                title: "持续更新",
                subtitle: "主题皮肤商店 \(VIPManager.themeSkinDiscountText)  · 更多会员权益正在路上",
                icon: "heart.fill",
                preferredGlassStyle: .glossBlack,
                isWide: true
            )
        ]
    }

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    topBar
                    heroSection
                    benefitsSection
                    planSelectorSection
                    purchaseSection
                    agreementSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSkinSelection) {
            VIPCardSkinSelectionView()
        }
        .sheet(isPresented: $showCoinStore) {
            MeowCoinStoreView()
        }
        .alert("会员兑换", isPresented: $showingPurchaseAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert(infoAlertTitle, isPresented: $showInfoAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(infoAlertMessage)
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
        .overlay {
            if showTrialPopup {
                VIPTrialPopupView(
                    visualTheme: visualTheme,
                    isPresented: $showTrialPopup,
                    onConfirm: {
                        let result = vipManager.startTrialPeriod()
                        if result.success {
                            NotificationCenter.default.post(name: .vipExchangeAttempted, object: nil)
                        }
                        alertMessage = result.message
                        showingPurchaseAlert = true
                    },
                    onDismiss: {
                        print("用户选择稍后体验VIP")
                    }
                )
            }
        }
        .onChange(of: showTrialPopup) { _, isShowing in
            if !isShowing {
                AppFirstLaunchGuideManager.shared.resetGuideTargetFrames([.aiAnalysisVIPTrialConfirmButton])
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .vipCenterOpened, object: nil)
            if vipManager.availablePlans.contains(where: { $0.id == selectedPlanID }) == false {
                selectedPlanID = vipManager.availablePlans[0].id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !hasCheckedTrialOnAppear && vipManager.canShowTrialOffer {
                    showTrialPopup = true
                }
                hasCheckedTrialOnAppear = true
            }
        }
        .onDisappear {
            AppFirstLaunchGuideManager.shared.resetGuideTargetFrames([.aiAnalysisVIPTrialConfirmButton])
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: visualTheme.backgroundGradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(visualTheme.glowColor)
                .frame(width: 260, height: 260)
                .blur(radius: 48)
                .offset(x: -88, y: -250)

            Circle()
                .fill(visualTheme.glowColor.opacity(0.75))
                .frame(width: 220, height: 220)
                .blur(radius: 56)
                .offset(x: 108, y: -150)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("少女心愿")
                    .font(.system(size: 22, weight: .semibold))
                Text("VIP")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(visualTheme.accentColor.opacity(0.18)))
                    .overlay(
                        Capsule()
                            .stroke(visualTheme.accentColor.opacity(0.45), lineWidth: 1)
                    )
            }
            .foregroundStyle(.white)

            Spacer()

            Menu {
                Button {
                    if vipManager.isVIP {
                        showSkinSelection = true
                    } else {
                        presentInfoAlert(
                            title: "VIP身份",
                            message: "开通 VIP 后即可切换专属卡片皮肤，并解锁你的尊贵身份样式。"
                        )
                    }
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
                topButton(icon: "ellipsis")
            }

            Button {
                dismiss()
            } label: {
                topButton(icon: "xmark")
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            Text(vipManager.isVIP ? "守护少女每一份美好" : "给你的心愿一份更尊贵的守护")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(heroSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(visualTheme.secondaryTextColor)
                .multilineTextAlignment(.center)

            ZStack {
                VIPGlassCardBackground(glassStyle: visualTheme.primaryGlassStyle, cornerRadius: 28)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: vipManager.isVIP ? "checkmark.seal.fill" : "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(visualTheme.primaryGlassStyle.iconTint)
                        Text(statusTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(statusDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        heroTag(text: vipManager.isVIP ? "尊贵身份" : "智能升级")
                        heroTag(text: vipManager.isVIP ? currentIdentityTag : "试用可体验")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
            .frame(height: 154)

            Text("会员权益")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.76))
                .padding(.top, 4)
        }
    }

    private var benefitsSection: some View {
        VStack(spacing: 14) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(benefitsTopRows) { benefit in
                    benefitCard(for: benefit)
                }
            }

            HStack(spacing: 12) {
                if let iconBenefit = benefitsBottomRow.first {
                    benefitCard(for: iconBenefit)
                }

                if let wideBenefit = benefitsBottomRow.last {
                    benefitWideCard(for: wideBenefit)
                }
            }
        }
    }

    private var planSelectorSection: some View {
        HStack(spacing: 12) {
            ForEach(vipManager.availablePlans) { plan in
                Button {
                    selectedPlanID = plan.id
                } label: {
                    VStack(spacing: 8) {
                        HStack {
                            if let badge = plan.badgeText {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(visualTheme.accentColor.opacity(0.16)))
                                    .overlay(
                                        Capsule()
                                            .stroke(visualTheme.accentColor.opacity(0.42), lineWidth: 1)
                                    )
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .frame(height: 18)

                        Spacer()

                        Text(plan.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)

                        Text(plan.subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))

                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 126)
                    .background(
                        VIPGlassCardBackground(
                            glassStyle: selectedPlanID == plan.id ? visualTheme.primaryGlassStyle : .glossBlack,
                            cornerRadius: 22
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                selectedPlanID == plan.id
                                ? visualTheme.primaryGlassStyle.strokeColor.opacity(0.95)
                                : Color.white.opacity(0.08),
                                lineWidth: selectedPlanID == plan.id ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            Button {
                handlePurchase()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("兑换\(selectedPlan.title)会员")
                            .font(.system(size: 18, weight: .bold))
                        Text("开通后立即生效，可叠加有效期")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.68))
                    }

                    Spacer()

                    Text("\(selectedPlan.meowCoins)喵币")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.92))
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [
                            visualTheme.accentColor,
                            visualTheme.accentColor.opacity(0.82)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: visualTheme.glowColor, radius: 20, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .captureGuideTarget(.aiAnalysisExchangeButton)

            Button {
                showCoinStore = true
            } label: {
                Text("喵币不足？前往商店获取喵币")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private var agreementSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text("请阅读并同意")
                    .foregroundStyle(Color.white.opacity(0.62))
                Text("会员协议")
                    .foregroundStyle(.white)
                Text("使用协议")
                    .foregroundStyle(.white)
            }
            .font(.system(size: 12, weight: .medium))

            Text("VIP 为喵币兑换型权益，不自动续费。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private func benefitCard(for benefit: VIPBenefit) -> some View {
        Button {
            handleBenefitTap(benefit)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: benefit.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle((benefit.preferredGlassStyle ?? visualTheme.secondaryGlassStyle).iconTint)

                Spacer(minLength: 0)

                Text(benefit.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                Text(benefit.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                VIPGlassCardBackground(
                    glassStyle: benefit.preferredGlassStyle ?? visualTheme.secondaryGlassStyle,
                    cornerRadius: 22
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func benefitWideCard(for benefit: VIPBenefit) -> some View {
        Button {
            handleBenefitTap(benefit)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: benefit.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle((benefit.preferredGlassStyle ?? visualTheme.secondaryGlassStyle).iconTint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(benefit.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(benefit.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(
                VIPGlassCardBackground(
                    glassStyle: benefit.preferredGlassStyle ?? visualTheme.secondaryGlassStyle,
                    cornerRadius: 22
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func topButton(icon: String) -> some View {
        ZStack {
            VIPGlassCardBackground(glassStyle: visualTheme.secondaryGlassStyle, cornerRadius: 18)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }

    private func heroTag(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private var statusTitle: String {
        if vipManager.isVIP {
            return vipManager.isInTrialPeriod ? "你正在体验 VIP 中" : "你已经拥有 VIP 身份"
        }
        return "升级为 VIP，解锁更完整的智能体验"
    }

    private var statusDescription: String {
        if vipManager.isVIP {
            return vipManager.isInTrialPeriod
                ? "体验期间即可抢先感受多模态智能、专属身份和会员优惠。"
                : "专属权益已生效，快去试试萌宠智能对话、卡片皮肤和会员优惠。"
        }
        return "本地能力依然可用，涉及第三方模型和 API 的智能能力会在开通后完整开放。"
    }

    private var currentIdentityTag: String {
        switch vipManager.cardStyle {
        case .blackGold:
            return "黑金尊享"
        case .monicaPink:
            return "莫妮卡粉"
        }
    }

    private func handleBenefitTap(_ benefit: VIPBenefit) {
        switch benefit.id {
        case "identity":
            if vipManager.isVIP {
                showSkinSelection = true
            } else {
                presentInfoAlert(
                    title: benefit.title,
                    message: "开通 VIP 后即可解锁专属身份标识、靓号与卡片皮肤。右上角的「设置卡片」入口也会继续保留。"
                )
            }
        case "discount":
            presentInfoAlert(
                title: benefit.title,
                message: "VIP 期间萌宠商店享 \(VIPManager.petShopDiscountText)，\n主题皮肤商店 \(VIPManager.themeSkinDiscountText)."
            )
        case "magicTheme":
            presentInfoAlert(
                title: benefit.title,
                message: "VIP 期间可直接使用魔法配色；若你已经单独花喵币解锁，就算 VIP 到期也不会关闭。"
            )
        case "icons":
            presentInfoAlert(
                title: benefit.title,
                message: "个性图标库会纳入当前默认图标与「少女心愿 logo」图标方案，作为专属收藏权益逐步开放。"
            )
        case "weekly":
            presentInfoAlert(
                title: benefit.title,
                message: "会员周报，后续会补充每周衣橱、萌宠与消费概览。"
            )
        case "updates":
            presentInfoAlert(
                title: benefit.title,
                message: "后续会持续补充主题皮肤商店、周报与更多会员限定内容。"
            )
        default:
            presentInfoAlert(title: benefit.title, message: benefit.subtitle)
        }
    }

    private func handlePurchase() {
        NotificationCenter.default.post(name: .vipExchangeAttempted, object: nil)
        let result = vipManager.purchaseVIP(plan: selectedPlan)
        alertMessage = result.message
        showingPurchaseAlert = true
    }

    private func presentInfoAlert(title: String, message: String) {
        infoAlertTitle = title
        infoAlertMessage = message
        showInfoAlert = true
    }

    private func redeemVIPCode() {
        let code = vipCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let featureResult = FeatureUnlockManager.shared.redeemCode(code)
        if featureResult.success {
            redeemResultMessage = featureResult.message
            showingRedeemResultAlert = true
            return
        }

        if code == "太子爷" {
            let key = "HasRedeemedVIP_Prince"
            if UserDefaults.standard.bool(forKey: key) {
                redeemResultMessage = "您已经领取过该奖励啦！"
                showingRedeemResultAlert = true
            } else {
                UserDefaults.standard.set(true, forKey: key)
                _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 666)
                _ = PetDataManager.shared.updateCurrency(type: .fishCoin, delta: 88888)
                redeemResultMessage = "兑换成功！\n获得 666 喵币\n88888 鱼币"
                showingRedeemResultAlert = true
            }
            return
        }

        if code == "adminmuniao" {
            UserDefaults.standard.set(true, forKey: "LabEntryEnabled")
            redeemResultMessage = "实验室入口已开启！\n请前往「我的」页面查看"
            showingRedeemResultAlert = true
            return
        }

        if featureResult.feature != nil {
            redeemResultMessage = featureResult.message
        } else {
            redeemResultMessage = "兑换码无效"
        }
        showingRedeemResultAlert = true
    }
}

#Preview {
    VIPCenterView()
}
