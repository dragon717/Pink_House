import Foundation

/// 录入列表只重算发生变化的款式。提交仍走完整 OpsSeriesEntryValidator。
@MainActor
final class OpsSeriesEntryValidationCache {
    private var entries: [String: (OpsSeriesTypeEntry, [OpsSeriesEntryIssue])] = [:]

    func issues(for entry: OpsSeriesTypeEntry) -> [OpsSeriesEntryIssue] {
        if let cached = entries[entry.id], cached.0 == entry { return cached.1 }
        var issues: [OpsSeriesEntryIssue] = []
        OpsSeriesEntryValidator.validateEntry(entry, into: &issues)
        // 草稿切换/删除不能让缓存无限增长。
        if entries.count >= 512 { entries.removeAll(keepingCapacity: true) }
        entries[entry.id] = (entry, issues)
        return issues
    }
}
