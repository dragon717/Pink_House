import XCTest

@testable import ItemManager

/// 时光馆「静态发布 + CloudKit 只读 + 本地缓存」协议的回归测试。
///
/// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md：
///   §4.4 发布号与撤回版本单调性 / §5.2 覆盖状态语义 / §6.7 关联完整性
///   §11.5 版本优先合并 / §12.3 下载安全 / §13.3 清理竞态 / §14.1 撤回优先
///   §18.1 验收点 D07–D12
final class TimeHallPublicationProtocolTests: XCTestCase {

  // MARK: - 规范实体 ID（§6.5：沿用现有 DTO 的 id，旧收藏无需迁移）

  func testCanonicalEntityIDRoundTrip() {
    let id = TimeHallCanonicalID.make(
      brandID: "pink-house", entityType: .commerceProduct, stableSourceID: "p-1001")
    XCTAssertEqual(id, "pink-house/commerce-product/p-1001")
    XCTAssertTrue(TimeHallCanonicalID.isValid(id))
    XCTAssertEqual(TimeHallCanonicalID.brandID(from: id), "pink-house")
    XCTAssertEqual(TimeHallCanonicalID.entityType(from: id), .commerceProduct)
  }

  func testCanonicalEntityIDRejectsMalformedValues() {
    // 段数不对
    XCTAssertFalse(TimeHallCanonicalID.isValid("pink-house/event"))
    XCTAssertFalse(TimeHallCanonicalID.isValid("pink-house/event/a/b"))
    // 空段
    XCTAssertFalse(TimeHallCanonicalID.isValid("pink-house//x"))
    XCTAssertFalse(TimeHallCanonicalID.isValid("/event/x"))
    // 未知实体类型
    XCTAssertFalse(TimeHallCanonicalID.isValid("pink-house/unknown-type/x"))
    // 非法值不得推出品牌
    XCTAssertNil(TimeHallCanonicalID.brandID(from: "broken"))
    XCTAssertNil(TimeHallCanonicalID.entityType(from: "broken"))
  }

  // MARK: - 覆盖状态语义（§5.2：partial/unknown 不是结论；withdrawn 不得展示）

  func testCoverageStatusConclusiveness() {
    XCTAssertTrue(TimeHallCoverageStatus.complete.isConclusive)
    XCTAssertTrue(TimeHallCoverageStatus.empty.isConclusive)
    XCTAssertTrue(TimeHallCoverageStatus.notSupported.isConclusive)
    XCTAssertTrue(TimeHallCoverageStatus.withdrawn.isConclusive)
    // 资料不完整与尚未检查都不能被当成「就是没有」
    XCTAssertFalse(TimeHallCoverageStatus.partial.isConclusive)
    XCTAssertFalse(TimeHallCoverageStatus.unknown.isConclusive)
  }

  func testWithdrawnAndUnsupportedAreNotDisplayable() {
    XCTAssertFalse(TimeHallCoverageStatus.withdrawn.allowsDisplay)
    XCTAssertFalse(TimeHallCoverageStatus.notSupported.allowsDisplay)
    for status in [
      TimeHallCoverageStatus.complete, .empty, .partial, .unknown,
    ] {
      XCTAssertTrue(status.allowsDisplay, status.rawValue)
    }
  }

  // MARK: - 发布头新旧判断（§4.4：不能只看日期）

  func testReleaseSupersedesPrefersReleaseSeqThenRevocationEpoch() {
    let base = makeRelease(seq: 5, revocationEpoch: 1)
    XCTAssertTrue(makeRelease(seq: 6, revocationEpoch: 0).supersedes(base))
    XCTAssertFalse(makeRelease(seq: 4, revocationEpoch: 99).supersedes(base))
    // 同一发布号内，撤回版本更高视为更新
    XCTAssertTrue(makeRelease(seq: 5, revocationEpoch: 2).supersedes(base))
    XCTAssertFalse(makeRelease(seq: 5, revocationEpoch: 1).supersedes(base))
    // 没有已知发布时，任何发布都是新的
    XCTAssertTrue(base.supersedes(nil))
  }

  func testReleaseReadabilityFollowsMinimumReaderVersion() {
    XCTAssertTrue(makeRelease(seq: 1, minimumReaderVersion: TimeHallProtocol.readerVersion)
      .isReadableByCurrentClient)
    XCTAssertTrue(makeRelease(seq: 1, minimumReaderVersion: 1).isReadableByCurrentClient)
    // 更高读取协议必须被识别为「需要新版 App」，而不是静默失败
    XCTAssertFalse(
      makeRelease(seq: 1, minimumReaderVersion: TimeHallProtocol.readerVersion + 1)
        .isReadableByCurrentClient)
  }

  // MARK: - 撤回优先（§14.1）

  func testFilteringWithdrawnRemovesEntityAndKeepsOthers() {
    let fragment = TimeHallCatalogFragmentDTO(events: [
      makeEvent("e-1"), makeEvent("e-2"), makeEvent("e-3"),
    ])
    let withdrawn: Set<String> = [
      TimeHallCanonicalID.make(brandID: "pink-house", entityType: .event, stableSourceID: "e-2")
    ]
    let filtered = fragment.filteringWithdrawn(canonicalIDs: withdrawn, brandID: "pink-house")
    XCTAssertEqual(filtered.events.map(\.id), ["e-1", "e-3"])
  }

  func testFilteringWithdrawnIsScopedPerBrand() {
    let fragment = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    // 同 ID 但属于别的品牌：不得误删
    let otherBrandWithdrawal: Set<String> = [
      TimeHallCanonicalID.make(
        brandID: "angelic-pretty", entityType: .event, stableSourceID: "e-1")
    ]
    let filtered = fragment.filteringWithdrawn(
      canonicalIDs: otherBrandWithdrawal, brandID: "pink-house")
    XCTAssertEqual(filtered.events.count, 1)
  }

  func testFilteringWithdrawnWithEmptySetIsIdentity() {
    let fragment = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    let filtered = fragment.filteringWithdrawn(canonicalIDs: [], brandID: "pink-house")
    XCTAssertEqual(filtered.events.count, 1)
  }

  // MARK: - 分片合并（§11.5：更新版本优先）

  func testFragmentMergeDeduplicatesById() {
    var first = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1"), makeEvent("e-2")])
    let second = TimeHallCatalogFragmentDTO(events: [makeEvent("e-2"), makeEvent("e-3")])
    first.merge(second)
    XCTAssertEqual(first.events.map(\.id), ["e-1", "e-2", "e-3"])
  }

  func testReplacingPrefersLaterRevisionForSameEntity() {
    let earlier = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1", title: "旧标题")])
    let later = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1", title: "新标题")])
    let merged = later.replacing(earlier)
    XCTAssertEqual(merged.events.count, 1)
    XCTAssertEqual(merged.events.first?.title, "新标题")
  }

  func testReplacingKeepsEntriesOnlyPresentInEarlierSnapshot() {
    let earlier = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1"), makeEvent("e-2")])
    let later = TimeHallCatalogFragmentDTO(events: [makeEvent("e-2")])
    let merged = later.replacing(earlier)
    XCTAssertEqual(Set(merged.events.map(\.id)), ["e-1", "e-2"])
  }

  // MARK: - 控制状态只增不减（§13.3 步骤 7）

  func testControlStateMergingNeverShrinksWithdrawals() {
    let current = TimeHallControlState(
      revocationEpoch: 3,
      withdrawnEntityIDs: ["pink-house/event/e-1"],
      withdrawnMediaHashes: ["hash-a"],
      disabledBrandIDs: [],
      lastCheckedAt: nil,
      knownReleaseSeq: 7,
      knownRootIndexHash: "root-7"
    )
    let incoming = TimeHallControlState(
      revocationEpoch: 2,
      withdrawnEntityIDs: ["pink-house/event/e-2"],
      withdrawnMediaHashes: ["hash-b"],
      disabledBrandIDs: ["legacy-brand"],
      lastCheckedAt: Date(),
      knownReleaseSeq: 6,
      knownRootIndexHash: "root-6"
    )
    let merged = current.merging(incoming)
    XCTAssertEqual(merged.revocationEpoch, 3, "撤回版本不允许倒退")
    XCTAssertEqual(merged.withdrawnEntityIDs, [
      "pink-house/event/e-1", "pink-house/event/e-2",
    ])
    XCTAssertEqual(merged.withdrawnMediaHashes, ["hash-a", "hash-b"])
    XCTAssertEqual(merged.disabledBrandIDs, ["legacy-brand"])
    // 已知发布号不回退：更高才替换
    XCTAssertEqual(merged.knownReleaseSeq, 7)
    XCTAssertEqual(merged.knownRootIndexHash, "root-7")
  }

  func testControlStateMergingAcceptsNewerRelease() {
    let current = TimeHallControlState(
      revocationEpoch: 1, withdrawnEntityIDs: [], withdrawnMediaHashes: [],
      disabledBrandIDs: [], lastCheckedAt: nil,
      knownReleaseSeq: 2, knownRootIndexHash: "root-2"
    )
    let newer = TimeHallControlState(
      revocationEpoch: 1, withdrawnEntityIDs: [], withdrawnMediaHashes: [],
      disabledBrandIDs: [], lastCheckedAt: Date(),
      knownReleaseSeq: 3, knownRootIndexHash: "root-3"
    )
    let merged = current.merging(newer)
    XCTAssertEqual(merged.knownReleaseSeq, 3)
    XCTAssertEqual(merged.knownRootIndexHash, "root-3")
  }

  // MARK: - 分片 ID 安全（§12.3：不信任任何远端标识）

  func testPartitionIDRejectsPathTraversal() {
    XCTAssertTrue(TimeHallPartitionID.isSafe("pink-house/event/all"))
    XCTAssertTrue(TimeHallPartitionID.isSafe("pink-house/event/2026-09"))
    XCTAssertFalse(TimeHallPartitionID.isSafe(""))
    XCTAssertFalse(TimeHallPartitionID.isSafe("../../etc/passwd"))
    XCTAssertFalse(TimeHallPartitionID.isSafe("pink-house/event/.."))
    XCTAssertFalse(TimeHallPartitionID.isSafe("/pink-house/event/all"))
    XCTAssertFalse(TimeHallPartitionID.isSafe("pink-house/event/all/"))
    XCTAssertFalse(TimeHallPartitionID.isSafe("Pink-House/event/all"), "大写不在允许字符集内")
    XCTAssertFalse(TimeHallPartitionID.isSafe("pink-house/event/a b"))
  }

  func testPartitionIDFileNameComponentFlattensSeparators() {
    XCTAssertEqual(
      TimeHallPartitionID.fileNameComponent(for: "pink-house/event/all"),
      "pink-house_event_all"
    )
    XCTAssertFalse(TimeHallPartitionID.fileNameComponent(for: "a/b/c").contains("/"))
  }

  func testPartitionIDParsingMatchesBuilder() {
    let id = TimeHallPartitionID.make(
      brandID: "pink-house", entityType: .event, scopeKey: "all")
    XCTAssertEqual(id, "pink-house/event/all")
    XCTAssertEqual(TimeHallPartitionID.brandID(from: id), "pink-house")
    XCTAssertEqual(TimeHallPartitionID.entityType(from: id), .event)
    XCTAssertEqual(TimeHallPartitionID.scopeKey(from: id), "all")
    XCTAssertNil(TimeHallPartitionID.brandID(from: "too-short"))
  }

  func testMonthlyPartitionIDUsesBusinessMonth() {
    let id = TimeHallPartitionID.monthly(
      brandID: "pink-house", entityType: .event, dayKey: "2026-09-14")
    XCTAssertEqual(id, "pink-house/event/2026-09")
  }

  // MARK: - 请求去重键（§11.6：同分片并发合并）

  func testRequestDeduplicationKeyIgnoresEntityTypeOrder() {
    let a = TimeHallRequest(
      brandID: "pink-house", entityTypes: [.event, .item])
    let b = TimeHallRequest(
      brandID: "pink-house", entityTypes: [.item, .event])
    XCTAssertEqual(a.deduplicationKey, b.deduplicationKey)
  }

  func testRequestDeduplicationKeyDistinguishesBrandAndWindow() {
    let base = TimeHallRequest(brandID: "pink-house", entityTypes: [.event])
    let otherBrand = TimeHallRequest(brandID: "angelic-pretty", entityTypes: [.event])
    let windowed = TimeHallRequest(
      brandID: "pink-house", entityTypes: [.event], recentDayCount: 7)
    XCTAssertNotEqual(base.deduplicationKey, otherBrand.deduplicationKey)
    XCTAssertNotEqual(base.deduplicationKey, windowed.deduplicationKey)
  }

  // MARK: - 业务日历（§18.1 D08：跨月跨年由 Calendar 处理）

  func testRecentDayKeysCrossMonthBoundary() {
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let reference = TimeHallBusinessCalendar.date(fromDayKey: "2026-03-02", timeZone: tokyo)!
    let keys = TimeHallBusinessCalendar.recentDayKeys(
      referenceDate: reference, count: 3, timeZone: tokyo)
    XCTAssertEqual(keys, ["2026-03-02", "2026-03-01", "2026-02-28"])
  }

  func testRecentDayKeysRespectsSourceTimeZone() {
    let utc = TimeZone(identifier: "UTC")!
    // UTC 2026-01-01 00:30 在东京已是 09:30，同日；但 UTC 2025-12-31 23:30 在东京是 2026-01-01
    let lateUtc = TimeHallBusinessCalendar.date(fromDayKey: "2025-12-31", timeZone: utc)!
      .addingTimeInterval(23 * 3600 + 30 * 60)
    XCTAssertEqual(
      TimeHallBusinessCalendar.dayKey(for: lateUtc, timeZone: utc), "2025-12-31")
    XCTAssertEqual(
      TimeHallBusinessCalendar.dayKey(
        for: lateUtc, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026-01-01")
  }

  func testMonthKeyDerivation() {
    XCTAssertEqual(TimeHallBusinessCalendar.monthKey(for: "2026-09-14"), "2026-09")
    XCTAssertEqual(TimeHallBusinessCalendar.monthKey(for: "bad"), "bad")
  }

  // MARK: - 读取错误可重试判定

  func testRetryableErrorsAreClassifiedCorrectly() {
    for error in [TimeHallReadError.offline, .cloudUnavailable, .throttled, .packHashMismatch] {
      XCTAssertTrue(error.isRetryable, error.rawValue)
    }
    for error in [
      TimeHallReadError.permissionDenied, .releaseUnreadable, .releaseMissing,
      .rootIndexHashMismatch, .unsupportedSchema, .invalidIdentifier, .brandNotSupported,
      .cancelled,
    ] {
      XCTAssertFalse(error.isRetryable, error.rawValue)
    }
    // 每次错误都必须有面向用户的中文说明
    for error in TimeHallReadError.allCasesForTesting where error.labelZH.isEmpty {
      XCTFail("缺少中文说明：\(error.rawValue)")
    }
  }

  // MARK: - 第一/第二层校验（§1.2 B / §18.1 D09）

  func testStructuralValidationRejectsEmptyPackageCarryingRecords() {
    let fragment = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    let outcome = TimeHallPublicationValidator.validateStructural(
      fragment,
      declaredEntityType: .event,
      brandID: "pink-house",
      coverageStatus: .empty
    )
    XCTAssertFalse(outcome.isValid, "empty 覆盖状态不得携带条目")
    XCTAssertTrue(outcome.issues.contains { $0.code == "empty.notEmpty" })
  }

  func testStructuralValidationAcceptsConsistentFragment() {
    let fragment = TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    let outcome = TimeHallPublicationValidator.validateStructural(
      fragment,
      declaredEntityType: .event,
      brandID: "pink-house",
      coverageStatus: .partial
    )
    XCTAssertTrue(outcome.isValid, outcome.summary)
  }

  func testStructuralValidationRejectsEmptyBrandID() {
    let outcome = TimeHallPublicationValidator.validateStructural(
      TimeHallCatalogFragmentDTO(),
      declaredEntityType: nil,
      brandID: "",
      coverageStatus: .partial
    )
    XCTAssertFalse(outcome.isValid)
    XCTAssertTrue(outcome.issues.contains { $0.code == "brandID.empty" })
  }

  func testMergedFragmentValidationSkipsPartitionOnlyRule() {
    // 合并后的展示快照没有单一实体类型，不应因为「条目数」被分片级规则误判
    let merged = TimeHallCatalogFragmentDTO(items: [], events: [makeEvent("e-1")])
    let outcome = TimeHallPublicationValidator.validateMergedFragment(
      merged, brandID: "pink-house")
    XCTAssertTrue(outcome.isValid, outcome.summary)
  }

  func testPartitionValidationRejectsBrandSegmentMismatch() {
    let descriptor = makeDescriptor(
      partitionID: "angelic-pretty/event/all",
      brandID: "pink-house",
      entityType: .event
    )
    let payload = TimeHallPackPayload(
      partitionID: descriptor.partitionID,
      brandID: descriptor.brandID,
      entityType: descriptor.entityType,
      partitionRevision: descriptor.partitionRevision,
      coverageStatus: descriptor.coverageStatus,
      checkedThrough: nil,
      dayCoverage: [:],
      records: TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    )
    let outcome = TimeHallPublicationValidator.validatePartition(
      descriptor: descriptor,
      payload: payload,
      compressedBytes: 1_000,
      uncompressedBytes: 4_000
    )
    XCTAssertFalse(outcome.isValid)
    XCTAssertTrue(outcome.issues.contains { $0.code == "partitionID.brandMismatch" })
  }

  func testPartitionValidationRejectsUnsafePartitionID() {
    let descriptor = makeDescriptor(
      partitionID: "../escape/event",
      brandID: "pink-house",
      entityType: .event
    )
    let payload = TimeHallPackPayload(
      partitionID: descriptor.partitionID,
      brandID: descriptor.brandID,
      entityType: descriptor.entityType,
      partitionRevision: 1,
      coverageStatus: .partial,
      checkedThrough: nil,
      dayCoverage: [:],
      records: TimeHallCatalogFragmentDTO()
    )
    let outcome = TimeHallPublicationValidator.validatePartition(
      descriptor: descriptor, payload: payload,
      compressedBytes: 100, uncompressedBytes: 200)
    XCTAssertFalse(outcome.isValid)
    XCTAssertTrue(outcome.issues.contains { $0.code == "partitionID.unsafe" })
  }

  // MARK: - 根清单（§6.7）

  func testRootIndexLookupsAndWithdrawalProjection() {
    let descriptor = makeDescriptor(
      partitionID: "pink-house/event/all", brandID: "pink-house", entityType: .event)
    let withdrawal = TimeHallWithdrawal(
      canonicalEntityID: TimeHallCanonicalID.make(
        brandID: "pink-house", entityType: .event, stableSourceID: "e-9"),
      withdrawnAt: "2026-09-01",
      mediaHashes: ["media-hash-1"]
    )
    let otherBrandWithdrawal = TimeHallWithdrawal(
      canonicalEntityID: TimeHallCanonicalID.make(
        brandID: "angelic-pretty", entityType: .event, stableSourceID: "e-1"),
      withdrawnAt: "2026-09-01"
    )
    let root = TimeHallRootIndex(
      releaseSeq: 4,
      publishedAt: "2026-09-14T00:00:00Z",
      revocationEpoch: 2,
      brands: [
        TimeHallBrandDescriptor(
          brandID: "pink-house",
          displayName: "PINK HOUSE",
          sourceTimeZone: "Asia/Tokyo",
          sourceCoverage: .currentlyEnumerable,
          coverageDescription: "官网当前仍可枚举"
        )
      ],
      partitions: [descriptor],
      withdrawals: [withdrawal, otherBrandWithdrawal]
    )

    XCTAssertEqual(root.brand("pink-house")?.displayName, "PINK HOUSE")
    XCTAssertNil(root.brand("missing"))
    XCTAssertEqual(root.partition(partitionID: "pink-house/event/all")?.entityType, .event)
    XCTAssertEqual(root.withdrawnEntityIDs().count, 2)
    XCTAssertEqual(root.withdrawnEntityIDs(brandID: "pink-house").count, 1)
    XCTAssertEqual(root.withdrawnMediaHashes(), ["media-hash-1"])
    XCTAssertEqual(
      root.partitions(brandID: "pink-house", entityTypes: [.event]).count, 1)
    XCTAssertTrue(
      root.partitions(brandID: "pink-house", entityTypes: [.item]).isEmpty)
    XCTAssertEqual(root.brand("pink-house")?.businessTimeZone.identifier, "Asia/Tokyo")
  }

  func testDescriptorDayCoverageLookup() {
    let descriptor = makeDescriptor(
      partitionID: "pink-house/event/all",
      brandID: "pink-house",
      entityType: .event,
      dayCoverage: ["2026-09-13": .empty, "2026-09-12": .complete]
    )
    XCTAssertEqual(descriptor.sortedDayKeys, ["2026-09-12", "2026-09-13"])
    XCTAssertEqual(descriptor.coverageStatus(forDay: "2026-09-13"), .empty)
    XCTAssertNil(descriptor.coverageStatus(forDay: "2026-09-01"))
  }

  // MARK: - 数据包负载自洽（§6.3）

  func testPackPayloadMatchesDescriptor() {
    let descriptor = makeDescriptor(
      partitionID: "pink-house/event/all", brandID: "pink-house", entityType: .event)
    let payload = TimeHallPackPayload(
      partitionID: descriptor.partitionID,
      brandID: descriptor.brandID,
      entityType: descriptor.entityType,
      partitionRevision: descriptor.partitionRevision,
      coverageStatus: descriptor.coverageStatus,
      checkedThrough: nil,
      dayCoverage: [:],
      records: TimeHallCatalogFragmentDTO()
    )
    XCTAssertTrue(payload.matches(descriptor))

    let mismatched = TimeHallPackPayload(
      partitionID: descriptor.partitionID,
      brandID: descriptor.brandID,
      entityType: descriptor.entityType,
      partitionRevision: descriptor.partitionRevision + 1,
      coverageStatus: descriptor.coverageStatus,
      checkedThrough: nil,
      dayCoverage: [:],
      records: TimeHallCatalogFragmentDTO()
    )
    XCTAssertFalse(mismatched.matches(descriptor))
  }

  // MARK: - 数据包缓存与清理竞态（§13.3）

  func testPackCacheInstallsReadsBackAndPersistsAcrossInstances() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = TimeHallCacheLayout.testing(at: root)

    let cache = TimeHallPackCache(layout: layout)
    let generation = await cache.currentGeneration()
    let descriptor = makeDescriptor(
      partitionID: "pink-house/event/all", brandID: "pink-house", entityType: .event)
    let payload = TimeHallPackPayload(
      partitionID: descriptor.partitionID,
      brandID: descriptor.brandID,
      entityType: descriptor.entityType,
      partitionRevision: descriptor.partitionRevision,
      coverageStatus: .partial,
      checkedThrough: "2026-09-13T00:00:00Z",
      dayCoverage: ["2026-09-13": .complete],
      records: TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    )

    let installed = try await cache.install(
      descriptor: descriptor, payload: payload, generation: generation)
    XCTAssertEqual(installed.partitionID, descriptor.partitionID)
    XCTAssertEqual(installed.generation, generation)
    XCTAssertEqual(installed.recordCount, descriptor.recordCount)
    let fragment = try await cache.fragment(partitionID: descriptor.partitionID)
    XCTAssertEqual(fragment?.events.map(\.id), ["e-1"])
    let isInstalled = await cache.isInstalled(partitionID: descriptor.partitionID)
    XCTAssertTrue(isInstalled)

    let usage = await cache.usage()
    XCTAssertEqual(usage.packCount, 1)
    XCTAssertGreaterThan(usage.packBytes, 0)

    // 新实例应从索引恢复，而不是依赖内存状态
    let reopened = TimeHallPackCache(layout: layout)
    let reopenedInstalled = await reopened.isInstalled(partitionID: descriptor.partitionID)
    XCTAssertTrue(reopenedInstalled)
    let reopenedFragment = try await reopened.fragment(partitionID: descriptor.partitionID)
    XCTAssertEqual(reopenedFragment?.events.map(\.id), ["e-1"])
  }

  func testPackCacheRejectsInstallFromStaleGeneration() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallPackCache(layout: TimeHallCacheLayout.testing(at: root))

    let staleGeneration = await cache.currentGeneration()
    try await cache.clearDownloadedContent()

    let descriptor = makeDescriptor(
      partitionID: "pink-house/event/all", brandID: "pink-house", entityType: .event)
    let payload = TimeHallPackPayload(
      partitionID: descriptor.partitionID,
      brandID: descriptor.brandID,
      entityType: descriptor.entityType,
      partitionRevision: 1,
      coverageStatus: .partial,
      checkedThrough: nil,
      dayCoverage: [:],
      records: TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
    )

    do {
      _ = try await cache.install(
        descriptor: descriptor, payload: payload, generation: staleGeneration)
      XCTFail("清理后旧 generation 的安装必须被拒绝，否则刚清空的缓存会被重新写满")
    } catch let error as TimeHallCacheError {
      XCTAssertEqual(error, .staleGeneration)
    }
  }

  func testPackCacheClearDropsIndexKeepsGenerationMovingForward() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallPackCache(layout: TimeHallCacheLayout.testing(at: root))

    let generation = await cache.currentGeneration()
    let descriptor = makeDescriptor(
      partitionID: "pink-house/event/all", brandID: "pink-house", entityType: .event)
    _ = try await cache.install(
      descriptor: descriptor,
      payload: TimeHallPackPayload(
        partitionID: descriptor.partitionID,
        brandID: descriptor.brandID,
        entityType: descriptor.entityType,
        partitionRevision: 1,
        coverageStatus: .partial,
        checkedThrough: nil,
        dayCoverage: [:],
        records: TimeHallCatalogFragmentDTO(events: [makeEvent("e-1")])
      ),
      generation: generation
    )
    let installedBeforeClear = await cache.isInstalled(partitionID: descriptor.partitionID)
    XCTAssertTrue(installedBeforeClear)

    try await cache.clearDownloadedContent()

    let installedAfterClear = await cache.isInstalled(partitionID: descriptor.partitionID)
    XCTAssertFalse(installedAfterClear)
    let after = await cache.currentGeneration()
    XCTAssertGreaterThan(after, generation, "清理必须递增 generation")
    let usage = await cache.usage()
    XCTAssertEqual(usage.packCount, 0)
    XCTAssertEqual(usage.packBytes, 0)
  }

  func testPackCacheRejectsUnsafePartitionID() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallPackCache(layout: TimeHallCacheLayout.testing(at: root))
    let generation = await cache.currentGeneration()
    let descriptor = makeDescriptor(
      partitionID: "../../escape", brandID: "pink-house", entityType: .event)

    do {
      _ = try await cache.install(
        descriptor: descriptor,
        payload: TimeHallPackPayload(
          partitionID: descriptor.partitionID,
          brandID: descriptor.brandID,
          entityType: descriptor.entityType,
          partitionRevision: 1,
          coverageStatus: .partial,
          checkedThrough: nil,
          dayCoverage: [:],
          records: TimeHallCatalogFragmentDTO()
        ),
        generation: generation
      )
      XCTFail("非法分片 ID 必须被拒绝")
    } catch let error as TimeHallCacheError {
      XCTAssertEqual(error, .invalidIdentifier)
    }
  }

  // MARK: - 媒体缓存（§12.3）

  func testMediaCacheInstallsValidImageAndServesDownsampledCopy() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallMediaCache(layout: TimeHallCacheLayout.testing(at: root))

    let bytes = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))
    let media = TimeHallDownloadedMedia(
      recordName: "th.media.test",
      contentHash: TimeHallPackCodec.sha256Hex(bytes),
      mimeType: "image/png",
      bytes: bytes
    )
    let generation = await cache.currentGeneration()
    let record = try await cache.install(
      media: media, mediaKey: "pink-house/event/e-1#thumb", generation: generation)

    XCTAssertEqual(record.contentHash, media.contentHash)
    XCTAssertEqual(record.byteCount, bytes.count)
    let hasThumb = await cache.hasMedia(mediaKey: "pink-house/event/e-1#thumb")
    XCTAssertTrue(hasThumb)
    let thumb = await cache.image(mediaKey: "pink-house/event/e-1#thumb")
    XCTAssertNotNil(thumb)
    let missing = await cache.image(mediaKey: "unknown-key")
    XCTAssertNil(missing)

    let usage = await cache.usage()
    XCTAssertEqual(usage.mediaCount, 1)
    XCTAssertGreaterThan(usage.mediaBytes, 0)
  }

  func testMediaCacheRejectsContentHashMismatch() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallMediaCache(layout: TimeHallCacheLayout.testing(at: root))
    let bytes = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))

    let tampered = TimeHallDownloadedMedia(
      recordName: "th.media.test",
      contentHash: String(repeating: "0", count: 64),
      mimeType: "image/png",
      bytes: bytes
    )
    let generation = await cache.currentGeneration()
    do {
      _ = try await cache.install(
        media: tampered, mediaKey: "key", generation: generation)
      XCTFail("内容摘要不符必须被拒绝")
    } catch let error as TimeHallCacheError {
      XCTAssertEqual(error, .checksumMismatch)
    }
    let hasTampered = await cache.hasMedia(mediaKey: "key")
    XCTAssertFalse(hasTampered)
  }

  func testMediaCacheRejectsDisallowedMimeTypeAndUnsafeKey() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallMediaCache(layout: TimeHallCacheLayout.testing(at: root))
    let bytes = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))
    let hash = TimeHallPackCodec.sha256Hex(bytes)
    let generation = await cache.currentGeneration()

    let script = TimeHallDownloadedMedia(
      recordName: "th.media.test", contentHash: hash,
      mimeType: "application/javascript", bytes: bytes)
    do {
      _ = try await cache.install(media: script, mediaKey: "key", generation: generation)
      XCTFail("非白名单类型必须被拒绝，避免把可执行内容当图片落盘")
    } catch let error as TimeHallCacheError {
      XCTAssertEqual(error, .unsupportedEncoding)
    }

    let image = TimeHallDownloadedMedia(
      recordName: "th.media.test", contentHash: hash, mimeType: "image/png", bytes: bytes)
    for unsafeKey in ["../../etc/passwd", "/absolute/path", "a/../b", ""] {
      do {
        _ = try await cache.install(
          media: image, mediaKey: unsafeKey, generation: generation)
        XCTFail("非法媒体键必须被拒绝：\(unsafeKey)")
      } catch let error as TimeHallCacheError {
        XCTAssertEqual(error, .invalidIdentifier, unsafeKey)
      }
    }
  }

  func testMediaCacheClearRaisesGenerationAndDropsRecords() async throws {
    let root = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TimeHallMediaCache(layout: TimeHallCacheLayout.testing(at: root))
    let bytes = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))
    let media = TimeHallDownloadedMedia(
      recordName: "th.media.test",
      contentHash: TimeHallPackCodec.sha256Hex(bytes),
      mimeType: "image/png",
      bytes: bytes
    )
    let generation = await cache.currentGeneration()
    _ = try await cache.install(media: media, mediaKey: "key", generation: generation)
    let hasBefore = await cache.hasMedia(mediaKey: "key")
    XCTAssertTrue(hasBefore)

    try await cache.clearDownloadedContent()

    let hasAfter = await cache.hasMedia(mediaKey: "key")
    XCTAssertFalse(hasAfter)
    let after = await cache.currentGeneration()
    XCTAssertGreaterThan(after, generation)
    let usage = await cache.usage()
    XCTAssertEqual(usage.mediaCount, 0)
    // 清缓存不得删除个人资产：这里只断言媒体目录被清空而非整个沙盒
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
  }

  // MARK: - Bundle 种子（§8.3 默认禁止）

  func testBundleBrandSeedsAreExplicitlyRegistered() {
    let seeds = TimeHallBundleSource.brandSeeds
    XCTAssertEqual(seeds.count, 5)
    XCTAssertEqual(seeds.map(\.brandID), [
      "pink-house",
      "angelic-pretty",
      "baby-the-stars-shine-bright",
      "juliette-et-justine",
      "moi-meme-moitie",
    ])
    XCTAssertEqual(seeds.filter(\.isPrimary).count, 1)
    XCTAssertEqual(TimeHallBundleSource.primaryBrandID, "pink-house")
    for seed in seeds {
      XCTAssertFalse(seed.displayName.isEmpty, seed.brandID)
      XCTAssertFalse(seed.coverageDescription.isEmpty, "范围说明不得留空：\(seed.brandID)")
      XCTAssertNotNil(TimeZone(identifier: seed.sourceTimeZone), seed.brandID)
    }
  }

  func testBundleSeedPartitionsDeclarePartialCoverage() throws {
    let entry = try XCTUnwrap(TimeHallBundleSource.brandSeeds.first)
    let catalog = try XCTUnwrap(TimeHallBundleSource.catalog(resourceName: "catalog"))
    let seed = TimeHallBundleSource.makeSeed(entry: entry, catalog: catalog)
    let partitions = seed.partitions

    XCTAssertFalse(partitions.isEmpty)
    XCTAssertTrue(seed.contains(entityType: .event))
    XCTAssertEqual(seed.partition(for: .event)?.partitionRevision, 1, "来源没有修订概念，不编造")
    for partition in partitions {
      XCTAssertEqual(partition.brandID, entry.brandID)
      XCTAssertEqual(
        TimeHallPartitionID.brandID(from: partition.partitionID), entry.brandID)
      XCTAssertEqual(
        TimeHallPartitionID.entityType(from: partition.partitionID), partition.entityType)
      // Bundle 是过去某个时点的快照，不得自称 complete（§5.2）
      XCTAssertEqual(
        partition.coverageStatus, .partial,
        "随包种子不得声明完整覆盖：\(partition.partitionID)")
      XCTAssertTrue(TimeHallPartitionID.isSafe(partition.partitionID))
    }
  }

  // MARK: - 辅助

  private static let onePixelPNGBase64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  private func makeScratchDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("th-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func makeEvent(_ id: String, title: String? = nil) -> TimeHallEventDTO {
    TimeHallEventDTO(
      id: id,
      officialID: 0,
      kind: .event,
      title: title ?? id,
      publishedOn: "2026-09-13",
      summary: "",
      content: "",
      sourceURL: "https://www.pink-house.com/",
      coverImage: "",
      imageSourceURLs: [],
      productCodes: [],
      linkedCommerceItemIDs: [],
      observedAt: "2026-09-13"
    )
  }

  private func makeDescriptor(
    partitionID: String,
    brandID: String,
    entityType: TimeHallEntityType,
    dayCoverage: [String: TimeHallCoverageStatus] = [:]
  ) -> TimeHallPartitionDescriptor {
    TimeHallPartitionDescriptor(
      partitionID: partitionID,
      brandID: brandID,
      entityType: entityType,
      partitionRevision: 1,
      coverageStatus: .partial,
      checkedThrough: nil,
      dayCoverage: dayCoverage,
      packRecordName: "th.pack.\(partitionID)",
      payloadHash: String(repeating: "a", count: 64),
      recordCount: 1,
      dependencyPackRecordNames: []
    )
  }

  private func makeRelease(
    seq: Int,
    revocationEpoch: Int = 0,
    minimumReaderVersion: Int = TimeHallProtocol.readerVersion,
    publishedAt: String = "2026-09-14T00:00:00Z"
  ) -> TimeHallReleaseMetadata {
    TimeHallReleaseMetadata(
      releaseSeq: seq,
      schemaVersion: TimeHallProtocol.schemaVersion,
      publishedAt: publishedAt,
      rootIndexHash: String(repeating: "b", count: 64),
      revocationEpoch: revocationEpoch,
      minimumReaderVersion: minimumReaderVersion,
      previousReleaseSeq: max(0, seq - 1),
      changeTag: nil
    )
  }
}

extension TimeHallReadError {
  /// 便于遍历所有错误码做「必须有中文说明」的穷尽检查
  fileprivate static var allCasesForTesting: [TimeHallReadError] {
    [
      .offline, .cloudUnavailable, .permissionDenied, .throttled, .releaseUnreadable,
      .releaseMissing, .rootIndexHashMismatch, .packHashMismatch, .packDecodeFailed,
      .packTooLarge, .unsupportedEncoding, .unsupportedSchema, .missingDependency,
      .invalidIdentifier, .brandNotSupported, .diskSpaceInsufficient, .cancelled, .unknown,
    ]
  }
}
