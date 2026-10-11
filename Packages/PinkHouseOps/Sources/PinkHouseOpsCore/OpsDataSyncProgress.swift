import Foundation
import SharedCatalog

/// 只描述当前阶段；图片的 100% 不代表整轮迁移已回读确认。
public struct OpsDataSyncProgress: Equatable, Sendable {
    public private(set) var title: String
    public private(set) var completed: Int?
    public private(set) var total: Int?
    public let startedAt: Date
    public private(set) var lastAdvancedAt: Date
    private var phase: String

    public init(title: String, now: Date = Date()) {
        self.title = title
        phase = title
        startedAt = now
        lastAdvancedAt = now
    }

    public var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }

    public var countText: String? {
        guard let completed, let total, total > 0 else { return nil }
        return "\(completed)/\(total) 张"
    }

    public mutating func advance(to title: String, now: Date = Date()) {
        setPhase(title, title: title, now: now)
    }

    /// 重复、倒退或无关的输出不算进展，也不能掩盖长时间等待。
    public mutating func receive(_ event: ShopCatalogPublishEvent, mode: OpsBridgeMode,
                                 environment: ShopCatalogPublishTargetEnvironment, now: Date = Date()) {
        let name = environment == .development ? "开发环境" : "线上环境"
        guard let stage = event.stage else { return }
        let key = "\(environment.rawValue)/\(mode.rawValue)/\(stage.rawValue)"
        let title: String
        switch stage {
        case .baseline, .readHead: title = "读取\(name)版本"
        case .fetchMedia: title = "下载\(name)图片"
        case .remoteMedia: title = "检查\(name)已有图片"
        case .uploadMedia: title = "上传\(name)图片"
        case .build, .freeze: title = "准备同步数据"
        case .verifyArtifact: title = "校验同步数据"
        case .uploadPacks: title = "上传\(name)目录"
        case .readBack: title = "核对\(name)图片和目录"
        case .switchHead: title = "更新\(name)版本"
        case .confirmHead: title = "确认\(name)更新结果"
        }
        if event.type == "stage", event.state == .started {
            setPhase(key, title: title, now: now)
        } else if event.type == "stage", event.state == .succeeded,
                  stage == .baseline, mode == .pullCatalog {
            setPhase(key + "/catalog", title: "下载\(name)目录", now: now)
        } else if event.type == "progress", [.fetchMedia, .uploadMedia].contains(stage),
                  let count = event.completed, let size = event.total, count >= 0, size >= 0 {
            setPhase(key, title: title, now: now)
            let next = min(count, size)
            if total != size || completed == nil || next > completed! {
                completed = total == size ? max(completed ?? 0, next) : next
                total = size
                lastAdvancedAt = now
            }
        }
    }

    public func timingText(at now: Date) -> String {
        let elapsed = Self.duration(now.timeIntervalSince(startedAt))
        let silence = now.timeIntervalSince(lastAdvancedAt)
        return silence >= 45
            ? "已用 \(elapsed) · 等待响应 \(Self.duration(silence))，尚未完成"
            : "已用 \(elapsed)"
    }

    private mutating func setPhase(_ key: String, title: String, now: Date) {
        guard phase != key else { return }
        phase = key
        self.title = title
        completed = nil
        total = nil
        lastAdvancedAt = now
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}
