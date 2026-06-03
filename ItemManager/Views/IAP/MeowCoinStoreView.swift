import SwiftUI
import StoreKit
import UIKit
import MessageUI

// MARK: - 喵币商店页面
// 用户购买喵币的主要界面

struct MeowCoinStoreView: View {
    @StateObject private var viewModel = IAPViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticShareItems: [Any] = []
    @State private var diagnosticMailAttachments: [MailAttachment] = []
    @State private var showDiagnosticMailComposer = false
    @State private var showDiagnosticShareSheet = false
    @State private var showDiagnosticAlert = false
    @State private var diagnosticAlertMessage = ""
    @State private var shouldOpenDiagnosticShareAfterAlert = false
    @State private var isPreparingDiagnosticFeedback = false
    @State private var showingOfferCodeInfoAlert = false
    @State private var showingOfferCodeRedemption = false
    @State private var showingOfferCodeErrorAlert = false
    @State private var offerCodeErrorMessage = "暂时无法打开 App Store 优惠码兑换界面，请稍后重试。".appLocalized

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // 余额卡片
                        balanceCard

                        // 喵币充值选项
                        coinPurchaseSection

                        // App Store 兑换码
                        offerCodeSection

                        // VIP说明
                        vipExchangeHintSection

                        // 服务协议
                        termsSection
                    }
                    .padding(.vertical)
                }

                // 成功提示
                if viewModel.showSuccessToast {
                    SuccessToast(message: viewModel.successMessage) {
                        viewModel.dismissSuccessToast()
                    }
                }
            }
            .navigationTitle("获取喵币".appLocalized)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("问题反馈".appLocalized) {
                        exportDiagnostics()
                    }
                    .disabled(isPreparingDiagnosticFeedback)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成".appLocalized) {
                        dismiss()
                    }
                }
            }
            .alert("购买失败".appLocalized, isPresented: $viewModel.showErrorAlert) {
                Button("确定".appLocalized) {
                    viewModel.dismissErrorAlert()
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("问题反馈".appLocalized, isPresented: $showDiagnosticAlert) {
                Button("确定".appLocalized, role: .cancel) {
                    if shouldOpenDiagnosticShareAfterAlert {
                        shouldOpenDiagnosticShareAfterAlert = false
                        showDiagnosticShareSheet = true
                    }
                }
            } message: {
                Text(diagnosticAlertMessage)
            }
            .alert("使用 App Store 兑换码".appLocalized, isPresented: $showingOfferCodeInfoAlert) {
                Button("取消".appLocalized, role: .cancel) { }
                Button("继续".appLocalized) {
                    Task {
                        await prepareAndShowOfferCodeRedemption()
                    }
                }
            } message: {
                Text("请输入官方 App Store 优惠码。".appLocalized)
            }
            .alert("App Store 兑换码".appLocalized, isPresented: $showingOfferCodeErrorAlert) {
                Button("知道了".appLocalized, role: .cancel) { }
            } message: {
                Text(offerCodeErrorMessage)
            }
            .sheet(isPresented: $showDiagnosticMailComposer) {
                MailComposer(
                    subject: diagnosticMailSubject,
                    recipients: [LegalLinks.supportEmailAddress],
                    messageBody: diagnosticMailBody,
                    attachments: diagnosticMailAttachments
                ) { result, error in
                    handleDiagnosticMailResult(result: result, error: error)
                }
            }
            .sheet(isPresented: $showDiagnosticShareSheet) {
                ShareSheet(items: diagnosticShareItems)
            }
            .task {
                await viewModel.fetchProducts()
            }
            .offerCodeRedemption(isPresented: $showingOfferCodeRedemption) { result in
                if case .failure(let error) = result {
                    Task {
                        await IAPDiagnosticStore.shared.record(
                            category: .flow,
                            name: "redemption_sheet_callback",
                            level: .error,
                            fields: [
                                "source": "meow_coin_store",
                                "result": "failure",
                                "error": error.localizedDescription,
                                "eligibleProductIDs": IAPOfferCodeRedemption.eligibleProductIDs.joined(separator: ",")
                            ]
                        )
                    }
                    StoreManager.shared.cancelOfferCodeRedemptionSession(reason: "meow_coin_store_redemption_failed: \(error.localizedDescription)")
                    offerCodeErrorMessage = "无法打开 App Store 优惠码兑换界面：%@".appLocalized(error.localizedDescription)
                    showingOfferCodeErrorAlert = true
                } else {
                    Task {
                        await IAPDiagnosticStore.shared.record(
                            category: .flow,
                            name: "redemption_sheet_callback",
                            level: .notice,
                            fields: [
                                "source": "meow_coin_store",
                                "result": "success_or_dismissed",
                                "eligibleProductIDs": IAPOfferCodeRedemption.eligibleProductIDs.joined(separator: ",")
                            ]
                        )
                    }
                }
            }
        }
    }

    // MARK: - 余额卡片
    private var balanceCard: some View {
        VStack(spacing: 16) {
            // 喵币图标
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .yellow.opacity(0.3), radius: 10, x: 0, y: 5)

            VStack(spacing: 8) {
                Text("当前余额".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(viewModel.currentBalance)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("喵币".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [.yellow.opacity(0.3), .orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal)
    }

    // MARK: - 喵币充值区域
    private var coinPurchaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("获取喵币".appLocalized)
                    .font(.title2.bold())

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)

            // 首次双倍活动横幅
            FirstDoubleBanner(refreshToken: viewModel.firstPurchaseStatusVersion)
                .padding(.horizontal)

            if viewModel.meowCoinProducts.isEmpty {
                // 加载中或无法获取商品时的占位
                EmptyProductPlaceholder()
                    .padding(.horizontal)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(viewModel.meowCoinProducts) { product in
                        CoinProductCard(
                            product: product,
                            refreshToken: viewModel.firstPurchaseStatusVersion,
                            isPurchasing: viewModel.isPurchasing
                        ) {
                            Task {
                                await viewModel.purchaseMeowCoin(product: product)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - App Store 兑换码入口
    private var offerCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store 优惠码".appLocalized)
                .font(.title2.bold())
                .padding(.horizontal)

            Button {
                showingOfferCodeInfoAlert = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "gift.fill")
                        .font(.title2)
                        .foregroundStyle(.pink)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.pink.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("兑换 App Store 优惠码".appLocalized)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("支持 6 个喵币档优惠码，不影响首充双倍".appLocalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    // MARK: - VIP兑换说明
    private var vipExchangeHintSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("VIP会员".appLocalized)
                    .font(.title2.bold())

                Spacer()

                if viewModel.isVIP {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                        Text("已开通".appLocalized)
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.yellow.opacity(0.15))
                    )
                }
            }
            .padding(.horizontal)

            if viewModel.isVIP, let expireDate = viewModel.vipExpireDate {
                Text("有效期至: %@".appLocalized(expireDate.formatted(date: .long, time: .omitted)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("VIP 不单独售卖".appLocalized, systemImage: "info.circle.fill")
                    .font(.headline)

                Text("先购买喵币，再前往会员中心兑换会员时长。".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("当前兑换价格：66 喵币 / 月".appLocalized)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .padding(.horizontal)
        }
    }

    // MARK: - 服务协议
    private var termsSection: some View {
        VStack(spacing: 8) {
            Text("由于虚拟商品的特殊性，购买成功后不支持退款".appLocalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("购买即表示同意".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("用户服务协议".appLocalized) {
                    openExternalURL(LegalLinks.userAgreementURL)
                }
                .font(.caption)

                Text("和".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("隐私政策".appLocalized) {
                    openExternalURL(LegalLinks.privacyURL)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func openExternalURL(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func prepareAndShowOfferCodeRedemption() async {
        let isReady = await StoreManager.shared.prepareOfferCodeRedemptionSession(source: "meow_coin_store")
        if isReady {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "redemption_sheet_presenting",
                level: .notice,
                fields: [
                    "source": "meow_coin_store",
                    "eligibleProductIDs": IAPOfferCodeRedemption.eligibleProductIDs.joined(separator: ",")
                ]
            )
            showingOfferCodeRedemption = true
        } else {
            offerCodeErrorMessage = "当前 App Store 环境没有返回任何可兑换的喵币商品，优惠码无法兑换。请检查 6 个喵币档是否可用、每个 Free Offer 是否绑定对应商品；沙盒账号只能测试 Sandbox Codes，不能兑换生产环境 URL / Custom / One-Time Use Codes。".appLocalized
            showingOfferCodeErrorAlert = true
        }
    }

    private func exportDiagnostics() {
        guard !isPreparingDiagnosticFeedback else { return }

        isPreparingDiagnosticFeedback = true
        Task {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "diagnostics_feedback_requested",
                level: .notice,
                fields: ["channel": "mail_preferred"]
            )

            do {
                let exportedURL = try await viewModel.exportDiagnostics()

                if MailComposer.canSendMail() {
                    let attachment = try MailAttachment(
                        fileURL: exportedURL,
                        mimeType: "application/x-ndjson"
                    )

                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "diagnostics_feedback_mail_ready",
                        level: .notice,
                        fields: ["fileName": exportedURL.lastPathComponent]
                    )

                    await MainActor.run {
                        diagnosticMailAttachments = [attachment]
                        showDiagnosticMailComposer = true
                        isPreparingDiagnosticFeedback = false
                    }
                } else {
                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "diagnostics_feedback_mail_unavailable",
                        level: .notice,
                        fields: [
                            "fallback": "share_sheet",
                            "fileName": exportedURL.lastPathComponent
                        ]
                    )

                    await MainActor.run {
                        diagnosticShareItems = [exportedURL]
                        diagnosticAlertMessage = "当前设备没有配置系统邮件账户，已改为打开文件分享。请将日志文件发送给开发者邮箱：%@".appLocalized(LegalLinks.supportEmailAddress)
                        shouldOpenDiagnosticShareAfterAlert = true
                        showDiagnosticAlert = true
                        isPreparingDiagnosticFeedback = false
                    }
                }
            } catch {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "diagnostics_feedback_export_failed",
                    level: .error,
                    fields: ["error": error.localizedDescription]
                )

                await MainActor.run {
                    diagnosticAlertMessage = "问题反馈日志导出失败：%@".appLocalized(error.localizedDescription)
                    shouldOpenDiagnosticShareAfterAlert = false
                    showDiagnosticAlert = true
                    isPreparingDiagnosticFeedback = false
                }
            }
        }
    }

    private var diagnosticMailSubject: String {
        "Pink House IAP 问题反馈".appLocalized
    }

    private var diagnosticMailBody: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
        return """
        你好，开发者：

        我遇到了应用内购买问题，已自动附带 IAP 诊断日志文件。

        请补充以下信息：
        - 触发时间：
        - 商品档位：
        - 是否弹出系统支付面板：
        - 实际结果：
        - 期望结果：

        当前应用版本：%@ (%@)
        """.appLocalized(version, build)
    }

    private func handleDiagnosticMailResult(result: MFMailComposeResult, error: Error?) {
        diagnosticMailAttachments = []
        showDiagnosticMailComposer = false

        Task {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "diagnostics_feedback_mail_finished",
                level: error == nil ? .notice : .error,
                fields: [
                    "result": diagnosticMailResultText(result),
                    "error": error?.localizedDescription ?? "none"
                ]
            )
        }

        if let error {
            diagnosticAlertMessage = "邮件草稿打开失败：%@".appLocalized(error.localizedDescription)
            shouldOpenDiagnosticShareAfterAlert = false
            showDiagnosticAlert = true
        }
    }

    private func diagnosticMailResultText(_ result: MFMailComposeResult) -> String {
        switch result {
        case .cancelled:
            return "cancelled"
        case .saved:
            return "saved"
        case .sent:
            return "sent"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - 首次双倍活动横幅
struct FirstDoubleBanner: View {
    let refreshToken: Int
    @State private var hasFirstDouble = FirstDoubleBonusManager.shared.hasAnyFirstDoubleBonus()

    private func refreshBannerState() {
        hasFirstDouble = FirstDoubleBonusManager.shared.hasAnyFirstDoubleBonus()
    }

    var body: some View {
        Group {
            if hasFirstDouble {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.yellow)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("🎉 首充双倍活动".appLocalized)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)

                        Text("首次购买任意档位，喵币数量翻倍！".appLocalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.2), .orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .onAppear {
            refreshBannerState()
        }
        .onChange(of: refreshToken) { _, _ in
            refreshBannerState()
        }
    }
}

// MARK: - 喵币商品卡片
struct CoinProductCard: View {
    let product: MeowCoinProductDisplay
    let refreshToken: Int
    let isPurchasing: Bool
    let onPurchase: () -> Void
    @State private var hasFirstDouble: Bool = false

    private func updateFirstDoubleStatus() {
        hasFirstDouble = FirstDoubleBonusManager.shared.hasFirstDoubleBonus(for: product.id)
    }

    var body: some View {
        Button(action: onPurchase) {
            VStack(spacing: 12) {
                // 标签区域
                HStack(alignment: .top) {
                    if hasFirstDouble {
                        Text("首充双倍".appLocalized)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.red)
                            )
                    }

                    Spacer(minLength: 0)

                    if let tag = product.tag,
                       !(hasFirstDouble && product.isBonusRateTag) {
                        Text(tag)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(product.isBestValue ? Color.green : Color.orange)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: 22)

                VStack(spacing: 8) {
                    Image(product.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 4)

                    VStack(spacing: 2) {
                        Text(product.packageName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        if hasFirstDouble {
                            VStack(spacing: 2) {
                                Text(product.firstDoubleTitle)
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)

                                Text(product.baseTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                            }
                        } else {
                            Text(product.displayTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }

                    if !product.subtitle.isEmpty && !hasFirstDouble {
                        Text(product.subtitle)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                Text(product.price)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(hasFirstDouble ? Color.red : Color.blue)
                    )
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 210, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        hasFirstDouble ? Color.red.opacity(0.5) :
                        product.isBestValue ? Color.green.opacity(0.5) :
                        product.isPopular ? Color.orange.opacity(0.5) :
                        Color.clear,
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPurchasing)
        .opacity(isPurchasing ? 0.75 : 1.0)
        .onAppear {
            updateFirstDoubleStatus()
        }
        .onChange(of: refreshToken) { _, _ in
            updateFirstDoubleStatus()
        }
    }
}

// MARK: - 空商品占位符
struct EmptyProductPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("暂时无法获取商品信息".appLocalized)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("请检查网络连接或稍后重试".appLocalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - 成功提示
struct SuccessToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                Text(message)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                onDismiss()
            }
        }
    }
}

// MARK: - 预览
#Preview {
    MeowCoinStoreView()
}
