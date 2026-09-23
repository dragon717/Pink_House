import Foundation
import SwiftData

// MARK: - 加入衣橱的两种形态
//
// 形态 A「一键入库」：不打开编辑页，直接把商品落成 `Clothing` 写入 SwiftData。
// 形态 B「加入并编辑」：复用既有的 `TabNavigationManager.presentWardrobeCreation(with:)`，
//                    跳到衣橱的手动创建页并预填，使用者可逐项确认后再保存。
//
// 2026-09-24：旧馆（馆藏档案/我的品牌）与仲夏物语模块整体移除，
// 原先由 `TimeHallItemDTO` / `TimeHallCommerceItemDTO` / 仲夏 DTO 走
// DraftBuilder 的重载与 `TimeHallWardrobeInsertMode`/`InsertButtons` 随之删除；
// 本文件只剩「草稿 → 落库」的共用管线，供店家上新复用。

// MARK: - 形态 A：一键入库

@MainActor
enum TimeHallWardrobeQuickInserter {
  /// 把一份已构造好的草稿直接落库。
  ///
  /// 字段映射与 `ClothingEditView.save()` 的新建分支保持一致，
  /// 区别只是「不经确认直接写」——因此这里不引入任何新的价格推算规则，
  /// 草稿是什么就写什么。
  @discardableResult
  static func insert(draft: ClothingEditDraft, modelContext: ModelContext) throws -> Clothing {
    let brand = getOrCreateBrand(name: draft.brandName, modelContext: modelContext)

    let clothing = Clothing(
      name: draft.name,
      brand: brand,
      types: draft.types,
      colors: draft.colors,
      sizes: draft.sizes,
      length: draft.length,
      condition: draft.condition.isEmpty ? "全新" : draft.condition,
      accessories: draft.accessories,
      imagePaths: draft.imagePaths,
      isShared: draft.isShared,
      originalPrice: Decimal(draft.originalPrice),
      originalPriceJPY: Decimal(draft.originalPriceJPY ?? 0),
      originalPriceCurrencyCode: draft.originalPriceCurrencyCode
        ?? ClothingPriceCurrency.jpy.rawValue,
      originalPriceExchangeRateJPY: Decimal(draft.originalPriceExchangeRateJPY ?? 21.0),
      originalPriceRateUpdatedAt: draft.originalPriceRateUpdatedAt,
      price: Decimal(draft.priceTotal),
      deposit: Decimal(draft.deposit),
      balance: Decimal(draft.balance),
      accessoriesPrice: Decimal(draft.accessoriesPrice),
      shippingFee: Decimal(draft.shippingFee ?? 0),
      shippingFeeJPY: Decimal(draft.shippingFeeJPY ?? 0),
      shippingFeeCurrencyCode: draft.shippingFeeCurrencyCode
        ?? ClothingPriceCurrency.cny.rawValue,
      shippingExchangeRateJPY: Decimal(draft.shippingExchangeRateJPY ?? 21.0),
      shippingRateUpdatedAt: draft.shippingRateUpdatedAt,
      purchaseDate: draft.purchaseDate,
      depositDate: draft.depositDate,
      isDepositPlan: draft.isDepositPlan,
      finalPaymentDate: draft.finalPaymentDate,
      finalPaymentEndDate: draft.finalPaymentEndDate,
      note: draft.note,
      stock: draft.stock,
      status: .onShelf,
      isResaleTransfer: draft.isResaleTransfer ?? false
    )

    // 尺码表 / 价格表沿用草稿里的图片路径（商品档案会填这两项）。
    let sizeChart = draft.sizeChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
    let priceChart = draft.priceChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
    clothing.sizeChartImagePath = (sizeChart?.isEmpty == true) ? nil : sizeChart
    clothing.priceChartImagePath = (priceChart?.isEmpty == true) ? nil : priceChart

    modelContext.insert(clothing)
    do {
      try modelContext.save()
    } catch {
      // 保存失败要回滚插入，避免留下一个只有内存态的幽灵条目。
      modelContext.delete(clothing)
      AppLogger.error("一键入库失败：\(error.localizedDescription)")
      throw TimeHallWardrobeInsertError.saveFailed(error.localizedDescription)
    }
    return clothing
  }

  /// 与 `ClothingEditView.getOrCreateBrand(name:)` 同规则：先查后建，查失败也退化为新建。
  private static func getOrCreateBrand(name: String, modelContext: ModelContext) -> Brand? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let descriptor = FetchDescriptor<Brand>(predicate: #Predicate { $0.name == trimmed })
    if let existing = try? modelContext.fetch(descriptor).first {
      return existing
    }

    let newBrand = Brand(name: trimmed)
    modelContext.insert(newBrand)
    return newBrand
  }
}

nonisolated enum TimeHallWardrobeInsertError: LocalizedError {
  case saveFailed(String)

  var errorDescription: String? {
    switch self {
    case .saveFailed(let reason): return reason
    }
  }
}
