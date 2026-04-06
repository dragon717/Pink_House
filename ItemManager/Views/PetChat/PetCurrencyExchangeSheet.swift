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
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("货币兑换")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(exchangeRateDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                Picker("兑换方向", selection: $direction) {
                    ForEach(PetCurrencyExchangeDirection.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                HStack(spacing: 20) {
                    currencyBadge(for: direction.sourceCurrency)
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                    currencyBadge(for: direction.targetCurrency)
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("\(title(for: direction.sourceCurrency))余额：\(sourceBalance)")
                        Spacer()
                        Text("\(title(for: direction.targetCurrency))余额：\(targetBalance)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button {
                        inputAmountText = "\(exchangeAmountValue)"
                        showAmountInput = true
                    } label: {
                        Text("兑换数量: \(exchangeAmountValue)")
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        Text("当前最多可兑换 \(maxExchangeableSourceAmount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if sourceBalance > 0 {
                        Text("目标货币已接近上限，暂时无法继续兑换")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("当前没有可用于兑换的\(title(for: direction.sourceCurrency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if hasExchangeableBalance {
                        Text("预计到账 \(convertedTargetAmount(for: exchangeAmountValue) ?? 0) \(title(for: direction.targetCurrency))")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                .padding(.horizontal, 24)

                Button {
                    performExchange()
                } label: {
                    Text(direction.title)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(direction == .fishToBone ? Color.brown : Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .disabled(!hasExchangeableBalance)
                .opacity(hasExchangeableBalance ? 1 : 0.5)

                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        _ = PetDataManager.shared.updateCurrency(type: .fishCoin, delta: 1000)
                        _ = PetDataManager.shared.updateCurrency(type: .boneCoin, delta: 1000)
                        resultMessage = "🛠️ Debug：已增加 1000 鱼币和 1000 骨头币"
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("输入兑换数量", isPresented: $showAmountInput) {
                TextField("数量", text: $inputAmountText)
                    .keyboardType(.numberPad)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let value = Int(inputAmountText), value > 0 {
                        exchangeAmount = min(Double(value), maxExchangeAmount)
                        clampExchangeAmount()
                    }
                }
            }
            .alert("兑换失败", isPresented: $showingErrorAlert) {
                Button("知道了", role: .cancel) { }
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
            return "汇率 1:1"
        case .meowToFish:
            return "1 喵币 = 1000 鱼币"
        case .meowToBone:
            return "1 喵币 = 1000 骨头币"
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
        switch currency {
        case .meowCoin: return "喵币"
        case .fishCoin: return "鱼币"
        case .boneCoin: return "骨头币"
        }
    }

    private func performExchange() {
        let sourceAmount = min(exchangeAmountValue, maxExchangeableSourceAmount)
        guard sourceAmount > 0 else {
            presentError("当前数量无法兑换")
            return
        }

        guard let targetAmount = convertedTargetAmount(for: sourceAmount) else {
            presentError("兑换数量过大，请减少后重试")
            return
        }

        var status = petDataManager.status
        switch direction {
        case .fishToBone:
            guard status.fishCoin >= sourceAmount else {
                presentError("鱼币不足")
                return
            }
            let (newBoneCoin, overflow) = status.boneCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("骨头币数量过大，暂时无法继续兑换")
                return
            }
            status.fishCoin -= sourceAmount
            status.boneCoin = newBoneCoin
            resultMessage = "兑换成功：\(sourceAmount) 鱼币 → \(targetAmount) 骨头币"
        case .boneToFish:
            guard status.boneCoin >= sourceAmount else {
                presentError("骨头币不足")
                return
            }
            let (newFishCoin, overflow) = status.fishCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("鱼币数量过大，暂时无法继续兑换")
                return
            }
            status.boneCoin -= sourceAmount
            status.fishCoin = newFishCoin
            resultMessage = "兑换成功：\(sourceAmount) 骨头币 → \(targetAmount) 鱼币"
        case .meowToFish:
            let (newFishCoin, overflow) = status.fishCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("鱼币数量过大，暂时无法继续兑换")
                return
            }
            guard StoreManager.spendMeowCoins(sourceAmount, in: &status) else {
                presentError("喵币不足")
                return
            }
            status.fishCoin = newFishCoin
            resultMessage = "兑换成功：\(sourceAmount) 喵币 → \(targetAmount) 鱼币"
        case .meowToBone:
            let (newBoneCoin, overflow) = status.boneCoin.addingReportingOverflow(targetAmount)
            guard !overflow else {
                presentError("骨头币数量过大，暂时无法继续兑换")
                return
            }
            guard StoreManager.spendMeowCoins(sourceAmount, in: &status) else {
                presentError("喵币不足")
                return
            }
            status.boneCoin = newBoneCoin
            resultMessage = "兑换成功：\(sourceAmount) 喵币 → \(targetAmount) 骨头币"
        }

        PetDataManager.shared.saveStatus(status)
        NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
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
    private func currencyBadge(for currency: PetCurrency) -> some View {
        VStack(spacing: 6) {
            switch currency {
            case .meowCoin:
                Image(systemName: "pawprint.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.yellow)
            case .fishCoin:
                Image(systemName: "fish.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
            case .boneCoin:
                ZStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "CD7F32"))
                    Text("🦴")
                        .font(.system(size: 20))
                }
            }
            Text(title(for: currency))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
