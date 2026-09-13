import Combine
import Foundation

// MARK: - 收藏与私人状态
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §1.2 D / §13.3 / §14.3 / §17.3。
//
// **收藏不是缓存。**
//   - `timeHall.treasured.v1` 继续保留，清理下载缓存时不得删除；
//   - 需要新封装时先读旧 key，再以可重复方式迁移；
//   - 运营条目被撤回时，收藏关系保留，界面显示「原图鉴资料已不可用」，
//     但不再提供该条目的运营图片与正文再次下载。
//
// 本类型**只碰收藏标识**，不接触衣橱、照片、手账或其他个人资产。

@MainActor
final class TimeHallUserStateStore: ObservableObject {
    static let shared = TimeHallUserStateStore()

    /// 现有收藏键。**不得改名**，否则既有用户收藏会全部失效。
    static let legacyTreasureKey = "timeHall.treasured.v1"

    /// 迁移目标键。当前为空实现，只为将来更换 ID 方案预留显式迁移入口。
    static let migrationTreasureKey = "timeHall.treasured.v2"

    @Published private(set) var treasuredIDs: Set<String> = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        var result = Set(defaults.stringArray(forKey: Self.legacyTreasureKey) ?? [])
        // 迁移键存在时取并集，保证迁移过程可重复执行、不丢收藏
        if let migrated = defaults.stringArray(forKey: Self.migrationTreasureKey) {
            result.formUnion(migrated)
        }
        treasuredIDs = result
    }

    func isTreasured(_ id: String) -> Bool {
        treasuredIDs.contains(id)
    }

    func toggle(_ id: String) {
        if treasuredIDs.contains(id) {
            treasuredIDs.remove(id)
        } else {
            treasuredIDs.insert(id)
        }
        persist()
    }

    func setTreasured(_ id: String, _ isTreasured: Bool) {
        guard isTreasured != treasuredIDs.contains(id) else { return }
        if isTreasured {
            treasuredIDs.insert(id)
        } else {
            treasuredIDs.remove(id)
        }
        persist()
    }

    /// 无可映射身份的收藏保留占位，**不静默删除**（§4.5）。
    func remapOwnedIDs(_ mapping: [String: String]) {
        guard !mapping.isEmpty else { return }
        var result: Set<String> = []
        for id in treasuredIDs {
            result.insert(mapping[id] ?? id)
        }
        treasuredIDs = result
        persist()
    }

    /// 已被运营撤回、但用户仍收藏着的条目 ID。
    ///
    /// 收藏关系保留，界面据此显示「原图鉴资料已不可用」。
    func withdrawnTreasuredIDs(withdrawn: Set<String>) -> Set<String> {
        treasuredIDs.intersection(withdrawn)
    }

    private func persist() {
        let sorted = Array(treasuredIDs)
        defaults.set(sorted, forKey: Self.legacyTreasureKey)
        defaults.set(sorted, forKey: Self.migrationTreasureKey)
    }
}
