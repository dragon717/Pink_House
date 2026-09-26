//
//  ShopCatalogStrictPolicy.swift
//  SharedCatalog
//
//  发布引用校验的两种策略（方案 R08）。
//
//  ## 为什么不能只有一种
//
//  现有门禁是「兼容读」口径：把符合形式的 `mediaKey` / `thmedia:` 引用视为
//  **已远端化**，把悬空 asset id / 裸名字降级成**告警**而不是阻断。
//  这对**存量旧数据**是必须的 —— 一刀切阻断会把已经在线上跑了几个月的目录
//  全部标红（无法与 App 内置资源文件名区分，会误伤）。
//
//  但它对**本次新创建 / 修改的内容**是错的：新内容引用的东西我们自己说了算，
//  一个「长得像哈希」的字符串不证明远端真有那份字节。方案 §2 的原话是
//  「合法 hash 但远端无文件被阻断」「Development 有图而 Production 无图不能误判已上传」。
//
//  ## 作用域为什么是「被改动的实体」而不是「整个目录」
//
//  严格策略只作用于**本次动过**的实体（`ShopCatalogChangeSet.strictScopeIDs`，
//  来自本地变更追踪 + 与基线的差分）。这样：
//    · 新建的商品必须图片可解析；
//    · 顺手修的一处文案不会因为隔壁一个 2019 年的老商品用了裸文件名而被卡住。
//
//  ## 离线能判到哪一步（说清楚边界，不假绿）
//
//  本机**离线**能判的：引用的形态能不能解析出「一个本机文件 / 一个远端键」。
//  本机**离线判不了**的：那个远端键在目标环境里**是不是真的有那份字节**。
//  后者只能由受控发布器在第 5 步「回读核对资源」时做，并把结论回传。
//  所以严格模式下「远端键未经回读确认」是**告警 + 明确文案**，
//  而不是本机假装阻断（假装阻断会让运营去点一个永远不会通过的按钮）。
//

import Foundation

// MARK: - 策略

public nonisolated enum ShopCatalogStrictPolicy: String, Codable, CaseIterable, Sendable {

    /// 兼容策略（默认）：无法核对的引用只告警。
    /// 用于**存量旧数据**，改动前行为完全不变。
    case compatibility

    /// 严格策略：**本次新增 / 修改**的实体里，无法解析的引用一律阻断。
    case strict

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compatibility: return "兼容策略"
        case .strict: return "严格策略（推荐）"
        }
    }

    public var guidance: String {
        switch self {
        case .compatibility:
            return "与旧版本一致：悬空引用与裸名字只提示、不阻断。存量目录不会被标红。"
        case .strict:
            return "本次新增 / 修改的内容里，无法解析的图片引用（裸名字、悬空资源、外部地址）"
                + "一律阻断发布；已经远端化但**未在本目标环境回读确认**的媒体键会单独列出提示。"
        }
    }

    /// 是否把「无法核对的引用」升级为阻断
    public var blocksUnverifiableReferences: Bool { self == .strict }
}

// MARK: - 严格策略的统计（界面用）

/// 严格策略在本次校验里的作用结果。界面据此解释「为什么这一条被阻断」。
public nonisolated struct ShopCatalogStrictAudit: Equatable, Sendable {

    public var policy: ShopCatalogStrictPolicy
    /// 本次作用域覆盖的实体 id 数（0 = 严格策略实际上没有生效对象）
    public var scopeEntityCount: Int
    /// 未被回读确认的媒体键（远端化形式，但目标环境尚未验证）
    public var unverifiedMediaKeys: [String]
    /// 被升级为阻断的引用条数
    public var blockedReferenceCount: Int

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        policy: ShopCatalogStrictPolicy,
        scopeEntityCount: Int = 0,
        unverifiedMediaKeys: [String] = [],
        blockedReferenceCount: Int = 0
    ) {
        self.policy = policy
        self.scopeEntityCount = scopeEntityCount
        self.unverifiedMediaKeys = unverifiedMediaKeys
        self.blockedReferenceCount = blockedReferenceCount
    }

    /// 作用域说明（严格模式下必须显示，否则运营会以为「严格策略没生效」）
    public var scopeText: String {
        switch policy {
        case .compatibility:
            return "兼容策略：所有引用按旧口径判定。"
        case .strict:
            if scopeEntityCount == 0 {
                return "严格策略：本次没有新增 / 修改过任何内容，所以没有额外收紧对象。"
            }
            return "严格策略：本次收紧 \(scopeEntityCount) 个新增 / 修改过的实体上的图片引用。"
        }
    }
}
