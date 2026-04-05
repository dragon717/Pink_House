import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    private func guideTarget(for option: PetWidgetOption) -> GuideTargetKey? {
        let guideManager = AppFirstLaunchGuideManager.shared
        guard guideManager.isShowingFeatureExperienceGuide,
              guideManager.currentFeatureExperienceFeature == .aiAnalysis,
              option.command == "weather_guidance" else {
            return nil
        }
        return .petChatGuideOptionButton
    }

    @ViewBuilder
    private func optionIconView(_ icon: String) -> some View {
        if UIImage(named: icon) != nil {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: icon)
                .font(.caption)
        }
    }

    private var preferredColumnCount: Int {
        if UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular {
            return 4
        }
        return 3
    }

    private var resolvedColumnCount: Int {
        max(1, min(preferredColumnCount, widget.options.count))
    }

    private var optionFill: Color {
        themeManager.petChatSkinTheme.resolvedQuickOptionFill(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var optionStroke: Color {
        themeManager.petChatSkinTheme.resolvedQuickOptionStroke(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var optionText: Color {
        themeManager.petChatSkinTheme.resolvedQuickOptionTextColor(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var optionRows: [[PetWidgetOption]] {
        return stride(from: 0, to: widget.options.count, by: resolvedColumnCount).map { start in
            Array(widget.options[start..<min(start + resolvedColumnCount, widget.options.count)])
        }
    }

    private var usesStackedOptionLayout: Bool {
        resolvedColumnCount >= 3
    }

    @ViewBuilder
    private func optionButton(_ option: PetWidgetOption) -> some View {
        Button {
            if guideTarget(for: option) != nil {
                NotificationCenter.default.post(name: .petChatGuideOptionTapped, object: nil)
            }
            onAction(option)
        } label: {
            Group {
                if usesStackedOptionLayout {
                    VStack(spacing: 6) {
                        if let icon = option.icon, !icon.isEmpty {
                            optionIconView(icon)
                                .frame(height: 16)
                        }
                        Text(option.title)
                            .font(.caption)
                            .lineLimit(3)
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        if let icon = option.icon, !icon.isEmpty {
                            optionIconView(icon)
                        }
                        Text(option.title)
                            .font(.caption)
                            .lineLimit(3)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            .foregroundStyle(optionText)
            .background(optionFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(optionStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .captureGuideTarget(guideTarget(for: option))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = widget.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            }

            VStack(spacing: 8) {
                ForEach(Array(optionRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { option in
                            optionButton(option)
                        }
                        if row.count < resolvedColumnCount {
                            ForEach(0..<(resolvedColumnCount - row.count), id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct PetWeatherWidget: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    let widget: PetWidgetData

    var body: some View {
        let palette = MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
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
                                .multilineTextAlignment(.leading)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.top, 2)
                }
            }
            .buttonStyle(.plain)

            if isExpanded && !widget.metrics.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
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
                        .padding(.vertical, 8)
                        .background(palette.quickOptionFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                        onAction(actionCommandOption(for: currency))
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(displayCurrencies, id: \.self) { currency in
                        CurrencyView(type: currency, amount: amount(for: currency)) {
                            onAction(actionCommandOption(for: currency))
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

    private func actionCommandOption(for currency: PetCurrency) -> PetWidgetOption {
        switch currency {
        case .meowCoin:
            return PetWidgetOption(title: "喵币充值", command: "pet_currency_action_meow")
        case .fishCoin:
            return PetWidgetOption(title: "鱼币兑换", command: "pet_currency_action_fish")
        case .boneCoin:
            return PetWidgetOption(title: "骨头币兑换", command: "pet_currency_action_bone")
        }
    }
}

private struct PetInventoryPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @ObservedObject private var petDataManager = PetDataManager.shared
    @State private var isDropTargeted = false

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
                    title: "我的背包空空的",
                    subtitle: "带我去商店补一点猫粮、罐头或者玩具吧。"
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 14)], spacing: 14) {
                        ForEach(widget.options) { option in
                            if let item = item(for: option.command) {
                                Button {
                                    onAction(option)
                                } label: {
                                    InventoryItemView(item: item, count: petDataManager.status.inventory[item.id] ?? 0)
                                        .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .onDrag {
                                    PetEmbeddedPanelDragDrop.itemProvider(for: option.command)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var inventoryDropZone: some View {
        HStack(spacing: 6) {
            Image(systemName: "pawprint.circle.fill")
            Text("拖到这里就能直接喂我")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(isDropTargeted ? Color.blue.opacity(0.16) : Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: PetEmbeddedPanelDragDrop.supportedTypeIdentifiers, isTargeted: $isDropTargeted) { providers in
            PetEmbeddedPanelDragDrop.handleDrop(from: providers) { payload in
                onAction(PetWidgetOption(title: "拖拽使用", command: payload, icon: "pawprint.circle.fill"))
            }
        }
    }

    private var currencyRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {
                    onAction(currencyActionOption(for: .meowCoin))
                }
                CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {
                    onAction(currencyActionOption(for: .fishCoin))
                }
                CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {
                    onAction(currencyActionOption(for: .boneCoin))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {
                        onAction(currencyActionOption(for: .meowCoin))
                    }
                    CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {
                        onAction(currencyActionOption(for: .fishCoin))
                    }
                    CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {
                        onAction(currencyActionOption(for: .boneCoin))
                    }
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

    private func currencyActionOption(for currency: PetCurrency) -> PetWidgetOption {
        switch currency {
        case .meowCoin:
            return PetWidgetOption(title: "喵币充值", command: "pet_currency_action_meow")
        case .fishCoin:
            return PetWidgetOption(title: "鱼币兑换", command: "pet_currency_action_fish")
        case .boneCoin:
            return PetWidgetOption(title: "骨头币兑换", command: "pet_currency_action_bone")
        }
    }
}

private struct PetShopPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @ObservedObject private var petDataManager = PetDataManager.shared
    @State private var isDropTargeted = false

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
                    title: "今天的小卖部空空的",
                    subtitle: "等会儿再陪我来看看有没有新道具。"
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 14)], spacing: 14) {
                        ForEach(widget.options) { option in
                            if let item = item(for: option.command) {
                                ShopItemView(
                                    item: item,
                                    displayPrice: VIPManager.shared.petShopPrice(for: item.price),
                                    originalPrice: VIPManager.shared.isVIP ? item.price : nil,
                                    discountBadge: VIPManager.shared.isVIP ? VIPManager.petShopDiscountText : nil
                                ) {
                                    onAction(option)
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                                .onDrag {
                                    PetEmbeddedPanelDragDrop.itemProvider(for: option.command)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var shopDropZone: some View {
        HStack(spacing: 6) {
            Image(systemName: "cart.circle.fill")
            Text("拖到这里就能买来马上喂我")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(isDropTargeted ? Color.orange.opacity(0.16) : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: PetEmbeddedPanelDragDrop.supportedTypeIdentifiers, isTargeted: $isDropTargeted) { providers in
            PetEmbeddedPanelDragDrop.handleDrop(from: providers) { payload in
                let itemId = payload
                    .replacingOccurrences(of: "buy_item:", with: "")
                    .replacingOccurrences(of: "shop:", with: "")
                guard !itemId.isEmpty else { return }
                onAction(PetWidgetOption(title: "拖拽投喂", command: "drag_shop_item:\(itemId)", icon: "cart.circle.fill"))
            }
        }
    }

    private var currencyRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {
                    onAction(currencyActionOption(for: .meowCoin))
                }
                CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {
                    onAction(currencyActionOption(for: .fishCoin))
                }
                CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {
                    onAction(currencyActionOption(for: .boneCoin))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CurrencyView(type: .meowCoin, amount: petDataManager.status.meowCoin) {
                        onAction(currencyActionOption(for: .meowCoin))
                    }
                    CurrencyView(type: .fishCoin, amount: petDataManager.status.fishCoin) {
                        onAction(currencyActionOption(for: .fishCoin))
                    }
                    CurrencyView(type: .boneCoin, amount: petDataManager.status.boneCoin) {
                        onAction(currencyActionOption(for: .boneCoin))
                    }
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

    private func currencyActionOption(for currency: PetCurrency) -> PetWidgetOption {
        switch currency {
        case .meowCoin:
            return PetWidgetOption(title: "喵币充值", command: "pet_currency_action_meow")
        case .fishCoin:
            return PetWidgetOption(title: "鱼币兑换", command: "pet_currency_action_fish")
        case .boneCoin:
            return PetWidgetOption(title: "骨头币兑换", command: "pet_currency_action_bone")
        }
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

    private var selectedCurrency: CurrencyType {
        guard let raw = widget.metrics.first(where: { $0.name == PetMoneyCounterMetricKey.currency })?.value,
              let parsed = CurrencyType(rawValue: raw) else {
            return .rmb
        }
        switch parsed {
        case .rmb, .jpy, .usd:
            return parsed
        case .gold, .silver:
            return .rmb
        }
    }

    private var currencySymbol: String {
        switch selectedCurrency {
        case .rmb: return "¥"
        case .jpy: return "¥"
        case .usd: return "$"
        case .gold: return "Gold "
        case .silver: return "Silver "
        }
    }

    private var totalAmount: Int {
        let rawValue = widget.metrics.first(where: { $0.name == PetMoneyCounterMetricKey.amount })?.value
            ?? widget.metrics.first?.value
            ?? ""
        let digits = rawValue.filter { $0.isWholeNumber }
        return Int(digits) ?? 0
    }

    private var denominationValue: Int {
        let amount = max(1, totalAmount)
        let values: [Int]
        switch selectedCurrency {
        case .rmb:
            values = [100, 50, 20, 10, 5, 1]
        case .jpy:
            values = [10000, 5000, 1000]
        case .usd:
            values = [100, 50, 20, 10, 5, 2, 1]
        case .gold, .silver:
            values = [100]
        }
        return values.first(where: { amount >= $0 }) ?? (values.last ?? 1)
    }

    private var denominationColor: Color {
        switch selectedCurrency {
        case .rmb:
            switch denominationValue {
            case 100: return Color(red: 0.9, green: 0.3, blue: 0.3)
            case 50: return Color(red: 0.3, green: 0.7, blue: 0.5)
            case 20: return Color(red: 0.6, green: 0.4, blue: 0.2)
            case 10: return Color(red: 0.3, green: 0.5, blue: 0.8)
            case 5: return Color(red: 0.6, green: 0.3, blue: 0.7)
            case 1: return Color(red: 0.7, green: 0.7, blue: 0.3)
            default: return .gray
            }
        case .jpy:
            switch denominationValue {
            case 10000: return Color(red: 0.5, green: 0.3, blue: 0.2)
            case 5000: return Color(red: 0.5, green: 0.2, blue: 0.6)
            case 1000: return Color(red: 0.2, green: 0.4, blue: 0.7)
            default: return .gray
            }
        case .usd:
            switch denominationValue {
            case 100: return Color(red: 0.1, green: 0.4, blue: 0.2)
            case 50: return Color(red: 0.2, green: 0.3, blue: 0.5)
            case 20: return Color(red: 0.4, green: 0.2, blue: 0.2)
            case 10: return Color(red: 0.2, green: 0.3, blue: 0.2)
            case 5: return Color(red: 0.3, green: 0.2, blue: 0.4)
            case 2: return Color(red: 0.3, green: 0.4, blue: 0.6)
            case 1: return Color(red: 0.2, green: 0.5, blue: 0.3)
            default: return .gray
            }
        case .gold, .silver:
            return .gray
        }
    }

    private var denomination: Denomination {
        Denomination(value: denominationValue, color: denominationColor, name: "\(denominationValue)")
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
                    Text("\(currencySymbol)\(remainingBills * denomination.value)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                Spacer()
                Text("已数：\(currencySymbol)\(extractedBills * denomination.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
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
        .background(Color.clear)
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
                BanknoteView(denomination: denomination, currency: selectedCurrency, showShadow: true)
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
            BanknoteView(denomination: denomination, currency: selectedCurrency, showShadow: true)
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
                BanknoteView(denomination: denomination, currency: selectedCurrency, showShadow: false)
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

private enum PetEmbeddedPanelDragDrop {
    static let supportedTypeIdentifiers = [UTType.plainText.identifier]

    static func itemProvider(for command: String) -> NSItemProvider {
        NSItemProvider(object: command as NSString)
    }

    static func handleDrop(from providers: [NSItemProvider], perform: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String, !payload.isEmpty else { return }
            DispatchQueue.main.async {
                perform(payload)
            }
        }

        return true
    }
}

private struct PetDivinationPanelWidget: View {
    let widget: PetWidgetData
    let onAction: (PetWidgetOption) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var currentFortune: Fortune?
    @State private var videoState: VideoState = .initial
    @State private var showFortuneText = false

    private enum VideoState: Equatable {
        case initial
        case playing
        case finished
    }

    private let fortunes: [Fortune] = [
        Fortune(level: .supreme, text: "上上签", description: "财运亨通，福星高照", detail: "今日财运极佳，适合投资理财，可能会有意外之财降临。"),
        Fortune(level: .supreme, text: "上上签", description: "财源广进，日进斗金", detail: "财神眷顾，正财偏财皆旺，把握机会必有所获。"),
        Fortune(level: .supreme, text: "上上签", description: "富贵吉祥，万事顺遂", detail: "财星高照，事业财运双丰收，好运连连。"),
        Fortune(level: .good, text: "上签", description: "财运平稳，小有收获", detail: "今日财运不错，适合稳健理财，会有小惊喜。"),
        Fortune(level: .good, text: "上签", description: "积少成多，稳步前行", detail: "财运渐入佳境，坚持储蓄必有回报。"),
        Fortune(level: .good, text: "上签", description: "贵人相助，财运可期", detail: "有望得到贵人提携，财运有所提升。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetPanelHeader(title: widget.title, subtitle: widget.subtitle)

            GeometryReader { geometry in
                let containerSize = calculateContainerSize(for: geometry.size)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    ZStack {
                        if videoState == .initial {
                            Image("divination_first_frame")
                                .resizable()
                                .scaledToFill()
                                .frame(width: containerSize, height: containerSize)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .transition(.opacity)
                        }

                        if videoState == .playing {
                            DivinationVideoPlayer(
                                videoName: "请签",
                                onFinished: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        videoState = .finished
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                            showFortuneText = true
                                        }
                                    }
                                }
                            )
                            .frame(width: containerSize, height: containerSize)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .transition(.opacity)
                        }

                        if videoState == .finished {
                            Image("divination_last_frame")
                                .resizable()
                                .scaledToFill()
                                .frame(width: containerSize, height: containerSize)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .transition(.opacity)

                            RoundedRectangle(cornerRadius: 18)
                                .fill(.ultraThinMaterial.opacity(0.3))
                                .frame(width: containerSize, height: containerSize)

                            if showFortuneText {
                                VerticalFortuneText(
                                    fortune: currentFortune ?? fortunes[0],
                                    containerSize: containerSize
                                )
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }

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
                                lineWidth: 3
                            )
                            .frame(width: containerSize, height: containerSize)

                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(red: 0.9, green: 0.75, blue: 0.4).opacity(0.3), lineWidth: 8)
                            .frame(width: containerSize + 6, height: containerSize + 6)
                            .blur(radius: 4)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                    .offset(y: -8)

                    Spacer(minLength: 0)

                    ZStack {
                        if videoState == .finished && showFortuneText, let currentFortune {
                            interpretationView(for: currentFortune)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .frame(height: interpretationContainerHeight)

                    ZStack {
                        if videoState == .initial {
                            divinationButton(title: "请签求好运", icon: "wand.and.stars") {
                                startDivination()
                            }
                            .transition(.opacity)
                        } else if videoState == .finished && showFortuneText {
                            divinationButton(title: "再请一签", icon: "arrow.counterclockwise") {
                                replayDivination()
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(height: 80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 440)
            .animation(.easeInOut(duration: 0.25), value: videoState)
            .animation(.easeInOut(duration: 0.25), value: showFortuneText)

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

        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)

        showFortuneText = false
        withAnimation(.easeInOut(duration: 0.3)) {
            videoState = .playing
        }
    }

    private func replayDivination() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showFortuneText = false
            videoState = .playing
        }
        currentFortune = fortunes.randomElement()
    }

    private func calculateContainerSize(for size: CGSize) -> CGFloat {
        let widthBased = size.width * 0.78
        return min(max(widthBased, 220), 280)
    }

    private var interpretationContainerHeight: CGFloat {
        horizontalSizeClass == .regular ? 116 : 100
    }

    private var interpretationContentWidth: CGFloat {
        horizontalSizeClass == .regular ? 420 : 360
    }

    @ViewBuilder
    private func interpretationView(for fortune: Fortune) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            FortuneInterpretationView(fortune: fortune)
                .frame(width: interpretationContentWidth)
                .padding(.horizontal, 2)
        }
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
