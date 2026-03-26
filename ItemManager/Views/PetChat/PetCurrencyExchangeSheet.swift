import SwiftUI

struct PetCurrencyExchangeSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var petDataManager = PetDataManager.shared

    @State private var direction: PetCurrencyExchangeDirection
    @State private var exchangeAmount: Double = 1000
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
                    Text("汇率 1:1")
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
                        inputAmountText = "\(Int(exchangeAmount))"
                        showAmountInput = true
                    } label: {
                        Text("兑换数量: \(Int(exchangeAmount))")
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Slider(value: $exchangeAmount, in: 1000...100000, step: 1000)
                        .tint(themeManager.accentTextColor)

                    HStack {
                        Text("1000")
                        Spacer()
                        Text("100000")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                        exchangeAmount = Double(value)
                    }
                }
            }
            .alert("兑换失败", isPresented: $showingErrorAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var sourceBalance: Int {
        amount(for: direction.sourceCurrency)
    }

    private var targetBalance: Int {
        amount(for: direction.targetCurrency)
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
        let amount = Int(exchangeAmount)
        guard amount > 0 else { return }

        var status = petDataManager.status
        switch direction {
        case .fishToBone:
            guard status.fishCoin >= amount else {
                presentError("鱼币不足")
                return
            }
            status.fishCoin -= amount
            status.boneCoin += amount
            resultMessage = "兑换成功：\(amount) 鱼币 → \(amount) 骨头币"
        case .boneToFish:
            guard status.boneCoin >= amount else {
                presentError("骨头币不足")
                return
            }
            status.boneCoin -= amount
            status.fishCoin += amount
            resultMessage = "兑换成功：\(amount) 骨头币 → \(amount) 鱼币"
        }

        PetDataManager.shared.saveStatus(status)
        NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
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
