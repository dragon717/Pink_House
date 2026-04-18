import SwiftUI

struct ThemeSkinStoreView: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @ObservedObject private var vipManager = VIPManager.shared
    @Environment(ThemeManager.self) private var themeManager

    @State private var alertTitle = "提示"
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showCoinStore = false

    private let featuredThemeID = "theme_skin.girl_closet"
    private let basePrice = 99

    private var vipPrice: Int {
        VIPManager.discountedPrice(basePrice, rate: VIPManager.themeSkinShopDiscountRate)
    }

    private var displayPrice: Int {
        vipManager.isVIP ? vipPrice : basePrice
    }

    private var currentBalance: Int {
        themeSkinManager.currentMeowCoinBalance
    }

    private var isPurchased: Bool {
        themeSkinManager.isPurchased(featuredThemeID)
    }

    private var isActive: Bool {
        themeSkinManager.isActiveTheme(featuredThemeID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                featuredThemeCard
                purchaseNotesCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
        .background(storeBackground.ignoresSafeArea())
        .refreshable {
            themeSkinManager.reloadFromDisk()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCoinStore = true
                } label: {
                    Label("喵币商店", systemImage: "pawprint.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showCoinStore) {
            MeowCoinStoreView()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("主题皮肤商店")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text("购买后仅可启用该主题自己的顶部栏、底部栏、搜索栏和卡片组件，不支持跨主题混搭。")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("当前余额")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeManager.secondaryTextColor)

                    Text("\(currentBalance)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text("喵币")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.accentTextColor)
                }
            }

            ViewThatFits(in: .horizontal) {
                statusChipRow
                statusChipColumn
            }
        }
        .padding(18)
        .background(cardShell(cornerRadius: 26))
    }

    private var featuredThemeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                featuredThemeHeader(isCompact: false)
                featuredThemeHeader(isCompact: true)
            }

            themeHighlights

            VStack(spacing: 10) {
                Button {
                    handlePurchase()
                } label: {
                    ThemeSkinActionLabel(
                        title: isPurchased ? "已购买少女衣橱主题" : "购买主题",
                        subtitle: isPurchased ? "主题组件已加入你的皮肤库" : "立即支付 \(displayPrice) 喵币，VIP 自动享 9 折",
                        systemImage: isPurchased ? "checkmark.seal.fill" : "bag.fill"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchased)
                .opacity(isPurchased ? 0.6 : 1)
                .background(primaryActionBackground(disabled: isPurchased))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        handleActivationToggle()
                    } label: {
                        ThemeSkinMiniActionLabel(
                            title: isActive ? "停用主题" : "应用主题",
                            systemImage: isActive ? "power.circle.fill" : "wand.and.stars"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPurchased)
                    .frame(maxWidth: .infinity)
                    .background(secondaryActionBackground(enabled: isPurchased))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(isPurchased ? 1 : 0.45)

                    NavigationLink {
                        ThemeSkinDetailView(themeId: featuredThemeID)
                    } label: {
                        ThemeSkinMiniActionLabel(
                            title: "进入详情",
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .background(detailActionBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(cardShell(cornerRadius: 28))
    }

    private var statusChipRow: some View {
        HStack(spacing: 10) {
            purchaseStateChip
            activeStateChip
            vipStateChip
        }
    }

    private var statusChipColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                purchaseStateChip
                activeStateChip
            }

            vipStateChip
        }
    }

    private var purchaseStateChip: some View {
        ThemeSkinInfoChip(
            title: isPurchased ? "已购" : "未购",
            systemImage: isPurchased ? "checkmark.circle.fill" : "sparkles",
            tint: isPurchased ? .green : themeManager.accentTextColor
        )
    }

    private var activeStateChip: some View {
        ThemeSkinInfoChip(
            title: isActive ? "使用中" : "未启用",
            systemImage: isActive ? "wand.and.stars.inverse" : "circle.dashed",
            tint: isActive ? Color(hex: "FF6BA6") : themeManager.secondaryTextColor
        )
    }

    private var vipStateChip: some View {
        Group {
            if vipManager.isVIP {
                DiscountBadgeView(text: VIPManager.themeSkinDiscountText, style: .capsuleGlow, size: .small)
            } else {
                ThemeSkinInfoChip(
                    title: "VIP \(vipPrice)喵币",
                    systemImage: "crown.fill",
                    tint: Color(hex: "FF8A5B")
                )
            }
        }
    }

    private func featuredThemeHeader(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 14) {
                    themePreview
                    featuredThemeHeaderText
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    themePreview
                    featuredThemeHeaderText
                }
            }
        }
    }

    private var featuredThemeHeaderText: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("少女衣橱")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text("奶白圆角壳、浅粉描边、贴纸感装饰，优先替换系统顶部栏、底部栏、搜索栏与核心卡片。")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                ThemeSkinStatusBadge(isPurchased: isPurchased, isActive: isActive)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(displayPrice)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(themeManager.primaryTextColor)

                Text("喵币")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.secondaryTextColor)

                Text("原价 \(basePrice)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .strikethrough()

                Spacer(minLength: 0)

                if vipManager.isVIP {
                    DiscountBadgeView(
                        text: VIPManager.themeSkinDiscountText,
                        style: .capsuleGlow,
                        size: .small
                    )
                }
            }
        }
    }

    private var purchaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("购买说明")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            ThemeSkinBulletRow(text: "购买后只能启用“少女衣橱”主题内的组件，不会与其他主题皮肤混用。")
            ThemeSkinBulletRow(text: "每个组件支持单独启用或停用，未启用时回退系统默认样式。")
            ThemeSkinBulletRow(text: "若喵币不足，可直接从右上角进入喵币商店补充。")
        }
        .padding(18)
        .background(cardShell(cornerRadius: 24))
    }

    private var themePreview: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "FFF7F4"),
                            Color(hex: "FFE5EE"),
                            Color(hex: "FFD7E5")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 132)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule()
                            .fill(Color.white.opacity(0.86))
                            .frame(width: 56, height: 14)
                        Capsule()
                            .fill(Color(hex: "FF9BBC").opacity(0.28))
                            .frame(width: 72, height: 16)
                        Capsule()
                            .fill(Color.white.opacity(0.76))
                            .frame(width: 42, height: 12)
                    }
                    .padding(14)
                }

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "FF8AAF"))
                )
                .offset(x: -8, y: -8)
        }
    }

    private var themeHighlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主题组件")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(themeManager.primaryTextColor)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ThemeSkinSlotTag(title: "顶部栏")
                ThemeSkinSlotTag(title: "底部栏")
                ThemeSkinSlotTag(title: "搜索栏")
                ThemeSkinSlotTag(title: "统计卡")
                ThemeSkinSlotTag(title: "商品卡")
                ThemeSkinSlotTag(title: "设置卡")
            }
        }
    }

    private var storeBackground: some View {
        LinearGradient(
            colors: [
                themeManager.backgroundColor.opacity(0.96),
                Color.white.opacity(0.45),
                themeManager.cardTintColor.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func cardShell(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background(CardBackgroundView(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.78),
                                themeManager.cardTintColor.opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            )
            .shadow(color: themeManager.cardTintColor.opacity(0.10), radius: 20, x: 0, y: 10)
    }

    private func primaryActionBackground(disabled: Bool) -> some View {
        LinearGradient(
            colors: disabled
                ? [Color.gray.opacity(0.28), Color.gray.opacity(0.18)]
                : [Color(hex: "FFB7CF"), Color(hex: "FFC7AB")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func secondaryActionBackground(enabled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(enabled ? themeManager.cardTintColor.opacity(0.18) : Color.gray.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeManager.cardTintColor.opacity(enabled ? 0.32 : 0.12), lineWidth: 1)
            )
    }

    private var detailActionBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
    }

    private func handlePurchase() {
        guard !isPurchased else { return }

        if currentBalance < displayPrice {
            showCoinStore = true
            return
        }

        let result = themeSkinManager.purchaseTheme(featuredThemeID, autoActivateIfNeeded: true)
        present(result)
    }

    private func handleActivationToggle() {
        guard isPurchased else { return }

        let result = isActive
            ? themeSkinManager.deactivateCurrentTheme()
            : themeSkinManager.activateTheme(featuredThemeID)
        present(result)
    }

    private func present(_ result: ThemeSkinActionResult) {
        alertTitle = result.success ? "操作成功" : "操作失败"
        alertMessage = result.message
        showAlert = true
    }
}

private struct ThemeSkinStatusBadge: View {
    let isPurchased: Bool
    let isActive: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(isPurchased ? "已购" : "未购")
                .font(.caption.weight(.bold))
                .foregroundStyle(isPurchased ? Color.green : Color(hex: "FF7E9F"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((isPurchased ? Color.green : Color(hex: "FF7E9F")).opacity(0.14))
                )

            if isActive {
                Text("使用中")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: "FF5C93"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.84))
                    )
            }
        }
    }
}

private struct ThemeSkinInfoChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct ThemeSkinSlotTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: "B75C7C"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.76))
            )
            .overlay(
                Capsule()
                    .stroke(Color(hex: "FFB5CB").opacity(0.85), lineWidth: 1)
            )
    }
}

private struct ThemeSkinActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.black.opacity(0.88))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ThemeSkinMiniActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

private struct ThemeSkinBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: "FF8FAE"))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        ThemeSkinStoreView()
            .environment(ThemeManager.shared)
    }
}
