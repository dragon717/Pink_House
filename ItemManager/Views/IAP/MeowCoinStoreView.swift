import SwiftUI
import StoreKit

// MARK: - 喵币商店页面
// 用户购买喵币的主要界面

struct MeowCoinStoreView: View {
    @StateObject private var viewModel = IAPViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // 余额卡片
                        balanceCard

                        // 喵币充值选项
                        coinPurchaseSection

                        // VIP会员选项
                        vipSubscriptionSection

                        // 恢复购买按钮
                        restoreButton

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
            .navigationTitle("获取喵币")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("购买失败", isPresented: $viewModel.showErrorAlert) {
                Button("确定") {
                    viewModel.dismissErrorAlert()
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("恢复购买", isPresented: $viewModel.showRestoreSuccess) {
                Button("确定") {
                    viewModel.dismissRestoreSuccess()
                }
            } message: {
                Text(viewModel.restoreMessage)
            }
            .task {
                await viewModel.fetchProducts()
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
                Text("当前余额")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(viewModel.currentBalance)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("喵币")
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
                Text("获取喵币")
                    .font(.title2.bold())

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)

            // 首次双倍活动横幅
            FirstDoubleBanner()
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
                        CoinProductCard(product: product) {
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

    // MARK: - VIP订阅区域
    private var vipSubscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("VIP会员")
                    .font(.title2.bold())

                Spacer()

                if viewModel.isVIP {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                        Text("已开通")
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
                Text("有效期至: \(expireDate.formatted(date: .long, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // VIP特权列表
            VIPBenefitsGrid()
                .padding(.horizontal)

            // VIP购买选项
            if !viewModel.vipProducts.isEmpty {
                VStack(spacing: 12) {
                    ForEach(viewModel.vipProducts) { product in
                        VIPProductCard(product: product) {
                            Task {
                                await viewModel.purchaseVIP(product: product)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 恢复购买按钮
    private var restoreButton: some View {
        Button {
            Task {
                await viewModel.restorePurchases()
            }
        } label: {
            Text("恢复购买")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .disabled(viewModel.isLoading)
        .padding(.top, 8)
    }

    // MARK: - 服务协议
    private var termsSection: some View {
        VStack(spacing: 8) {
            Text("由于虚拟商品的特殊性，购买成功后不支持退款")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("购买即表示同意")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("用户服务协议") {
                    // 打开用户协议
                }
                .font(.caption)

                Text("和")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("隐私政策") {
                    // 打开隐私政策
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - 首次双倍活动横幅
struct FirstDoubleBanner: View {
    @State private var hasFirstDouble = FirstDoubleBonusManager.shared.hasFirstDoubleBonus()

    var body: some View {
        if hasFirstDouble {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 4) {
                    Text("🎉 首充双倍活动")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Text("首次购买任意档位，喵币数量翻倍！")
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
}

// MARK: - 喵币商品卡片
struct CoinProductCard: View {
    let product: MeowCoinProductDisplay
    let onPurchase: () -> Void
    @State private var hasFirstDouble = FirstDoubleBonusManager.shared.hasFirstDoubleBonus()

    var body: some View {
        Button(action: onPurchase) {
            VStack(spacing: 12) {
                // 标签区域
                HStack {
                    // 首次双倍标签
                    if hasFirstDouble {
                        Text("首充双倍")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.red)
                            )
                    }

                    Spacer()

                    // 普通标签
                    if let tag = product.tag {
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
                .frame(height: 22)

                // 喵币图标和数量
                VStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 显示数量
                    if hasFirstDouble {
                        // 首次双倍显示
                        VStack(spacing: 2) {
                            Text("\(product.totalCoins * 2)")
                                .font(.title2.bold())
                                .foregroundStyle(.primary)

                            Text("\(product.totalCoins)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                        }
                    } else {
                        // 正常显示
                        Text(product.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    if !product.subtitle.isEmpty && !hasFirstDouble {
                        Text(product.subtitle)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                // 价格按钮
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
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
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
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - VIP商品卡片
struct VIPProductCard: View {
    let product: VIPProductDisplay
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.3), .orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.name)
                            .font(.headline)

                        if product.isRecommended {
                            Text("推荐")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.red)
                                )
                        }
                    }

                    Text(product.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let savings = product.savingsPercent {
                        Text("立省 \(savings)%")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                // 价格
                VStack(alignment: .trailing, spacing: 4) {
                    Text(product.price)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    Text(product.periodText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                product.isRecommended ? Color.yellow.opacity(0.5) : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - VIP特权网格
struct VIPBenefitsGrid: View {
    let benefits = VIPBenefit.allBenefits

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(benefits) { benefit in
                VIPBenefitItem(benefit: benefit)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }
}

// MARK: - VIP特权项
struct VIPBenefitItem: View {
    let benefit: VIPBenefit

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: benefit.icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(benefit.title)
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text(benefit.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
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

            Text("暂时无法获取商品信息")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("请检查网络连接或稍后重试")
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
