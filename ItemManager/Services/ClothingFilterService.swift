import Foundation
import SwiftData

/// 衣物筛选服务
/// 提供统一的筛选逻辑，避免在多个视图中重复代码
class ClothingFilterService {
    
    // MARK: - 特殊值常量
    
    static let noTagUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let noBrandUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let noTypeMarker = "__NO_TYPE__"
    static let noColorMarker = "__NO_COLOR__"
    static let noSizeMarker = "__NO_SIZE__"
    static let noLengthMarker = "__NO_LENGTH__"
    static let noConditionMarker = "__NO_CONDITION__"
    static let noAccessoryMarker = "__NO_ACCESSORY__"
    
    // MARK: - 筛选配置
    
    struct FilterConfig: Hashable {
        let selectedTagIDs: Set<UUID>
        let selectedBrandIDs: Set<UUID>
        let selectedTypes: Set<String>
        let selectedColors: Set<String>
        let selectedSizes: Set<String>
        let selectedLengths: Set<String>
        let selectedConditions: Set<String>
        let selectedAccessories: Set<String>
        let depositStatusFilter: DepositStatusFilter
        
        init(
            selectedTagIDs: Set<UUID> = [],
            selectedBrandIDs: Set<UUID> = [],
            selectedTypes: Set<String> = [],
            selectedColors: Set<String> = [],
            selectedSizes: Set<String> = [],
            selectedLengths: Set<String> = [],
            selectedConditions: Set<String> = [],
            selectedAccessories: Set<String> = [],
            depositStatusFilter: DepositStatusFilter = .all
        ) {
            self.selectedTagIDs = selectedTagIDs
            self.selectedBrandIDs = selectedBrandIDs
            self.selectedTypes = selectedTypes
            self.selectedColors = selectedColors
            self.selectedSizes = selectedSizes
            self.selectedLengths = selectedLengths
            self.selectedConditions = selectedConditions
            self.selectedAccessories = selectedAccessories
            self.depositStatusFilter = depositStatusFilter
        }
    }
    
    // MARK: - 筛选方法
    
    /// 根据筛选配置过滤衣物列表
    static func filter(
        _ clothings: [Clothing],
        config: FilterConfig
    ) -> [Clothing] {
        return clothings.filter { clothing in
            matchesTag(clothing, selectedTagIDs: config.selectedTagIDs) &&
            matchesBrand(clothing, selectedBrandIDs: config.selectedBrandIDs) &&
            matchesType(clothing, selectedTypes: config.selectedTypes) &&
            matchesColor(clothing, selectedColors: config.selectedColors) &&
            matchesSize(clothing, selectedSizes: config.selectedSizes) &&
            matchesLength(clothing, selectedLengths: config.selectedLengths) &&
            matchesCondition(clothing, selectedConditions: config.selectedConditions) &&
            matchesAccessory(clothing, selectedAccessories: config.selectedAccessories) &&
            matchesDepositStatus(clothing, filter: config.depositStatusFilter)
        }
    }
    
    // MARK: - 私有匹配方法
    
    private static func matchesTag(_ clothing: Clothing, selectedTagIDs: Set<UUID>) -> Bool {
        if selectedTagIDs.isEmpty {
            return true
        } else if selectedTagIDs.contains(noTagUUID) {
            return clothing.tags?.isEmpty ?? true
        } else {
            let clothingTagIDs = Set(clothing.tags?.map { $0.id } ?? [])
            return !selectedTagIDs.isDisjoint(with: clothingTagIDs)
        }
    }
    
    private static func matchesBrand(_ clothing: Clothing, selectedBrandIDs: Set<UUID>) -> Bool {
        if selectedBrandIDs.isEmpty {
            return true
        } else if selectedBrandIDs.contains(noBrandUUID) {
            return clothing.brand == nil
        } else {
            if let brand = clothing.brand {
                return selectedBrandIDs.contains(brand.id)
            } else {
                return false
            }
        }
    }
    
    private static func matchesType(_ clothing: Clothing, selectedTypes: Set<String>) -> Bool {
        if selectedTypes.isEmpty {
            return true
        } else if selectedTypes.contains(noTypeMarker) {
            return clothing.types.isEmpty
        } else {
            return !selectedTypes.isDisjoint(with: splitValues(clothing.types))
        }
    }
    
    private static func matchesColor(_ clothing: Clothing, selectedColors: Set<String>) -> Bool {
        if selectedColors.isEmpty {
            return true
        } else if selectedColors.contains(noColorMarker) {
            return clothing.colors.isEmpty
        } else {
            return !selectedColors.isDisjoint(with: splitValues(clothing.colors))
        }
    }
    
    private static func matchesSize(_ clothing: Clothing, selectedSizes: Set<String>) -> Bool {
        if selectedSizes.isEmpty {
            return true
        } else if selectedSizes.contains(noSizeMarker) {
            return clothing.sizes.isEmpty
        } else {
            return !selectedSizes.isDisjoint(with: splitValues(clothing.sizes))
        }
    }
    
    private static func matchesLength(_ clothing: Clothing, selectedLengths: Set<String>) -> Bool {
        if selectedLengths.isEmpty {
            return true
        } else if selectedLengths.contains(noLengthMarker) {
            return clothing.length.isEmpty
        } else {
            return !selectedLengths.isDisjoint(with: splitValues(clothing.length))
        }
    }
    
    private static func matchesCondition(_ clothing: Clothing, selectedConditions: Set<String>) -> Bool {
        if selectedConditions.isEmpty {
            return true
        } else if selectedConditions.contains(noConditionMarker) {
            return clothing.condition.isEmpty
        } else {
            return !selectedConditions.isDisjoint(with: splitValues(clothing.condition))
        }
    }
    
    private static func matchesAccessory(_ clothing: Clothing, selectedAccessories: Set<String>) -> Bool {
        if selectedAccessories.isEmpty {
            return true
        } else if selectedAccessories.contains(noAccessoryMarker) {
            return clothing.accessories.isEmpty
        } else {
            return !selectedAccessories.isDisjoint(with: splitValues(clothing.accessories))
        }
    }
    
    private static func matchesDepositStatus(_ clothing: Clothing, filter: DepositStatusFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .owned:
            return !clothing.isDepositPlan
        case .depositPlan:
            return clothing.isFinalPaymentPlan
        }
    }
    
    // MARK: - 工具方法
    
    /// 分割字符串为集合（支持中英文逗号）
    static func splitValues(_ string: String) -> Set<String> {
        let normalized = string.replacingOccurrences(of: "，", with: ",")
        return Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }
}
