import Foundation

struct SeriesInfo: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let styleCount: Int
    let itemCount: Int
    let totalBalance: Decimal
    let totalDeposit: Decimal
    /// 汇总与明细共用成员身份，不能再分别按名称前缀猜测。
    let clothingIDs: Set<UUID>
}

struct SeriesInput: Sendable {
    let id: UUID
    let name: String
    /// 已包含库存和小物的待付金额，不再乘库存或加定金。
    let balance: Decimal
    let deposit: Decimal
    let stock: Int
}

final class SeriesAnalyzer {
    static let shared = SeriesAnalyzer()

    func analyzeSeries(from clothings: [Clothing]) async -> [SeriesInfo] {
        let inputs = clothings.map {
            SeriesInput(id: $0.id, name: $0.name,
                        balance: $0.pendingFinalPaymentAmount,
                        deposit: $0.reservationPaidAmount,
                        stock: FinancialDataSanitizer.stock($0.stock))
        }
        return await Task.detached(priority: .userInitiated) {
            Self.summarize(inputs)
        }.value
    }

    /// 前 2～4 字规则：先按共同的前两字划分互斥成员，再取最长共同前缀作为名称。
    /// 美乐蒂、美乐蒂联、美乐蒂蜜因此只有一个「美乐蒂」，每件衣物仅统计一次。
    nonisolated static func summarize(_ inputs: [SeriesInput]) -> [SeriesInfo] {
        var seen = Set<UUID>()
        let unique = inputs.filter { seen.insert($0.id).inserted }
        let groups = Dictionary(grouping: unique) {
            String(normalizedName($0.name).prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return groups.values.map { members in
            var prefix = String(normalizedName(members[0].name).prefix(4))
            for member in members.dropFirst() {
                let name = normalizedName(member.name)
                while !name.hasPrefix(prefix) { prefix.removeLast() }
            }
            return SeriesInfo(
                name: prefix.trimmingCharacters(in: .whitespacesAndNewlines),
                styleCount: Set(members.map { normalizedName($0.name) }).count,
                itemCount: members.reduce(0) { $0 + $1.stock },
                totalBalance: members.reduce(0) { $0 + $1.balance },
                totalDeposit: members.reduce(0) { $0 + $1.deposit },
                clothingIDs: Set(members.map(\.id)))
        }.sorted {
            if $0.totalBalance != $1.totalBalance { return $0.totalBalance > $1.totalBalance }
            if $0.styleCount != $1.styleCount { return $0.styleCount > $1.styleCount }
            return $0.name < $1.name
        }
    }

    private nonisolated static func normalizedName(_ text: String) -> String {
        let charactersToRemove = CharacterSet(charactersIn: "[]【】(){}<>《》")
        let name = text.components(separatedBy: charactersToRemove).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.isEmpty ? "未命名" : name
    }
}
