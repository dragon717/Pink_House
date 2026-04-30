import Foundation
import Combine

final class ThemeSkinManager: ObservableObject, ThemeSkinProviding {
    static let shared = ThemeSkinManager()

    @Published private(set) var products: [ThemeSkinProduct] = [
        ThemeSkinProduct.skyConcert,
        ThemeSkinProduct.swanDream
    ]
    @Published private(set) var ownedThemeSkins: [OwnedThemeSkin] = []
    @Published private(set) var activeSelection: ActiveThemeSkinSelection = .inactive
    @Published private(set) var backgroundStickerSelections: [String: ThemeSkinBackgroundSelection] = [:]

    private let ownedKey = "theme_skin.owned"
    private let activeSelectionKey = "theme_skin.active_selection"
    private let backgroundStickerSelectionKey = "theme_skin.background_sticker_selection_v1"
    private let coreSurfaceMigrationKeyPrefix = "theme_skin.core_surface_defaults_migrated_v1"
    private let topNavigationMigrationKeyPrefix = "theme_skin.top_navigation_defaults_migrated_v1"

    private init() {
        reloadFromDisk(applyBackgroundHarmony: false)
    }

    var allOwnedThemeSkins: [OwnedThemeSkin] { ownedThemeSkins }
    var activeThemeId: String? { activeSelection.activeThemeId }
    var activeProduct: ThemeSkinProduct? { activeThemeId.flatMap { product(for: $0) } }
    var currentEnabledSlots: Set<ThemeSkinSlot> { activeSelection.enabledSlots }
    var currentMeowCoinBalance: Int { StoreManager.getCurrentBalance() }

    func reloadFromDisk(applyBackgroundHarmony: Bool = true) {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: ownedKey),
           let decoded = try? JSONDecoder().decode([OwnedThemeSkin].self, from: data) {
            ownedThemeSkins = decoded.sorted { $0.purchasedAt < $1.purchasedAt }
        } else {
            ownedThemeSkins = []
        }

        if let data = defaults.data(forKey: activeSelectionKey),
           let decoded = try? JSONDecoder().decode(ActiveThemeSkinSelection.self, from: data) {
            activeSelection = sanitize(selection: decoded)
        } else {
            activeSelection = .inactive
        }

        if let data = defaults.data(forKey: backgroundStickerSelectionKey),
           let decoded = try? JSONDecoder().decode([String: ThemeSkinBackgroundSelection].self, from: data) {
            backgroundStickerSelections = sanitize(backgroundSelections: decoded)
        } else {
            backgroundStickerSelections = [:]
        }

        migrateCoreSurfaceDefaultsIfNeeded(defaults: defaults)
        migrateTopNavigationDefaultsIfNeeded(defaults: defaults)

        if applyBackgroundHarmony {
            _ = ThemeManager.shared.enforceThemeSkinBackgroundHarmonyIfNeeded(activeThemeId: activeSelection.activeThemeId)
        }
    }

    func product(for idOrThemeId: String) -> ThemeSkinProduct? {
        products.first { $0.id == idOrThemeId || $0.themeId == idOrThemeId }
    }

    func ownedRecord(for idOrThemeId: String) -> OwnedThemeSkin? {
        let resolvedId = product(for: idOrThemeId)?.themeId ?? idOrThemeId
        return ownedThemeSkins.first { $0.id == resolvedId }
    }

    func isPurchased(_ idOrThemeId: String) -> Bool {
        ownedRecord(for: idOrThemeId) != nil
    }

    func isActiveTheme(_ idOrThemeId: String) -> Bool {
        let resolvedId = product(for: idOrThemeId)?.themeId ?? idOrThemeId
        return activeSelection.activeThemeId == resolvedId
    }

    func priceQuote(for idOrThemeId: String) -> ThemeSkinPriceQuote? {
        guard let product = product(for: idOrThemeId) else { return nil }
        let isVIP = VIPManager.shared.isVIP
        let finalPrice = isVIP ? product.vipPrice : product.basePrice

        return ThemeSkinPriceQuote(
            productId: product.id,
            themeId: product.themeId,
            basePrice: product.basePrice,
            finalPrice: finalPrice,
            isVIPDiscountApplied: isVIP && product.vipPrice < product.basePrice,
            discountLabel: isVIP && product.vipPrice < product.basePrice ? VIPManager.themeSkinDiscountText : nil
        )
    }

    func purchasePrice(for idOrThemeId: String) -> Int? {
        priceQuote(for: idOrThemeId)?.finalPrice
    }

    func canPurchase(_ idOrThemeId: String) -> Bool {
        guard let price = purchasePrice(for: idOrThemeId) else { return false }
        return !isPurchased(idOrThemeId) && currentMeowCoinBalance >= price
    }

    func purchaseTheme(_ idOrThemeId: String, autoActivateIfNeeded: Bool = true) -> ThemeSkinActionResult {
        guard let product = product(for: idOrThemeId),
              let quote = priceQuote(for: idOrThemeId) else {
            return .failure("未找到主题商品。")
        }

        if isPurchased(product.themeId) {
            return .failure("这个主题已经购买过了。")
        }

        guard StoreManager.spendMeowCoins(quote.finalPrice) else {
            return .failure("喵币不足，需要 \(quote.finalPrice) 喵币。")
        }

        ownedThemeSkins.append(
            OwnedThemeSkin(
                id: product.themeId,
                purchasedAt: Date(),
                paidPrice: quote.finalPrice
            )
        )
        saveOwnedThemeSkins()

        let purchaseMessage = "已购买「\(product.name)」，消费 \(quote.finalPrice) 喵币。"
        if autoActivateIfNeeded {
            let didAdjustBackground = applyThemeSelection(product)
            return .success("\(purchaseMessage) 已自动应用。\(themeBackgroundHarmonySuffix(didAdjustBackground))")
        }

        broadcastChange()
        return .success(purchaseMessage)
    }

    func activateTheme(_ idOrThemeId: String) -> ThemeSkinActionResult {
        guard let product = product(for: idOrThemeId) else {
            return .failure("未找到主题。")
        }

        guard isPurchased(product.themeId) else {
            return .failure("请先购买这个主题。")
        }

        let didAdjustBackground = applyThemeSelection(product)
        return .success("已应用「\(product.name)」。\(themeBackgroundHarmonySuffix(didAdjustBackground))")
    }

    func deactivateCurrentTheme() -> ThemeSkinActionResult {
        guard activeSelection.activeThemeId != nil else {
            return .failure("当前没有启用中的主题。")
        }

        activeSelection = .inactive
        saveActiveSelection()
        broadcastChange()
        return .success("已停用当前主题。")
    }

    func isSlotSupported(_ slot: ThemeSkinSlot, in idOrThemeId: String? = nil) -> Bool {
        let resolvedId = idOrThemeId ?? activeSelection.activeThemeId
        guard let resolvedId, let product = product(for: resolvedId) else { return false }
        return product.supportedSlots.contains(slot)
    }

    func isSlotEnabled(_ slot: ThemeSkinSlot) -> Bool {
        guard activeSelection.activeThemeId != nil else { return false }
        return activeSelection.enabledSlots.contains(slot) && isSlotSupported(slot)
    }

    func enableSlot(_ slot: ThemeSkinSlot) -> ThemeSkinActionResult {
        setSlot(slot, enabled: true)
    }

    func disableSlot(_ slot: ThemeSkinSlot) -> ThemeSkinActionResult {
        setSlot(slot, enabled: false)
    }

    func setSlot(_ slot: ThemeSkinSlot, enabled: Bool) -> ThemeSkinActionResult {
        guard let activeThemeId = activeSelection.activeThemeId,
              let product = product(for: activeThemeId) else {
            return .failure("请先启用一个主题。")
        }

        guard product.supportedSlots.contains(slot) else {
            return .failure("当前主题不支持这个组件。")
        }

        if enabled {
            activeSelection.enabledSlots.insert(slot)
        } else {
            activeSelection.enabledSlots.remove(slot)
        }

        activeSelection = sanitize(selection: activeSelection)
        saveActiveSelection()
        broadcastChange()
        return .success(enabled ? "已启用\(slot.displayName)。" : "已停用\(slot.displayName)。")
    }

    func descriptor(for slot: ThemeSkinSlot, state: ThemeSkinState = .default) -> ThemeSkinDescriptor? {
        guard isSlotEnabled(slot), let activeThemeId = activeSelection.activeThemeId else { return nil }
        return descriptor(forThemeId: activeThemeId, slot: slot, state: state)
    }

    func descriptor(forThemeId themeId: String, slot: ThemeSkinSlot, state: ThemeSkinState = .default) -> ThemeSkinDescriptor? {
        guard let product = product(for: themeId), product.supportedSlots.contains(slot) else { return nil }

        let descriptorCode = "skin.\(product.assetNamespace).\(slot.descriptorNamespace).\(slot.descriptorVariant).\(state.rawValue)"
        return ThemeSkinDescriptor(
            themeId: product.themeId,
            assetNamespace: product.assetNamespace,
            slot: slot,
            variant: slot.descriptorVariant,
            state: state,
            descriptorCode: descriptorCode
        )
    }

    func enabledDescriptorsForActiveTheme(state: ThemeSkinState = .default) -> [ThemeSkinDescriptor] {
        activeSelection.enabledSlots.compactMap { descriptor(for: $0, state: state) }
    }

    func activeThemeDescriptor(for slot: ThemeSkinSlot, state: ThemeSkinState = .default) -> ThemeSkinDescriptor? {
        descriptor(for: slot, state: state)
    }

    func backgroundHeroAssetName(for idOrThemeId: String) -> String? {
        guard let product = product(for: idOrThemeId) else { return nil }

        if let selection = backgroundStickerSelections[product.themeId] {
            guard let heroAssetName = selection.heroAssetName else { return nil }
            return product.backgroundStickerOptions.contains { $0.assetName == heroAssetName }
                ? heroAssetName
                : product.defaultBackgroundHeroAssetName
        }

        return product.defaultBackgroundHeroAssetName
    }

    func backgroundLayoutPreset(for idOrThemeId: String) -> ThemeSkinWallpaperLayoutPreset {
        guard let product = product(for: idOrThemeId) else { return .mixedFocus }
        return backgroundStickerSelections[product.themeId]?.layoutPreset ?? .mixedFocus
    }

    func setBackgroundHeroAssetName(_ assetName: String?, for idOrThemeId: String) {
        guard let product = product(for: idOrThemeId) else { return }

        let sanitizedAssetName: String?
        if let assetName, product.backgroundStickerOptions.contains(where: { $0.assetName == assetName }) {
            sanitizedAssetName = assetName
        } else {
            sanitizedAssetName = nil
        }

        var nextSelections = backgroundStickerSelections
        nextSelections[product.themeId] = ThemeSkinBackgroundSelection(
            heroAssetName: sanitizedAssetName,
            layoutPreset: backgroundLayoutPreset(for: product.themeId)
        )
        backgroundStickerSelections = nextSelections
        saveBackgroundStickerSelections()
        broadcastChange()
    }

    func setBackgroundLayoutPreset(_ preset: ThemeSkinWallpaperLayoutPreset, for idOrThemeId: String) {
        guard let product = product(for: idOrThemeId) else { return }

        var nextSelections = backgroundStickerSelections
        nextSelections[product.themeId] = ThemeSkinBackgroundSelection(
            heroAssetName: backgroundHeroAssetName(for: product.themeId),
            layoutPreset: preset
        )
        backgroundStickerSelections = nextSelections
        saveBackgroundStickerSelections()
        broadcastChange()
    }

    private func sanitize(selection: ActiveThemeSkinSelection) -> ActiveThemeSkinSelection {
        guard let activeThemeId = selection.activeThemeId,
              let product = product(for: activeThemeId),
              isPurchased(activeThemeId) else {
            return .inactive
        }

        let filteredSlots = selection.enabledSlots.filter { product.supportedSlots.contains($0) }
        let enabledSlots = Set(filteredSlots)
        return ActiveThemeSkinSelection(activeThemeId: product.themeId, enabledSlots: enabledSlots)
    }

    private func sanitize(backgroundSelections selections: [String: ThemeSkinBackgroundSelection]) -> [String: ThemeSkinBackgroundSelection] {
        selections.reduce(into: [String: ThemeSkinBackgroundSelection]()) { result, entry in
            guard let product = product(for: entry.key) else { return }
            let heroAssetName = entry.value.heroAssetName
            let layoutPreset = entry.value.layoutPreset
            if let heroAssetName, product.backgroundStickerOptions.contains(where: { $0.assetName == heroAssetName }) {
                result[product.themeId] = ThemeSkinBackgroundSelection(
                    heroAssetName: heroAssetName,
                    layoutPreset: layoutPreset
                )
            } else if heroAssetName == nil || layoutPreset != nil {
                result[product.themeId] = ThemeSkinBackgroundSelection(
                    heroAssetName: nil,
                    layoutPreset: layoutPreset
                )
            }
        }
    }

    private func migrateCoreSurfaceDefaultsIfNeeded(defaults: UserDefaults) {
        guard let activeThemeId = activeSelection.activeThemeId,
              let product = product(for: activeThemeId),
              isPurchased(activeThemeId) else {
            return
        }

        let migrationKey = "\(coreSurfaceMigrationKeyPrefix).\(product.themeId)"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let newCoreSlots: Set<ThemeSkinSlot> = [
            .settingsGridCard,
            .sectionCard,
            .primaryButton,
            .iconCircleButton,
            .emptyState
        ]
        let slotsToEnable = newCoreSlots.filter { product.supportedSlots.contains($0) }

        if !slotsToEnable.isEmpty {
            activeSelection.enabledSlots.formUnion(slotsToEnable)
            activeSelection = sanitize(selection: activeSelection)
            saveActiveSelection()
        }

        defaults.set(true, forKey: migrationKey)
    }

    private func migrateTopNavigationDefaultsIfNeeded(defaults: UserDefaults) {
        guard let activeThemeId = activeSelection.activeThemeId,
              let product = product(for: activeThemeId),
              isPurchased(activeThemeId) else {
            return
        }

        let migrationKey = "\(topNavigationMigrationKeyPrefix).\(product.themeId)"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let navigationSlots: Set<ThemeSkinSlot> = [
            .topBarSegment,
            .topBarAddButton
        ]
        let slotsToEnable = navigationSlots.filter { product.supportedSlots.contains($0) }

        if !slotsToEnable.isEmpty {
            activeSelection.enabledSlots.formUnion(slotsToEnable)
            activeSelection = sanitize(selection: activeSelection)
            saveActiveSelection()
        }

        defaults.set(true, forKey: migrationKey)
    }

    @discardableResult
    private func applyThemeSelection(_ product: ThemeSkinProduct) -> Bool {
        activeSelection = ActiveThemeSkinSelection(
            activeThemeId: product.themeId,
            enabledSlots: Set(product.defaultEnabledSlots.filter { product.supportedSlots.contains($0) })
        )
        saveActiveSelection()
        let wasUsingImageBackground = UserDefaults.standard.string(forKey: "theme_background_style") == BackgroundStyle.image.rawValue
        let didAdjustBackground = ThemeManager.shared.enforceThemeSkinBackgroundHarmonyIfNeeded(activeThemeId: product.themeId)
        broadcastChange()
        return wasUsingImageBackground || didAdjustBackground
    }

    private func themeBackgroundHarmonySuffix(_ didAdjustBackground: Bool) -> String {
        didAdjustBackground ? " \(ThemeManager.themeSkinBackgroundHarmonyAppendix)" : ""
    }

    private func saveOwnedThemeSkins() {
        if let encoded = try? JSONEncoder().encode(ownedThemeSkins) {
            UserDefaults.standard.set(encoded, forKey: ownedKey)
        }
    }

    private func saveActiveSelection() {
        if let encoded = try? JSONEncoder().encode(activeSelection) {
            UserDefaults.standard.set(encoded, forKey: activeSelectionKey)
        }
    }

    private func saveBackgroundStickerSelections() {
        if let encoded = try? JSONEncoder().encode(backgroundStickerSelections) {
            UserDefaults.standard.set(encoded, forKey: backgroundStickerSelectionKey)
        }
    }

    private func broadcastChange() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .themeSkinDidChange, object: nil)
    }
}

extension Notification.Name {
    static let themeSkinDidChange = Notification.Name("ThemeSkinDidChange")
}
