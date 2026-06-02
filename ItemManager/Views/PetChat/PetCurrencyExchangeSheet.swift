import SwiftUI

struct PetCurrencyExchangeSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var petDataManager = PetDataManager.shared

    @State private var direction: PetCurrencyExchangeDirection
    @State private var exchangeAmount: Double = 1
    @State private var showAmountInput = false
    @State private var inputAmountText = ""
    @State private var resultMessage: String?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    init(preferredDirection: PetCurrencyExchangeDirection) {
        _direction = State(initialValue: preferredDirection)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = ExchangeSheetLayout(containerWidth: geometry.size.width)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: layout.sectionSpacing) {
                        VStack(spacing: 8) {
                            Text("货币兑换".appLocalized)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(exchangeRateDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: layout.directionButtonMinimumWidth), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(PetCurrencyExchangeDirection.allCases) { item in
                                Button {
                                    direction = item
                                } label: {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(direction == item ? Color.white : themeManager.primaryTextColor)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 12)
                                        .background(direction == item ? themeManager.accentTextColor : Color.secondary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) {
                                exchangeBadgeCard(for: direction.sourceCurrency, layout: layout)

                                Image(systemName: "arrow.right")
                                    .font(.title3)
                                    .foregroundStyle(themeManager.tertiaryTextColor)

                                exchangeBadgeCard(for: direction.targetCurrency, layout: layout)
                            }

                            VStack(spacing: 14) {
                                exchangeBadgeCard(for: direction.sourceCurrency, layout: layout)

                                Image(systemName: "arrow.down")
                                    .font(.title3)
                                    .foregroundStyle(themeManager.tertiaryTextColor)

                                exchangeBadgeCard(for: direction.targetCurrency, layout: layout)
                            }
                        }

                        VStack(spacing: 12) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) {
                                    balanceCard(
                                        title: "%@余额".appLocalized(title(for: direction.sourceCurrency)),
                                        amount: sourceBalance,
                                        layout: layout
                                    )
                                    balanceCard(
                                        title: "%@余额".appLocalized(title(for: direction.targetCurrency)),
                                        amount: targetBalance,
                                        layout: layout
                                    )
                                }

                                VStack(spacing: 8) {
                                    balanceCard(
                                        title: "%@余额".appLocalized(title(for: direction.sourceCurrency)),
                                        amount: sourceBalance,
                                        layout: layout
                                    )
                                    balanceCard(
                                        title: "%@余额".appLocalized(title(for: direction.targetCurrency)),
                                        amount: targetBalance,
                                        layout: layout
                                    )
                                }
                            }

                            Button {
                                inputAmountText = "\(exchangeAmountValue)"
                                showAmountInput = true
                            } label: {
                                Text("兑换数量: %d".appLocalized(exchangeAmountValue))
                                    .font(.headline)
                                    .foregroundStyle(themeManager.primaryTextColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(!hasExchangeableBalance)

                            if showsSlider {
                                Slider(value: $exchangeAmount, in: sliderRange, step: sliderStep)
                                    .tint(themeManager.accentTextColor)

                                HStack {
                                    Text("\(Int(sliderRange.lowerBound))")
                                    Spacer()
                                    Text("\(Int(sliderRange.upperBound))")
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            } else if hasExchangeableBalance {
                                Text("当前最多可兑换 %d".appLocalized(maxExchangeableSourceAmount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if sourceBalance > 0 {
                                Text("目标货币已接近上限，暂时无法继续兑换".appLocalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("当前没有可用于兑换的%@".appLocalized(title(for: direction.sourceCurrency)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if hasExchangeableBalance {
                                Text("预计到账 %d %@".appLocalized(convertedTargetAmount(for: exchangeAmountValue) ?? 0, title(for: direction.targetCurrency)))
                                    .font(.caption)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                            }
                        }

                        Button {
                            performExchange()
                        } label: {
                            Text(direction.title)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(actionButtonColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!hasExchangeableBalance)
                        .opacity(hasExchangeableBalance ? 1 : 0.5)

                        if let resultMessage {
                            Text(resultMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.bottom, 24)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        _ = PetDataManager.shared.updateCurrency(type: .fishCoin, delta: 1000)
                        _ = PetDataManager.shared.updateCurrency(type: .boneCoin, delta: 1000)
                        resultMessage = "Debug：已增加 1000 %@和 1000 %@".appLocalized(PetCurrency.fishCoin.localizedName, PetCurrency.boneCoin.localizedName)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".appLocalized) {
                        dismiss()
                    }
                }
            }
            .alert("输入兑换数量".appLocalized, isPresented: $showAmountInput) {
                TextField("数量".appLocalized, text: $inputAmountText)
                    .keyboardType(.numberPad)
                Button("取消".appLocalized, role: .cancel) { }
                Button("确定".appLocalized) {
                    if let value = Int(inputAmountText), value > 0 {
                        exchangeAmount = min(Double(value), maxExchangeAmount)
                        clampExchangeAmount()
                    }
                }
            }
            .alert("兑换失败".appLocalized, isPresented: $showingErrorAlert) {
                Button("知道了".appLocalized, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                clampExchangeAmount()
            }
            .onChange(of: direction) { _, _ in
                resultMessage = nil
                clampExchangeAmount()
            }
        }
    }

    private var sliderStep: Double {
        guard maxExchangeableSourceAmount > 1 else { return 1 }
        if direction.sourceCurrency == .meowCoin { return 1 }
        return maxExchangeableSourceAmount >= 100 ? 100 : 1
    }

    private var sliderRange: ClosedRange<Double> {
        1...Double(max(2, maxExchangeableSourceAmount))
    }

    private var maxExchangeAmount: Double {
        Double(max(1, maxExchangeableSourceAmount))
    }

    private var hasExchangeableBalance: Bool {
        maxExchangeableSourceAmount > 0
    }

    private var showsSlider: Bool {
        maxExchangeableSourceAmount > 1
    }

    private var sourceBalance: Int {
        amount(for: direction.sourceCurrency)
    }

    private var targetBalance: Int {
        amount(for: direction.targetCurrency)
    }

    private var exchangeAmountValue: Int {
        max(0, Int(exchangeAmount))
    }

    private var exchangeRateDescription: String {
        switch direction {
        case .fishToBone, .boneToFish:
            return "汇率 1:1".appLocalized
        case .meowToFish:
            return "1 %@ = 1000 %@".appLocalized(PetCurrency.meowCoin.localizedName, PetCurrency.fishCoin.localizedName)
        case .meowToBone:
            return "1 %@ = 1000 %@".appLocalized(PetCurrency.meowCoin.localizedName, PetCurrency.boneCoin.localizedName)
        }
    }

    private var actionButtonColor: Color {
        switch direction.targetCurrency {
        case .meowCoin:
            return .yellow
        case .fishCoin:
            return .orange
        case .boneCoin:
            return Color(hex: "A56A2A")
        }
    }

    private var maxExchangeableSourceAmount: Int {
        guard sourceBalance > 0 else { return 0 }

        let targetHeadroom = Int.max - targetBalance
        guard targetHeadroom > 0 else { return 0 }

        let maxByTarget: Int
        switch direction {
        case .fishToBone, .boneToFish:
            maxByTarget = targetHeadroom
        case .meowToFish, .meowToBone:
            maxByTarget = targetHeadroom / 1000
        }

        return max(0, min(sourceBalance, maxByTarget))
    }

    private func amount(for currency: PetCurrency) -> Int {
        switch currency {
        case .meowCoin: return petDataManager.status.meowCoin
        case .fishCoin: return petDataManager.status.fishCoin
        case .boneCoin: return petDataManager.status.boneCoin
        }
    }

    private func title(for currency: PetCurrency) -> String {
        currency.localizedName
    }

    private func performExchange() {
        let sourceAmount = min(exchangeAmountValue, maxExchangeableSourceAmount)
        guard sourceAmount > 0 else {
            presentError("当前数量无法兑换".appLocalized)
            return
        }

        guard let targetAmount = convertedTargetAmount(for: sourceAmount) else {
            presentError("兑换数量过大，请减少后重试".appLocalized)
            return
        }

        var status = petDataManager.status
        switch direction {
        case .fishToBone:
            guard status.fishCoin >= sourceAmount else {
                presentError("%@不足".appLocalized(PetCurrency.fishCoin.localizedName))
                return
            }
            let (newBoneCoin, overflow) = status.boneCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("%@数量过大，暂时无法继续兑换".appLocalized(PetCurrency.boneCoin.localizedName))
                return
            }
            status.fishCoin -= sourceAmount
            status.boneCoin = newBoneCoin
            resultMessage = "兑换成功：%d %@ → %d %@".appLocalized(sourceAmount, PetCurrency.fishCoin.localizedName, targetAmount, PetCurrency.boneCoin.localizedName)
        case .boneToFish:
            guard status.boneCoin >= sourceAmount else {
                presentError("%@不足".appLocalized(PetCurrency.boneCoin.localizedName))
                return
            }
            let (newFishCoin, overflow) = status.fishCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("%@数量过大，暂时无法继续兑换".appLocalized(PetCurrency.fishCoin.localizedName))
                return
            }
            status.boneCoin -= sourceAmount
            status.fishCoin = newFishCoin
            resultMessage = "兑换成功：%d %@ → %d %@".appLocalized(sourceAmount, PetCurrency.boneCoin.localizedName, targetAmount, PetCurrency.fishCoin.localizedName)
        case .meowToFish:
            let (newFishCoin, overflow) = status.fishCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("%@数量过大，暂时无法继续兑换".appLocalized(PetCurrency.fishCoin.localizedName))
                return
            }
            guard StoreManager.spendMeowCoins(sourceAmount, in: &status) else {
                presentError("%@不足".appLocalized(PetCurrency.meowCoin.localizedName))
                return
            }
            status.fishCoin = newFishCoin
            resultMessage = "兑换成功：%d %@ → %d %@".appLocalized(sourceAmount, PetCurrency.meowCoin.localizedName, targetAmount, PetCurrency.fishCoin.localizedName)
        case .meowToBone:
            let (newBoneCoin, overflow) = status.boneCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("%@数量过大，暂时无法继续兑换".appLocalized(PetCurrency.boneCoin.localizedName))
                return
            }
            guard StoreManager.spendMeowCoins(sourceAmount, in: &status) else {
                presentError("%@不足".appLocalized(PetCurrency.meowCoin.localizedName))
                return
            }
            status.boneCoin = newBoneCoin
            resultMessage = "兑换成功：%d %@ → %d %@".appLocalized(sourceAmount, PetCurrency.meowCoin.localizedName, targetAmount, PetCurrency.boneCoin.localizedName)
        }

        PetDataManager.shared.saveStatus(status)
        NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
        clampExchangeAmount()
    }

    private func convertedTargetAmount(for sourceAmount: Int) -> Int? {
        guard sourceAmount > 0 else { return 0 }

        switch direction {
        case .fishToBone, .boneToFish:
            return sourceAmount
        case .meowToFish, .meowToBone:
            let (result, overflow) = sourceAmount.multipliedReportingOverflow(by: 1000)
            return overflow ? nil : result
        }
    }

    private func clampExchangeAmount() {
        guard hasExchangeableBalance else {
            exchangeAmount = 0
            return
        }
        let upper = maxExchangeAmount
        if exchangeAmount > upper {
            exchangeAmount = upper
        } else if exchangeAmount < 1 {
            exchangeAmount = 1
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }

    @ViewBuilder
    private func exchangeBadgeCard(for currency: PetCurrency, layout: ExchangeSheetLayout) -> some View {
        VStack(spacing: 10) {
            currencyBadge(for: currency, layout: layout)
            Text(title(for: currency))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func currencyBadge(for currency: PetCurrency, layout: ExchangeSheetLayout) -> some View {
        VStack(spacing: 6) {
            switch currency {
            case .meowCoin:
                Image(systemName: "pawprint.circle.fill")
                    .font(.system(size: layout.iconSize))
                    .foregroundColor(.yellow)
            case .fishCoin:
                Image(systemName: "fish.circle.fill")
                    .font(.system(size: layout.iconSize))
                    .foregroundColor(.orange)
            case .boneCoin:
                ZStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: layout.iconSize))
                        .foregroundColor(Color(hex: "CD7F32"))
                    Text("🦴")
                        .font(.system(size: layout.emojiSize))
                }
            }
        }
    }

    private func balanceCard(title: String, amount: Int, layout: ExchangeSheetLayout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(amount)")
                .font(layout.balanceAmountFont)
                .fontWeight(.semibold)
                .foregroundStyle(themeManager.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ExchangeSheetLayout {
    let containerWidth: CGFloat

    var horizontalPadding: CGFloat {
        if containerWidth < 360 { return 16 }
        if containerWidth < 520 { return 20 }
        return 24
    }

    var sectionSpacing: CGFloat {
        containerWidth < 420 ? 18 : 24
    }

    var directionButtonMinimumWidth: CGFloat {
        if containerWidth < 420 { return 128 }
        if containerWidth < 560 { return 140 }
        return 150
    }

    var iconSize: CGFloat {
        containerWidth < 420 ? 32 : 36
    }

    var emojiSize: CGFloat {
        containerWidth < 420 ? 18 : 20
    }

    var balanceAmountFont: Font {
        containerWidth < 420 ? .headline : .title3
    }
}
