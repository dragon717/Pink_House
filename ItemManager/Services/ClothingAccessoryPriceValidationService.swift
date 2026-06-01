//
//  ClothingAccessoryPriceValidationService.swift
//  ItemManager
//
//  开屏时校验自定义小物总价，避免旧数据或历史逻辑导致 accessoriesPrice 漂移
//

import Foundation
import SwiftData

@MainActor
final class ClothingAccessoryPriceValidationService {
    static let shared = ClothingAccessoryPriceValidationService()

    private let validationVersion = "2026-06-accessory-price-cache-v1"
    private let validationVersionKey = "clothingAccessoryPriceValidation.completedVersion"
    private let fullValidationItemLimit = 2_000

    private init() {}

    func validateIfNeeded(modelContainer: ModelContainer) async {
        guard UserDefaults.standard.string(forKey: validationVersionKey) != validationVersion else {
            print("[AccessoryPriceValidation] 已完成当前版本校验，跳过")
            return
        }

        print("[AccessoryPriceValidation] 开始校验自定义小物总价...")

        #if !WIDGET_EXTENSION
        guard !SwiftDataMigrationManager.shared.isMigrating else {
            print("[AccessoryPriceValidation] iCloud 迁移中，跳过本轮校验")
            return
        }
        #endif

        let context = modelContainer.mainContext

        do {
            var descriptor = FetchDescriptor<Clothing>(
                predicate: #Predicate<Clothing> { $0.deletedAt == nil }
            )
            descriptor.fetchLimit = fullValidationItemLimit + 1
            let clothings = try context.fetch(descriptor)
            guard clothings.count <= fullValidationItemLimit else {
                print("[AccessoryPriceValidation] 活跃衣物超过 \(fullValidationItemLimit) 件，跳过启动期全量小物校验")
                UserDefaults.standard.set(validationVersion, forKey: validationVersionKey)
                return
            }

            var fixedCount = 0

            for clothing in clothings {
                guard let accessoryItems = clothing.accessoryItems, !accessoryItems.isEmpty else {
                    continue
                }

                let recalculatedTotal = accessoryItems.reduce(Decimal(0)) {
                    $0 + FinancialDataSanitizer.money($1.price)
                }
                guard clothing.accessoriesPrice != recalculatedTotal else { continue }

                clothing.accessoriesPrice = recalculatedTotal
                fixedCount += 1
                print("[AccessoryPriceValidation] 已修正 \(clothing.name) 的小物总价为 \(NSDecimalNumber(decimal: recalculatedTotal).stringValue)")
            }

            if fixedCount > 0 {
                try context.save()
                print("[AccessoryPriceValidation] 校验完成，已修正 \(fixedCount) 条数据")
            } else {
                print("[AccessoryPriceValidation] 无需修正")
            }
            UserDefaults.standard.set(validationVersion, forKey: validationVersionKey)
        } catch {
            print("[AccessoryPriceValidation] 校验失败: \(error)")
        }
    }
}
