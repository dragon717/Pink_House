import Foundation

// MARK: - 旧馆（馆藏档案 / 我的品牌）脏数据清理
//
// 2026-09-24 时光馆只保留「店家上新」，旧馆代码整体移除（用户确认口径）。
// 旧馆相关的 UserDefaults 键全部清掉，其中：
//   · `timehall.brand.followedAt`                  —— 品牌列表「N 天前加入」的本地覆盖层，纯 UI 数据；
//   · `timeHall.treasured.v1` / `v2`               —— 旧馆画册展品收藏（用户已确认放弃未迁移部分）；
//   · `timeHall.treasured.wishMigration.v1` 等两个 —— 收藏 → 心愿尾款迁移的标记与逐条检查点；
//   · `timeHall.cloudSync.enabled`                 —— 旧馆 CloudKit 增量包同步开关。
// 每次启动都执行一遍：幂等且廉价，避免再引入「一次性标记」这种新的脏数据。
@MainActor
enum LegacyTimeHallDataCleaner {
    /// 旧馆遗留键。代码已随旧馆删除，这里只留字符串字面量做一次性清理。
    private static let legacyKeys = [
        "timehall.brand.followedAt",
        "timeHall.treasured.v1",
        "timeHall.treasured.v2",
        "timeHall.treasured.wishMigration.v1",
        "timeHall.treasured.wishMigration.checkpoints.v1",
        "timeHall.cloudSync.enabled",
    ]

    static func purgeIfNeeded(defaults: UserDefaults = .standard) {
        for key in legacyKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            AppLogger.info("[LegacyTimeHallDataCleaner] 已清除旧馆遗留键：\(key)")
        }
    }
}
