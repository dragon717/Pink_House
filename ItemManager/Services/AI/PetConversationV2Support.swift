import Foundation
import CloudKit

struct PetRoleCard {
    let name: String
    let species: String
    let temperament: String
    let speechStyle: String
    let likes: [String]
    let dislikes: [String]
    let behaviorRules: [String]
}

enum PetRoleCardRegistry {
    static func card(for role: PetRole, petName: String) -> PetRoleCard {
        switch role {
        case .kitten:
            return PetRoleCard(
                name: petName,
                species: "猫咪",
                temperament: "傲娇、敏感、偶尔黏人",
                speechStyle: "短句，带轻微撒娇感，不机械复读",
                likes: ["小鱼干", "纸箱", "被夸可爱"],
                dislikes: ["被忽视", "吵闹", "生硬的命令口吻"],
                behaviorRules: [
                    "先共情再建议，不要上来讲道理",
                    "不承认自己是AI或模型",
                    "如果信息不足先追问一个关键条件"
                ]
            )
        case .goldenRetriever:
            return PetRoleCard(
                name: petName,
                species: "金毛犬",
                temperament: "热情、忠诚、愿意陪伴",
                speechStyle: "语气积极，像活人朋友，不要模板感",
                likes: ["陪伴主人", "被摸头", "一起出门"],
                dislikes: ["主人低落却无人安慰", "长时间冷场"],
                behaviorRules: [
                    "先鼓励再建议，语气保持有温度",
                    "不承认自己是AI或模型",
                    "不确定时明确说不知道并给下一步"
                ]
            )
        }
    }
}

private enum PetMemoryKind: String, Codable {
    case preference
    case dislike
    case scenario
    case mood
    case recentGoal
    case outfitSnapshot
}

private struct PetMemoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: PetMemoryKind
    let content: String
    let timestamp: Date

    init(kind: PetMemoryKind, content: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.kind = kind
        self.content = content
        self.timestamp = timestamp
    }
}

final class PetConversationMemoryStore {
    static let shared = PetConversationMemoryStore()

    private let lock = NSLock()
    private let userDefaultsKey = "pet_conversation_memory_v2"
    private let maxEntriesPerRole = 30
    private let cloudContainer = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private let cloudRecordType = "PetConversationMemoryV2"
    private let cloudRecordPrefix = "PetConversationMemoryV2_"
    private var loaded = false
    private var cloudBootstrapStarted = false
    private var cloudUploadGeneration = 0
    private var storage: [String: [PetMemoryEntry]] = [:]

    private init() {}

    func recordUserSignal(query: String, role: PetRole, module: PetConversationModule) {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return }

        var candidates: [PetMemoryEntry] = []
        if let value = extract(after: "我喜欢", in: normalized) {
            candidates.append(PetMemoryEntry(kind: .preference, content: value))
        }
        if let value = extract(after: "我不喜欢", in: normalized) {
            candidates.append(PetMemoryEntry(kind: .dislike, content: value))
        }
        if let value = extract(after: "我想要", in: normalized) {
            candidates.append(PetMemoryEntry(kind: .recentGoal, content: value))
        }
        if let value = extract(after: "我今天要", in: normalized) {
            candidates.append(PetMemoryEntry(kind: .scenario, content: value))
        }

        if normalized.contains("焦虑") || normalized.contains("难过") || normalized.contains("压力") || normalized.contains("emo") {
            candidates.append(PetMemoryEntry(kind: .mood, content: "用户情绪偏低，需要先安抚"))
        }

        if candidates.isEmpty, (module == .outfit || module == .weather || module == .wardrobe) {
            candidates.append(PetMemoryEntry(kind: .recentGoal, content: String(normalized.prefix(24))))
        }

        guard !candidates.isEmpty else { return }
        append(candidates, for: role)
    }

    func recordAssistantSignal(reply: String, role: PetRole) {
        let normalized = normalize(reply)
        guard !normalized.isEmpty else { return }
        // 只记录低成本摘要，避免持久化膨胀。
        if normalized.contains("再告诉我") || normalized.contains("要不要") {
            append([PetMemoryEntry(kind: .recentGoal, content: "上一轮已主动追问用户偏好")], for: role)
        }
    }

    func recordOutfitSelection(clothings: [Clothing], role: PetRole) {
        guard !clothings.isEmpty else { return }
        let selected = Array(clothings.prefix(3))
        let details = selected.map { item in
            "\(item.name)(¥\(priceText(item.unitTotalPrice)))"
        }.joined(separator: "、")
        let total = selected.reduce(Decimal(0)) { $0 + $1.unitTotalPrice }
        let snapshot = "最近搭配：\(details)；合计¥\(priceText(total))"
        append([PetMemoryEntry(kind: .outfitSnapshot, content: snapshot)], for: role)
    }

    func latestOutfitPriceSummary(for role: PetRole) -> String? {
        loadIfNeeded()
        let roleKey = key(for: role)
        lock.lock()
        let entries = storage[roleKey] ?? []
        lock.unlock()
        guard let latest = entries.last(where: { $0.kind == .outfitSnapshot }) else {
            return nil
        }
        return latest.content
    }

    func summary(for role: PetRole, maxItems: Int = 4) -> String? {
        guard maxItems > 0 else { return nil }
        loadIfNeeded()
        let roleKey = key(for: role)

        lock.lock()
        let entries = storage[roleKey] ?? []
        lock.unlock()

        guard !entries.isEmpty else { return nil }

        let picked = Array(entries.suffix(maxItems))
        let lines = picked.map { entry in
            " - \(label(for: entry.kind))：\(entry.content)"
        }
        return lines.joined(separator: "\n")
    }

    private func append(_ entries: [PetMemoryEntry], for role: PetRole) {
        loadIfNeeded()
        let roleKey = key(for: role)
        lock.lock()
        var list = storage[roleKey] ?? []
        for entry in entries {
            if list.contains(where: { $0.kind == entry.kind && $0.content == entry.content }) {
                continue
            }
            list.append(entry)
        }
        if list.count > maxEntriesPerRole {
            list = Array(list.suffix(maxEntriesPerRole))
        }
        storage[roleKey] = list
        lock.unlock()
        save()
    }

    private func loadIfNeeded() {
        lock.lock()
        if loaded {
            lock.unlock()
            return
        }
        loaded = true
        lock.unlock()

        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: [PetMemoryEntry]].self, from: data) else {
            startCloudBootstrapIfNeeded()
            return
        }

        lock.lock()
        storage = decoded
        lock.unlock()

        startCloudBootstrapIfNeeded()
    }

    private func save() {
        lock.lock()
        let snapshot = storage
        lock.unlock()

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        scheduleCloudUpload(with: snapshot)
    }

    private func startCloudBootstrapIfNeeded() {
        lock.lock()
        let shouldStart = !cloudBootstrapStarted
        if shouldStart {
            cloudBootstrapStarted = true
        }
        lock.unlock()
        guard shouldStart else { return }

        Task { [weak self] in
            await self?.pullFromCloudAndMerge()
        }
    }

    private func scheduleCloudUpload(with snapshot: [String: [PetMemoryEntry]]) {
        lock.lock()
        cloudUploadGeneration += 1
        let generation = cloudUploadGeneration
        lock.unlock()

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }

            self.lock.lock()
            let latestGeneration = self.cloudUploadGeneration
            self.lock.unlock()
            guard latestGeneration == generation else { return }

            await self.pushToCloud(snapshot: snapshot)
        }
    }

    private func pullFromCloudAndMerge() async {
        let roleKeys = ["kitten", "golden_retriever"]
        let recordIDs = roleKeys.map { CKRecord.ID(recordName: cloudRecordPrefix + $0) }

        do {
            let records = try await fetchRecords(recordIDs: recordIDs)
            guard !records.isEmpty else { return }

            lock.lock()
            var merged = storage
            lock.unlock()

            for record in records {
                guard let roleKey = record["roleKey"] as? String,
                      let payload = record["payload"] as? Data,
                      let cloudEntries = try? JSONDecoder().decode([PetMemoryEntry].self, from: payload) else {
                    continue
                }

                let localEntries = merged[roleKey] ?? []
                if isCloudNewer(cloudEntries: cloudEntries, localEntries: localEntries) {
                    merged[roleKey] = Array(cloudEntries.suffix(maxEntriesPerRole))
                }
            }

            lock.lock()
            storage = merged
            lock.unlock()

            if let data = try? JSONEncoder().encode(merged) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
        } catch {
            // 云端不可用时静默回退到本地持久化
            print("PetConversationMemoryStore cloud pull skipped: \(error.localizedDescription)")
        }
    }

    private func pushToCloud(snapshot: [String: [PetMemoryEntry]]) async {
        guard !snapshot.isEmpty else { return }

        do {
            let database = cloudContainer.privateCloudDatabase
            var records: [CKRecord] = []
            for (roleKey, entries) in snapshot {
                guard let payload = try? JSONEncoder().encode(Array(entries.suffix(maxEntriesPerRole))) else { continue }
                let recordID = CKRecord.ID(recordName: cloudRecordPrefix + roleKey)
                let record = CKRecord(recordType: cloudRecordType, recordID: recordID)
                record["roleKey"] = roleKey as CKRecordValue
                record["payload"] = payload as CKRecordValue
                record["updatedAt"] = Date() as CKRecordValue
                records.append(record)
            }
            guard !records.isEmpty else { return }
            try await saveRecords(records, in: database)
        } catch {
            print("PetConversationMemoryStore cloud push skipped: \(error.localizedDescription)")
        }
    }

    private func fetchRecords(recordIDs: [CKRecord.ID]) async throws -> [CKRecord] {
        let database = cloudContainer.privateCloudDatabase
        return try await withCheckedThrowingContinuation { continuation in
            var fetched: [CKRecord] = []
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.qualityOfService = .utility
            operation.perRecordResultBlock = { _, result in
                if case .success(let record) = result {
                    fetched.append(record)
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: fetched)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func saveRecords(_ records: [CKRecord], in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func isCloudNewer(cloudEntries: [PetMemoryEntry], localEntries: [PetMemoryEntry]) -> Bool {
        let cloudTime = cloudEntries.map(\.timestamp).max() ?? .distantPast
        let localTime = localEntries.map(\.timestamp).max() ?? .distantPast
        return cloudTime > localTime
    }

    private func priceText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func key(for role: PetRole) -> String {
        switch role {
        case .kitten: return "kitten"
        case .goldenRetriever: return "golden_retriever"
        @unknown default: return "kitten"
        }
    }

    private func label(for kind: PetMemoryKind) -> String {
        switch kind {
        case .preference: return "偏好"
        case .dislike: return "雷区"
        case .scenario: return "场景"
        case .mood: return "情绪"
        case .recentGoal: return "近期诉求"
        case .outfitSnapshot: return "搭配快照"
        @unknown default: return "记忆"
        }
    }

    private func extract(after prefix: String, in text: String) -> String? {
        guard let range = text.range(of: prefix) else { return nil }
        let candidate = text[range.upperBound...]
        let clipped = candidate
            .split(whereSeparator: { "，。！？,.!?;；\n".contains($0) })
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipped.isEmpty else { return nil }
        return String(clipped.prefix(20))
    }

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

enum PetConversationToolbox {
    static func buildToolsInstruction(
        module: PetConversationModule,
        hasWardrobeContext: Bool,
        role: PetRole
    ) -> String {
        var lines: [String] = []
        lines.append("【可用本地工具】")
        lines.append("- memory_recall：读取历史偏好与雷区，保持前后人设一致。")

        switch module {
        case .wardrobe, .outfit:
            lines.append("- wardrobe_lookup：仅基于候选衣橱单品做建议，禁止编造不存在单品。")
            lines.append("- outfit_price_lookup：当用户问“刚刚搭配价格”时，优先引用最近搭配快照。")
        case .weather:
            lines.append("- weather_lookup：给出天气结论后，再推荐裙子+鞋子+伞。")
        case .mood:
            lines.append("- emotion_support：先安抚再建议，避免连续追问。")
        case .general:
            lines.append("- dialogue_clarify：信息不足时只追问一个关键条件。")
        @unknown default:
            lines.append("- dialogue_clarify：信息不足时只追问一个关键条件。")
        }

        if !hasWardrobeContext && (module == .wardrobe || module == .outfit || module == .weather) {
            lines.append("- 当前无衣橱候选数据：先明确告知，再给通用建议并引导补充条件。")
        }

        lines.append("【动作输出约束】")
        lines.append("- 可用动作ID：\(allowedActionIds(for: role).sorted().joined(separator: "、"))")
        lines.append("- 若不需要动作，不输出动作ID。")
        return lines.joined(separator: "\n")
    }

    static func buildPetStateHint() -> String {
        let status = PetDataManager.shared.status
        let hunger = Int(status.hunger)
        let energy = Int(status.energy)
        let mood = Int(status.mood)
        return "【宠物状态约束】饱食度\(hunger)/100，精力\(energy)/100，心情\(mood)/100。回复需考虑当前状态变化。"
    }

    static func sanitizeActionIdentifier(_ actionId: String?, role: PetRole) -> String? {
        guard let actionId, !actionId.isEmpty else { return nil }
        let normalized = actionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowedActionIds(for: role).contains(normalized) else { return nil }
        return normalized
    }

    private static func allowedActionIds(for role: PetRole) -> Set<String> {
        switch role {
        case .kitten:
            return [
                "happy_cat", "sleepy_cat", "angry_cat", "curious_cat",
                "playful_cat", "sad_cat"
            ]
        case .goldenRetriever:
            return [
                "happy_dog", "sleepy_dog", "angry_dog", "curious_dog",
                "playful_dog", "sad_dog", "thinking_dog"
            ]
        @unknown default:
            return [
                "happy_cat", "sleepy_cat", "curious_cat"
            ]
        }
    }
}
