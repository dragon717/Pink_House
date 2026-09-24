//
//  ShopCatalogFormSnapshotStore.swift
//  ItemManager
//
//  运营端表单「编辑中快照」的唯一落盘口径 —— 修「离开页面再回来，没保存的输入全没了」。
//
//  ## 事故形态（2026-09-24）
//
//  批次详情页（一站式系列配置）、系列编辑页、补录草稿编辑器三处的表单值都放在 `@State`
//  里。用户切后台 / 跳系统相册选图 / 切到别的应用再回来，**之前填写的全部内容消失，
//  页面被重置成初始状态**，必须从头再填一遍。
//
//  ## 为什么加 `loaded` 守卫挡不住（上一轮修复失效的原因）
//
//  上一轮已定位到「这三个场景会重新触发 `onAppear`」，于是加了一次性回填守卫：
//
//      .onAppear { guard !loaded else { return }; loaded = true; …回填… }
//
//  但 `loaded` **本身就是 `@State`**。真正出问题的不是「`onAppear` 被多触发一次」，
//  而是**承载它的视图被重建了** —— 视图一重建，`loaded` 跟着归零，守卫直接失效，
//  表单被存储值重新回填（用户看到的正是「表单被重置」）。
//
//  视图为什么会重建：这三页都用 `.sheet` 呈现，而 sheet 修饰符挂在了 `ForEach` 的
//  **行视图**上（`batchRow` / `ShopCatalogDraftEditorRow` / `SeriesManageRow`）。
//  `Form` 底层是惰性、可复用的列表，行身份一旦变化或列表重新布局，行视图连同它承载的
//  sheet 内容视图一起重建，`@State` 与 `.onAppear` 守卫同时归零。
//
//  ## 两层修复
//
//  1. **消除重建诱因**（结构）：`.sheet` 从行视图提到稳定容器上，只挂一次。
//  2. **状态不依赖视图生命周期**（兜底）：本文件 —— 与 `ClothingEditView` 的
//     `persistCurrentStateForLifecycle` 同源：**在页面不可见前把「用户没提交的输入」
//     原样落盘；视图重建后自动恢复。** 不做定时任务，不做后台常驻。
//
//  ## 三条硬口径
//
//  · **只存未提交的输入**：`load` 出来先比对实体标识（批次 id / 草稿 id / 系列 id），
//    标识不符一律丢弃 —— 否则会「把 A 页面填的东西恢复进 B 页面」；
//  · **提交成功必须清**：保存成功后 `commit`，否则关页时会把已保存的内容又存成
//    「未保存的编辑」，下次进页面恢复出旧值；
//  · **读写失败不致命**：快照是兜底。编码失败 / 写盘失败 / 坏文件一律当作「没有快照」，
//    绝不能因为快照问题挡住用户正常录入。
//

import Foundation

// MARK: - 存储层

nonisolated enum ShopCatalogFormSnapshotStore {

    /// 快照目录：与草稿 / 覆盖层同级，便于统一排查与清理
    private static var directoryURL: URL {
        let dir = ShopCatalogStorage.directory.appendingPathComponent("form-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 单个页面的快照文件位置。
    ///
    /// 作用域里带实体 id，可能含 `/` 等路径字符 —— 先按文件名白名单替换，再补一个稳定
    /// 哈希后缀，避免「不同 id 被擦成同一个名字」而互相串页。
    static func fileURL(scope: String) -> URL {
        let allowed = CharacterSet(charactersIn:
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_.")
        let sanitized = String(scope.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let clipped = String(sanitized.suffix(60))
        return directoryURL.appendingPathComponent("\(clipped)-\(stableHash(scope)).json")
    }

    static func save<T: Encodable>(_ value: T, scope: String) {
        guard let data = try? ShopCatalogJSONCoding.encoder().encode(value) else { return }
        try? data.write(to: fileURL(scope: scope), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, scope: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(scope: scope)) else { return nil }
        return try? ShopCatalogJSONCoding.decoder().decode(type, from: data)
    }

    static func clear(scope: String) {
        try? FileManager.default.removeItem(at: fileURL(scope: scope))
    }

    /// 清掉全部快照（排查 / 重置用；不涉及草稿与覆盖层）
    static func clearAll() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    /// 稳定哈希（FNV-1a 64bit）：只用来避免文件名撞车，不做任何安全用途。
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

// MARK: - 页面侧快照管家

/// 页面侧的快照管家：把「防抖落盘 / 立即落盘 / 提交清理 / 自动恢复」收在一处。
///
/// 三个表单页共用同一份实现 —— 各页各写一套，必然有一套漏掉某个生命周期节点，
/// 而漏掉的那个节点就会变成下一次「内容全没了」的事故。
///
/// 用法（放在 `@State` 里，`Snapshot` 是一个只含可编码字段的纯值类型）：
///
///     @State private var keeper = ShopCatalogFormSnapshotKeeper<FooSnapshot>(scope: …)
///
///     // 首次出现：先按存储值填默认态，再用快照覆盖成「未提交的编辑」
///     .onAppear { applyDefaults(); keeper.restoreOrDiscard(defaults: makeSnapshot(), apply: apply) }
///
///     // 三处生命周期 + 变更防抖
///     .onChange(of: scenePhase) { _, phase in if phase != .active { keeper.flush(makeSnapshot()) } }
///     .onReceive(NotificationCenter.default.publisher(for: .didEnterBackgroundNotification)) { _ in keeper.flush(makeSnapshot()) }
///     .onDisappear { keeper.flush(makeSnapshot()) }
///     .onChange(of: makeSnapshot()) { _, s in keeper.schedule(s) }
///
///     // 保存成功
///     keeper.commit(makeSnapshot())
///
@MainActor
struct ShopCatalogFormSnapshotKeeper<Snapshot: Codable & Equatable> {

    /// 页面作用域（含实体 id）：不同页面 / 不同实体互不串页。
    ///
    /// 用 `var` 是因为实体 id 常常来自视图的 `let` 参数，而 `@State` 的属性初始化式
    /// 读不到同级的其它属性 —— 由页面在 `onAppear` 里赋值一次。
    /// 未赋值（空串）时所有落盘 / 读取一律跳过，绝不写到一个「共用文件」上。
    var scope: String

    /// 是否刚从快照恢复出「未提交的编辑」——驱动页面上的提示条
    private(set) var didRestore = false

    /// 防抖任务
    private var pending: Task<Void, Never>?

    /// 最近一次**已提交**（保存成功）的表单内容。承担两件事：
    ///   ① 关页时不再把「已保存的内容」当成未保存编辑又写回去；
    ///   ② 不留过期快照，下次进页面不会恢复出旧值。
    private var committed: Snapshot?

    init(scope: String) {
        self.scope = scope
    }

    // MARK: 恢复

    /// 用快照恢复未提交的编辑。
    ///
    /// `defaults` = 按存储值填出来的「默认态」：
    ///   · 没有快照 → 什么都不做（页面保持默认态）；
    ///   · 快照与默认态**逐字段相同** → 上次其实没改什么，直接清掉 —— 既不留垃圾，
    ///     也不会让下次进页面弹出一条无意义的「已恢复」提示；
    ///   · 有差异 → 恢复，并把 `didRestore` 置真。
    mutating func restoreOrDiscard(defaults defaultValue: Snapshot, apply: (Snapshot) -> Void) {
        guard !scope.isEmpty else { return }
        guard let stored = ShopCatalogFormSnapshotStore.load(Snapshot.self, scope: scope) else { return }
        guard stored != defaultValue else {
            ShopCatalogFormSnapshotStore.clear(scope: scope)
            return
        }
        apply(stored)
        didRestore = true
    }

    /// 用户主动放弃恢复：清掉快照并（由调用方）回到默认态
    mutating func discard() {
        pending?.cancel()
        pending = nil
        ShopCatalogFormSnapshotStore.clear(scope: scope)
        didRestore = false
    }

    /// 提示条已读（用户点了「知道了」，但接受恢复出来的内容）
    mutating func markRestoreAcknowledged() {
        didRestore = false
    }

    // MARK: 落盘

    /// 变更后防抖落盘（0.5s）。
    ///
    /// 防抖不只是省 IO —— **跳系统相册时页面不会走 `onDisappear`**，真正兜住
    /// 「选完图回来表单已经重建」的，就是这层「改一下就存一下」。
    mutating func schedule(_ snapshot: Snapshot) {
        pending?.cancel()
        guard !scope.isEmpty else { return }
        let scope = scope
        let committed = committed
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard snapshot != committed else { return }
            ShopCatalogFormSnapshotStore.save(snapshot, scope: scope)
        }
    }

    /// 立即落盘（切后台 / 失活 / 关页）。与已提交内容一致 → 只清不留。
    mutating func flush(_ snapshot: Snapshot) {
        pending?.cancel()
        pending = nil
        guard !scope.isEmpty else { return }
        guard snapshot != committed else {
            ShopCatalogFormSnapshotStore.clear(scope: scope)
            return
        }
        ShopCatalogFormSnapshotStore.save(snapshot, scope: scope)
    }

    /// 保存成功：记住「这就是已提交的内容」并清掉快照。
    mutating func commit(_ snapshot: Snapshot) {
        pending?.cancel()
        pending = nil
        committed = snapshot
        didRestore = false
        ShopCatalogFormSnapshotStore.clear(scope: scope)
    }
}

// MARK: - 各页面的快照载荷

/// 批次详情页（整批归属 + 一站式系列配置）的编辑中快照。
///
/// `batchID` 是**归属判定**：只对同一个批次有效。换批次 / 换行一律丢弃，
/// 否则会出现「把 A 批次填的店家和系列恢复进 B 批次」。
struct ShopCatalogBatchConfigSnapshot: Codable, Equatable {
    var batchID: String

    // 整批归属
    var shopID: String
    var newShopName: String
    var newShopAliases: String
    var seriesID: String
    var newSeriesName: String
    var newSeriesYearMonthText: String
    var newSeriesSeason: String

    // 系列级三项配置（发售阶段 / 图文 / 价格表）
    var configFormSeriesID: String?
    var config: ShopCatalogSeriesConfigForm
}

/// 补录草稿编辑器（款式 + 多颜色一体化录入）的编辑中快照。
///
/// `sourceDraftID` 是归属判定：只恢复进同一条源草稿的编辑器。
struct ShopCatalogDraftFormSnapshot: Codable, Equatable {
    var sourceDraftID: String

    var designNameText: String
    var categoryText: String
    var fabricText: String
    var styleDescriptionText: String
    var chartColumnsText: String
    var chartRowsText: String
    var chartUnit: String
    var chartImageText: String
    var newSeriesYearMonthText: String
    var reservationPriceText: String
    var stockPriceText: String
    var depositText: String
    var currency: CatalogCurrency?
    /// 颜色行（含每色的配色图引用）——「已选封面图 / 配色图」就靠它一起保住
    var colors: [ShopCatalogDraftStyleForm.ColorRow]
}

/// 系列编辑页（基础信息 + 三项系列配置）的编辑中快照。
///
/// `seriesID` 是归属判定：只恢复进同一条系列的编辑页。
struct ShopCatalogSeriesEditSnapshot: Codable, Equatable {
    var seriesID: String

    var name: String
    var yearMonthText: String
    var season: String
    var config: ShopCatalogSeriesConfigForm
}
