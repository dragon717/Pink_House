//
//  ShopCatalogBaseline.swift
//  SharedCatalog
//
//  发布基线：这份草稿是**从哪个线上版本改出来的**（方案 R07 / §5）。
//
//  ## 为什么必须显式记录 + 显式核对
//
//  Mac 草稿存的是**完整目录 JSON**，`coverageStatus` 默认 `complete`，
//  而整包发布用的是**同一个发布头**（其他时光馆分片也挂在它下面）。
//  于是「A 和 B 从同一基线改不同商品，A 先发、B 后发」时，B 的整包会把
//  A 的改动**整体抹掉** —— 而且线上看不出来，因为 B 的目录本身是合法完整的。
//
//  现有发布器的 `changeTag` 冲突检测发生在**发布执行阶段**（第 6 步），
//  它只能挡住「发布瞬间的并发」，挡不住「更早创建的草稿已经落后」。
//  所以要在草稿上冻结基线，并在提交前核对。
//
//  ## 本文件不做的事
//
//  · **不读网络**。线上当前是什么版本只有受控发布器能读到（s2s key 不进 App），
//    所以本文件只定义「基线长什么样」「拿一个线上发布头怎么判定」这两件纯逻辑；
//  · **不自动把「读到的线上头」当基线写回**。那等于替运营声明
//    「我的草稿一定基于最新线上」，正是要避免的假话 —— 写回由调用方
//    （Mac 的运营操作 / 受控发布器的回填）显式决定。
//

import Foundation

// MARK: - 基线

/// 草稿冻结下来的发布基线。全字段可选：旧草稿没有这些信息是**正常状态**
/// （`isKnown == false`），不能被当成「基线是 0」。
public nonisolated struct ShopCatalogBaseline: Codable, Equatable, Sendable {

    /// 线上发布号。nil = 未知（旧草稿 / 从未与线上核对过）。
    public var releaseSeq: Int?
    /// 线上根清单摘要（64 位小写 hex）。nil = 未知。
    public var rootIndexHash: String?
    /// 该基线来自哪个环境（`development` / `production`）。
    /// **必须记录**：拿 Development 的基线去核对 Production 是必然误判。
    public var environment: String?
    /// 基线被记录 / 核对的时刻（审计用）。
    public var observedAt: Date?

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        releaseSeq: Int? = nil,
        rootIndexHash: String? = nil,
        environment: String? = nil,
        observedAt: Date? = nil
    ) {
        self.releaseSeq = releaseSeq
        self.rootIndexHash = rootIndexHash
        self.environment = environment
        self.observedAt = observedAt
    }

    /// 是否有可用的基线信息（只填一个也算：发布号或摘要任一即可参与核对）。
    public var isKnown: Bool {
        if releaseSeq != nil { return true }
        return !(rootIndexHash ?? "").isEmpty
    }

    public var isEmpty: Bool { !isKnown }

    /// 与线上发布头是否一致。摘要缺失时只比发布号（旧草稿形态）。
    ///
    /// ⚠️ **两边任一侧没有摘要时只比发布号**，而不是判「摘要变了」：
    /// 受控发布器读发布头时可能只拿得到发布号（`fetch_current_release` 不一定
    /// 回吐 `rootIndexHash`）。把「读不到」当成「不一致」会把每一次正常发布
    /// 都误判成基线过期，运营就会学会忽略这个提示 —— 那比不提示更糟。
    public func matches(_ head: ShopCatalogOnlineHead) -> Bool {
        guard let releaseSeq else { return false }
        guard releaseSeq == head.releaseSeq else { return false }
        guard let rootIndexHash, !rootIndexHash.isEmpty else { return true }
        guard let onlineHash = head.rootIndexHash, !onlineHash.isEmpty else { return true }
        return rootIndexHash == onlineHash
    }

    /// 一句话描述（界面直接显示，不含「已核对」这类幻觉措辞）。
    public var displayText: String {
        guard isKnown else { return "未知（从未与线上核对）" }
        let seq = releaseSeq.map { "releaseSeq \($0)" } ?? "releaseSeq 未知"
        let hash = (rootIndexHash?.isEmpty == false)
            ? String(rootIndexHash!.prefix(12)) + "…"
            : "摘要未知"
        let env = environment.map { " @\($0)" } ?? ""
        return "\(seq) · \(hash)\(env)"
    }
}

// MARK: - 线上发布头（由受控发布器读取后回填）

/// 线上当前的发布头快照。**只能由受控发布器产出** ——
/// Mac App 自己不直连公共库（私钥不进 App，见 `PinkHouseOpsApp` 文件头）。
public nonisolated struct ShopCatalogOnlineHead: Codable, Equatable, Sendable {

    public var environment: String
    public var releaseSeq: Int
    /// 线上根清单摘要。**nil = 没读到**（`fetch_current_release` 不保证回吐这个字段），
    /// 与「读到了但为空」都要与「摘要一致」区分开 —— 见 `hasRootIndexHash`。
    public var rootIndexHash: String?
    /// 线上发布头的 `publishedAt` 原文字符串（协议里就是字符串，不做本地解析）。
    public var publishedAt: String?
    /// 本次读取发生的时刻。
    public var observedAt: Date

    // 跨模块构造入口（同 `ShopCatalogBaseline`）。
    public init(
        environment: String,
        releaseSeq: Int,
        rootIndexHash: String? = nil,
        publishedAt: String? = nil,
        observedAt: Date = Date()
    ) {
        self.environment = environment
        self.releaseSeq = releaseSeq
        self.rootIndexHash = rootIndexHash
        self.publishedAt = publishedAt
        self.observedAt = observedAt
    }

    /// 线上尚无商店发布头时的占位（`releaseSeq = 0`）。
    ///
    /// 与「没读到」必须区分：**没读到**是未知（不能据此说可以覆盖），
    /// **读到了 0** 才是「线上确实还没发过」。
    public var isFirstRelease: Bool { releaseSeq <= 0 }

    /// 本次读取**拿到了**摘要。false = 摘要没读到，本轮只能比发布号，
    /// 界面上不能写「摘要一致」。
    public var hasRootIndexHash: Bool {
        !(rootIndexHash ?? "").isEmpty
    }

    public var hashText: String {
        guard let rootIndexHash, !rootIndexHash.isEmpty else { return "摘要未读到" }
        return String(rootIndexHash.prefix(12)) + "…"
    }
}

// MARK: - 判定

/// 基线核对结论。
public nonisolated enum ShopCatalogBaselineVerdict: Equatable, Sendable {
    /// 没读到线上发布头（未接桥 / 网络失败 / 没权限）——**不能据此声称基线没问题**。
    case unverified(reason: String)
    /// 基线就是线上当前版本（或线上尚无内容且基线为空）。
    case current(head: ShopCatalogOnlineHead?)
    /// 线上已经前进：直接覆盖会抹掉别人的改动。
    case stale(head: ShopCatalogOnlineHead, reasons: [String])

    /// 是否阻断提交（`unverified` 不阻断，但必须由运营显式确认后才允许提交）。
    public var isBlocking: Bool {
        if case .stale = self { return true }
        return false
    }

    /// 是否已经真的核对过（`false` = 界面不得显示「基线已核对」）。
    public var isVerified: Bool {
        switch self {
        case .current, .stale: return true
        case .unverified: return false
        }
    }

    public var displayName: String {
        switch self {
        case .unverified: return "基线未核对"
        case .current: return "基线与线上一致"
        case .stale: return "基线已过期"
        }
    }

    /// 处置建议（不允许只给一个红点）。
    public var guidance: String {
        switch self {
        case .unverified(let reason):
            return "读不到线上发布头（\(reason)）。本页**不会**替你声称基线已核对；"
                + "要么先接通受控发布器读取，要么由你显式确认「没有其他人先发过」后再提交。"
        case .current(let head):
            if let head, head.isFirstRelease {
                return "线上尚无商店内容，这份草稿将作为首次发布。"
            }
            if let head, !head.hasRootIndexHash {
                // 说清「比到了哪一步」，不把「只比了发布号」说成「已核对」。
                return "线上版本号（releaseSeq \(head.releaseSeq)）与这份草稿的基线一致。"
                    + "本次没读到线上根清单摘要，所以只比了发布号。"
            }
            return "线上版本与这份草稿的基线一致，可以提交。"
        case .stale(_, let reasons):
            return "线上已经前进（\(reasons.joined(separator: "；"))）。"
                + "直接覆盖会抹掉别人后来的改动：请先合并对方的改动并重新确认，不要靠把发布号加一继续覆盖。"
        }
    }
}

// MARK: - 判定器

public nonisolated enum ShopCatalogBaselineResolver {

    /// 拿草稿基线与一个线上发布头比对。
    ///
    /// - Parameter head: nil = **没读到**（不是「读到空」）。读到空用
    ///   `ShopCatalogOnlineHead(releaseSeq: 0, …)` 表达。
    public static func verdict(
        baseline: ShopCatalogBaseline,
        head: ShopCatalogOnlineHead?
    ) -> ShopCatalogBaselineVerdict {
        guard let head else {
            return .unverified(reason: "未读取到线上发布头")
        }

        // 环境对不上：拿 Development 的基线核对 Production 是必然误判，
        // 这不是「过期」而是「读错了地方」，必须说清楚。
        if let env = baseline.environment, !env.isEmpty, env != head.environment {
            return .stale(head: head, reasons: [
                "基线来自 \(env) 环境，而本次读取的是 \(head.environment) 环境，两者不可比",
            ])
        }

        guard baseline.isKnown else {
            // 线上还没有内容 → 这份草稿天然就是基线（首次发布）。
            if head.isFirstRelease { return .current(head: head) }
            // 线上已经有内容，而草稿连基线都没记 → 我们无法判断它基于哪一版。
            return .unverified(reason: "这份草稿没有记录基线，线上已有 releaseSeq \(head.releaseSeq)")
        }

        if baseline.matches(head) { return .current(head: head) }

        var reasons: [String] = []
        if let seq = baseline.releaseSeq {
            if head.releaseSeq > seq {
                reasons.append("线上 releaseSeq \(head.releaseSeq) 高于草稿基线 \(seq)")
            } else if head.releaseSeq < seq {
                reasons.append("草稿基线 releaseSeq \(seq) 高于线上 \(head.releaseSeq)（可能读错环境或基线被污染）")
            }
        } else {
            reasons.append("草稿没有记录基线发布号")
        }
        // 只有**两侧都读到摘要**才谈得上「摘要变了」。
        // 线上摘要没读到时把它算成差异，等于把「读不到」伪装成「不一致」。
        if let hash = baseline.rootIndexHash, !hash.isEmpty,
           let onlineHash = head.rootIndexHash, !onlineHash.isEmpty, hash != onlineHash {
            reasons.append("线上根清单摘要已变化")
        }
        if reasons.isEmpty { reasons.append("基线与线上发布头不一致") }
        return .stale(head: head, reasons: reasons)
    }
}
