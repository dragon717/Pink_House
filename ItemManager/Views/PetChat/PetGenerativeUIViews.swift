import SwiftUI

struct PetGenerativeWidgetHost: View {
    let widgets: [PetWidgetData]
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(widgets) { widget in
                PetWidgetRegistry.makeWidget(widget, onAction: onAction)
            }
        }
    }
}

enum PetWidgetRegistry {
    @ViewBuilder
    static func makeWidget(_ widget: PetWidgetData, onAction: @escaping (PetWidgetOption) -> Void) -> some View {
        switch widget.type {
        case .quickOptions:
            PetQuickOptionsWidget(widget: widget, onAction: onAction)
        case .weatherCard:
            PetWeatherWidget(widget: widget)
        case .container:
            PetContainerWidget(widget: widget, onAction: onAction)
        case .insightCard:
            PetInsightCardWidget(widget: widget)
        case .statusPanel:
            PetStatusPanelWidget(widget: widget, onAction: onAction)
        case .currencyPanel:
            PetCurrencyPanelWidget(widget: widget, onAction: onAction)
        case .inventoryPanel:
            PetInventoryPanelWidget(widget: widget, onAction: onAction)
        case .shopPanel:
            PetShopPanelWidget(widget: widget, onAction: onAction)
        case .moneyCounter:
            PetMoneyCounterWidget(widget: widget, onAction: onAction)
        case .divinationPanel:
            PetDivinationPanelWidget(widget: widget, onAction: onAction)
        case .unknown:
            PetInsightCardWidget(widget: widget)
        }
    }
}

private struct PetQuickOptionsWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        let skin = themeManager.petChatSkinTheme
        let optionFill = skin.resolvedQuickOptionFill(themeManager: themeManager, colorScheme: colorScheme)
        let optionStroke = skin.resolvedQuickOptionStroke(themeManager: themeManager, colorScheme: colorScheme)
        let optionText = skin.resolvedQuickOptionTextColor(themeManager: themeManager, colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            }

            ForEach(widget.options) { option in
                Button {
                    onAction(option)
                } label: {
                    HStack(spacing: 8) {
                        if let icon = option.icon, !icon.isEmpty {
                            Image(systemName: icon)
                                .font(.caption)
                        }
                        Text(option.title)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .foregroundStyle(optionText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(optionFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(optionStroke, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

private struct PetWeatherWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }

            if !widget.metrics.isEmpty {
                HStack(spacing: 8) {
                    ForEach(widget.metrics) { metric in
                        VStack(spacing: 2) {
                            Text(metric.name)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryText)
                            Text(metric.value)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(palette.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(palette.quickOptionFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(10)
        .background(palette.cardBackground.opacity(colorScheme == .dark ? 0.5 : 0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.quickOptionStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PetInsightCardWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground.opacity(colorScheme == .dark ? 0.45 : 0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.quickOptionStroke.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PetContainerWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }
            if let subtitle = widget.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            if !widget.children.isEmpty {
                PetGenerativeWidgetHost(widgets: widget.children, onAction: onAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.quickOptionStroke.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PetStatusPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @ObservedObject private var petDataManager = PetDataManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)
            statusSwitchRow

            ForEach(widget.metrics) { metric in
                if metric.name.contains("亲密") {
                    PetIntimacyStatusRow(value: petDataManager.status.intimacy)
                } else {
                    StatusView(
                        icon: iconName(for: metric.name),
                        value: currentValue(for: metric.name),
                        color: color(for: metric.name)
                    )
                }
            }

            if !widget.options.isEmpty {
                PetQuickOptionsWidget(
                    widget: PetWidgetData(type: .quickOptions, options: widget.options),
                    onAction: onAction
                )
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private var statusSwitchRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusTabOptions) { option in
                    Button(option.title) {
                        onAction(option)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.pink)
                }
            }
        }
    }

    private var statusTabOptions: [PetWidgetOption] {
        [
            PetWidgetOption(title: "全部", command: "pet_status_all"),
            PetWidgetOption(title: "饱食", command: "pet_status_hunger"),
            PetWidgetOption(title: "饮水", command: "pet_status_hydration"),
            PetWidgetOption(title: "清洁", command: "pet_status_hygiene"),
            PetWidgetOption(title: "心情", command: "pet_status_mood"),
            PetWidgetOption(title: "亲密", command: "pet_status_intimacy")
        ]
    }

    private func currentValue(for name: String) -> Double {
        if name.contains("饱食") { return petDataManager.status.hunger }
        if name.contains("饮水") { return petDataManager.status.energy }
        if name.contains("清洁") { return petDataManager.status.hygiene }
        if name.contains("心情") { return petDataManager.status.mood }
        return 0
    }

    private func color(for name: String) -> Color {
        if name.contains("饱食") { return .orange }
        if name.contains("饮水") { return .blue }
        if name.contains("清洁") { return .green }
        return .pink
    }

    private func iconName(for name: String) -> String {
        if name.contains("饱食") { return "fork.knife" }
        if name.contains("饮水") { return "drop.fill" }
        if name.contains("清洁") { return "sparkles" }
        return "face.smiling.fill"
    }
}

private struct PetCurrencyPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @ObservedObject private var petDataManager = PetDataManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)
            currencySwitchRow
            currencyContent
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private var currencySwitchRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currencyTabOptions) { option in
                    Button(option.title) {
                        onAction(option)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(selectedCommand == option.command ? .pink : .gray)
                }
            }
        }
    }

    private var currencyContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(displayCurrencies, id: \.self) { currency in
                    CurrencyView(type: currency, amount: amount(for: currency)) {
                        onAction(commandOption(for: currency))
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(displayCurrencies, id: \.self) { currency in
                        CurrencyView(type: currency, amount: amount(for: currency)) {
                            onAction(commandOption(for: currency))
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var currencyTabOptions: [PetWidgetOption] {
        [
            PetWidgetOption(title: "全部", command: "pet_currency_all"),
            PetWidgetOption(title: "喵币", command: "pet_currency_meow"),
            PetWidgetOption(title: "鱼币", command: "pet_currency_fish"),
            PetWidgetOption(title: "骨头币", command: "pet_currency_bone")
        ]
    }

    private var selectedCommand: String {
        let names = widget.metrics.map(\.name)
        if names.count > 1 { return "pet_currency_all" }
        switch names.first {
        case "喵币": return "pet_currency_meow"
        case "鱼币": return "pet_currency_fish"
        case "骨头币": return "pet_currency_bone"
        default: return "pet_currency_all"
        }
    }

    private var displayCurrencies: [PetCurrency] {
        switch selectedCommand {
        case "pet_currency_meow":
            return [.meowCoin]
        case "pet_currency_fish":
            return [.fishCoin]
        case "pet_currency_bone":
            return [.boneCoin]
        default:
            return [.meowCoin, .fishCoin, .boneCoin]
        }
    }

    private func amount(for currency: PetCurrency) -> Int {
        switch currency {
        case .meowCoin: return petDataManager.status.meowCoin
        case .fishCoin: return petDataManager.status.fishCoin
        case .boneCoin: return petDataManager.status.boneCoin
        }
    }

    private func commandOption(for currency: PetCurrency) -> PetWidgetOption {
        switch currency {
        case .meowCoin:
            return PetWidgetOption(title: "喵币", command: "pet_currency_meow")
        case .fishCoin:
            return PetWidgetOption(title: "鱼币", command: "pet_currency_fish")
        case .boneCoin:
            return PetWidgetOption(title: "骨头币", command: "pet_currency_bone")
        }
    }
}

private struct PetInventoryPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @ObservedObject private var petDataManager = PetDataManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)
            PetSegmentTabs(primary: "背包", secondary: "商店", isPrimarySelected: true) {
                onAction(PetWidgetOption(title: "背包", command: "pet_inventory_panel"))
            } secondaryAction: {
                onAction(PetWidgetOption(title: "商店", command: "pet_shop_panel"))
            }
            inventoryGrid
            inventoryDropZone
            currencyRow
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private var inventoryGrid: some View {
        Group {
            if widget.options.isEmpty {
                PetPanelEmptyState(
                    systemIcon: "shippingbox",
                    title: "背包空空的",
                    subtitle: "去商店补一点猫粮、罐头或者玩具吧。"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(widget.options) { option in
                            if let item = item(for: option.command) {
                                Button {
                                    onAction(option)
                                } label: {
                                    InventoryItemView(item: item, count: petDataManager.status.inventory[item.id] ?? 0)
                                        .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .draggable(option.command)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var inventoryDropZone: some View {
        HStack(spacing: 6) {
            Image(systemName: "pawprint.circle.fill")
            Text("拖拽到这里就地投喂")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            onAction(PetWidgetOption(title: "拖拽使用", command: payload, icon: "pawprint.circle.fill"))
            return true
        }
    }

    private var currencyRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {}
                CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {}
                CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {}
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {}
                    CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {}
                    CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {}
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func item(for command: String) -> PetItemDefinition? {
        let itemId = command
            .replacingOccurrences(of: "use_item:", with: "")
            .replacingOccurrences(of: "inventory:", with: "")
        return PetConfigManager.shared.getItem(byId: itemId)
    }
}

private struct PetShopPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @ObservedObject private var petDataManager = PetDataManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)
            PetSegmentTabs(primary: "背包", secondary: "商店", isPrimarySelected: false) {
                onAction(PetWidgetOption(title: "背包", command: "pet_inventory_panel"))
            } secondaryAction: {
                onAction(PetWidgetOption(title: "商店", command: "pet_shop_panel"))
            }
            shopGrid
            shopDropZone
            currencyRow
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private var shopGrid: some View {
        Group {
            if widget.options.isEmpty {
                PetPanelEmptyState(
                    systemIcon: "cart",
                    title: "商店暂时空着",
                    subtitle: "等会儿再来看看有没有新道具。"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(widget.options) { option in
                            if let item = item(for: option.command) {
                                ShopItemView(item: item) {
                                    onAction(option)
                                }
                                .padding(.vertical, 2)
                                .draggable(option.command)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var shopDropZone: some View {
        HStack(spacing: 6) {
            Image(systemName: "cart.circle.fill")
            Text("拖拽到这里快速购买")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            onAction(PetWidgetOption(title: "拖拽购买", command: payload, icon: "cart.circle.fill"))
            return true
        }
    }

    private var currencyRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {}
                CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {}
                CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {}
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {}
                    CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {}
                    CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {}
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func item(for command: String) -> PetItemDefinition? {
        let itemId = command
            .replacingOccurrences(of: "buy_item:", with: "")
            .replacingOccurrences(of: "shop:", with: "")
        return PetConfigManager.shared.getItem(byId: itemId)
    }
}

private struct PetMoneyCounterWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @State private var remainingBills: Int = 0
    @State private var extractedBills: Int = 0
    @State private var stackScale: CGFloat = 1
    @State private var topBillOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var flyingBills: [CompactFlyingBill] = []
    @State private var pileOffsets: [CGSize] = []
    @State private var pileRotations: [Double] = []

    struct CompactFlyingBill: Identifiable {
        let id = UUID()
        var offset: CGSize
        var rotation: Double
        var opacity: Double = 1
    }

    private var totalAmount: Int {
        let rawValue = widget.metrics.first?.value ?? ""
        let digits = rawValue.filter { $0.isWholeNumber }
        return Int(digits) ?? 0
    }

    private var denomination: Denomination {
        let amount = max(1, totalAmount)
        if amount >= 10_000 {
            return Denomination(value: 1000, color: .red, name: "1000")
        }
        if amount >= 1_000 {
            return Denomination(value: 100, color: .red, name: "100")
        }
        if amount >= 100 {
            return Denomination(value: 20, color: .green, name: "20")
        }
        return Denomination(value: 10, color: .blue, name: "10")
    }

    private var totalBills: Int {
        max(1, totalAmount / max(1, denomination.value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("剩余金额")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("¥\(remainingBills * denomination.value)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                Spacer()
                Text("已数：¥\(extractedBills * denomination.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.78), Color.black.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if remainingBills == 0 {
                    Text("数钱数到手抽筋")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    GeometryReader { proxy in
                        moneyPile
                            .frame(
                                width: proxy.size.width * 0.5,
                                height: proxy.size.height * 0.5,
                                alignment: .center
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .scaleEffect(stackScale)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: stackScale)

            Text("拖走最上面那张，或者点一下数钞")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !widget.options.isEmpty {
                PetQuickOptionsWidget(
                    widget: PetWidgetData(type: .quickOptions, options: widget.options),
                    onAction: onAction
                )
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .onAppear {
            if remainingBills == 0 && extractedBills == 0 {
                remainingBills = totalBills
            }
            if pileOffsets.isEmpty {
                pileOffsets = (0..<12).map { _ in
                    CGSize(width: Double.random(in: -6...6), height: Double.random(in: -5...5))
                }
                pileRotations = (0..<12).map { _ in
                    Double.random(in: -4...4)
                }
            }
        }
    }

    private var moneyPile: some View {
        let messinessScale = 0.45 + min(2.0, Double(remainingBills) / 50.0)
        return ZStack {
            ForEach(1..<min(6, remainingBills), id: \.self) { index in
                let absoluteIndex = max(0, remainingBills - index)
                let randomOffset = pileOffset(for: absoluteIndex)
                let randomRotation = pileRotation(for: absoluteIndex)
                BanknoteView(denomination: denomination, currency: .rmb, showShadow: true)
                    .scaleEffect(1.0)
                    .scaleEffect(1 - CGFloat(index) * 0.03)
                    .rotationEffect(.degrees(randomRotation * messinessScale))
                    .offset(
                        x: randomOffset.width * messinessScale * 0.6,
                        y: CGFloat(index) * 1.5 + randomOffset.height * messinessScale * 0.6
                    )
                    .opacity(1 - Double(index) * 0.06)
                    .zIndex(Double(-index))
            }

            let topIndex = max(0, remainingBills)
            let topRandomOffset = pileOffset(for: topIndex)
            let topRandomRotation = pileRotation(for: topIndex)
            BanknoteView(denomination: denomination, currency: .rmb, showShadow: true)
                .scaleEffect(1.0)
                .rotationEffect(.degrees(topRandomRotation * messinessScale + (isDragging ? Double(topBillOffset.width / 10) : 0)))
                .offset(
                    x: topRandomOffset.width * messinessScale * 0.6 + topBillOffset.width,
                    y: topRandomOffset.height * messinessScale * 0.6 + topBillOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            topBillOffset = value.translation
                        }
                        .onEnded { value in
                            isDragging = false
                            let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                            if distance > 80 {
                                extractBill(direction: value.translation)
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                                    topBillOffset = .zero
                                }
                            }
                        }
                )
                .onTapGesture {
                    extractBill(direction: CGSize(width: 0, height: -320))
                }
                .zIndex(10)

            ForEach(flyingBills) { bill in
                BanknoteView(denomination: denomination, currency: .rmb, showShadow: false)
                    .scaleEffect(1.0)
                    .offset(bill.offset)
                    .rotationEffect(.degrees(bill.rotation))
                    .opacity(bill.opacity)
                    .zIndex(20)
            }
        }
    }

    private func extractBill(direction: CGSize) {
        guard remainingBills > 0 else { return }
        remainingBills -= 1
        extractedBills += 1
        topBillOffset = .zero
        stackScale = 0.98
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            stackScale = 1
        }

        let magnitude = max(1, sqrt(pow(direction.width, 2) + pow(direction.height, 2)))
        let endOffset = CGSize(
            width: direction.width / magnitude * 260,
            height: direction.height / magnitude * 260
        )

        let newBill = CompactFlyingBill(offset: .zero, rotation: 0, opacity: 1)
        flyingBills.append(newBill)
        let billID = newBill.id
        let index = flyingBills.indices.last!
        withAnimation(.easeOut(duration: 0.45)) {
            flyingBills[index].offset = endOffset
            flyingBills[index].rotation = Double.random(in: -35...35)
            flyingBills[index].opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            flyingBills.removeAll { $0.id == billID }
        }
    }

    private func pileOffset(for index: Int) -> CGSize {
        guard !pileOffsets.isEmpty else { return .zero }
        return pileOffsets[index % pileOffsets.count]
    }

    private func pileRotation(for index: Int) -> Double {
        guard !pileRotations.isEmpty else { return 0 }
        return pileRotations[index % pileRotations.count]
    }
}

private struct PetDivinationPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @State private var currentFortune: Fortune?
    @State private var phase: DivinationPhase = .idle
    @State private var revealFortune = false

    private enum DivinationPhase: Equatable {
        case idle
        case shaking
        case finished
    }

    private let fortunes: [Fortune] = [
        Fortune(level: .supreme, text: "上上签", description: "财运亨通，福星高照", detail: "今日很适合做让你开心的小决定，也容易遇到顺手的好消息。"),
        Fortune(level: .good, text: "上签", description: "稳稳前行，小有惊喜", detail: "今天适合慢慢推进手头的事，越是耐心越容易收获好结果。"),
        Fortune(level: .good, text: "上签", description: "贵人照拂，心想渐成", detail: "保持你现在的节奏，会有人或机会在关键处推你一把。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)

            RoundedRectangle(cornerRadius: 18)
                .fill(Color.clear)
                .frame(height: phase == .finished && revealFortune ? 320 : 250)
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.32, green: 0.12, blue: 0.12), Color(red: 0.55, green: 0.22, blue: 0.22)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.9, green: 0.75, blue: 0.4),
                                        Color(red: 0.7, green: 0.5, blue: 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )

                        VStack(spacing: 12) {
                            if phase == .idle {
                                fortuneFrame(name: "divination_first_frame")
                                divinationButton(title: "开始求签", icon: "wand.and.stars") {
                                    startDivination()
                                }
                            } else if phase == .shaking {
                                fortuneFrame(name: "divination_first_frame")
                                    .rotationEffect(.degrees(revealFortune ? 4 : -4))
                                    .animation(.easeInOut(duration: 0.12).repeatCount(6, autoreverses: true), value: revealFortune)
                                Text("摇签中…")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.82))
                            } else if let currentFortune {
                                VStack(spacing: 10) {
                                    fortuneFrame(name: "divination_last_frame")
                                    if revealFortune {
                                        FortuneStickView(fortune: currentFortune)
                                            .scaleEffect(0.85)
                                        FortuneInterpretationView(fortune: currentFortune)
                                            .padding(.horizontal, -12)
                                    }
                                    divinationButton(title: "再求一签", icon: "arrow.counterclockwise") {
                                        startDivination()
                                    }
                                }
                            }
                        }
                        .padding(14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .animation(.easeInOut(duration: 0.25), value: phase)

            if !widget.options.isEmpty {
                PetQuickOptionsWidget(
                    widget: PetWidgetData(type: .quickOptions, options: widget.options),
                    onAction: onAction
                )
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    private func startDivination() {
        currentFortune = fortunes.randomElement()
        revealFortune = false
        phase = .shaking
        withAnimation(.easeInOut(duration: 0.12)) {
            revealFortune = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            phase = .finished
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                revealFortune = true
            }
        }
    }

    private func fortuneFrame(name: String) -> some View {
        Group {
            if UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 0.9, green: 0.75, blue: 0.4), lineWidth: 2)
                )
            }
        }
        .frame(height: phase == .finished ? 140 : 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func divinationButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct PetPanelEmptyState: View {
    let systemIcon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemIcon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct PetPanelHeader: View {
    let title: String?
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PetSegmentTabs: View {
    let primary: String
    let secondary: String
    let isPrimarySelected: Bool
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack {
            Button(action: primaryAction) {
                Text(primary)
                    .font(.headline)
                    .fontWeight(isPrimarySelected ? .bold : .regular)
                    .foregroundColor(isPrimarySelected ? .primary : .secondary)
            }
            Text("|")
                .foregroundColor(.secondary.opacity(0.3))
                .padding(.horizontal, 8)
            Button(action: secondaryAction) {
                Text(secondary)
                    .font(.headline)
                    .fontWeight(isPrimarySelected ? .regular : .bold)
                    .foregroundColor(isPrimarySelected ? .secondary : .primary)
            }
            Spacer()
        }
    }
}

private struct PetIntimacyStatusRow: View {
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundColor(.pink)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.pink.opacity(0.15))
                    Capsule()
                        .fill(Color.pink)
                        .frame(width: geometry.size.width * CGFloat(max(0, min(100, value)) / 100.0))
                }
            }
            .frame(height: 8)
            Text(heartText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var heartText: String {
        let filled = Int((max(0, min(100, value)) / 20).rounded(.down))
        let empty = max(0, 5 - filled)
        return String(repeating: "♥️", count: filled) + String(repeating: "♡", count: empty)
    }
}
