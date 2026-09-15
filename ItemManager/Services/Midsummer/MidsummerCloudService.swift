import CloudKit
import Foundation
import UIKit

// MARK: - 仲夏物语 · CloudKit 公共库读写
//
// 复用项目既有容器 `iCloud.bugod2.ItemManager`（与 Notice / 时光馆一致），
// 因此**不需要新建容器**，但需要在 CloudKit Console 为下面两个 Record Type 配好字段与权限：
//
//   MidsummerSeries   系列
//   MidsummerItem     单品
//
// 权限要求：`_world` 与 `_icloud` 一律 **Read-only**，Create/Write 只给自定义角色
// （参见 docs/MIDSUMMER_TALE_CLOUDKIT_SETUP.md）。客户端 `isAdmin()` 只是 UI 闸门，
// 不是安全边界——这一点在 docs/品牌上新资讯功能方案.md §6 已经写明。
//
// 本服务**不做任何爬取**（项目硬约束）：只读写 CloudKit，图片由创作者本地上传。

@MainActor
final class MidsummerCloudService {
  static let shared = MidsummerCloudService()

  /// Record Type 名。改这里必须同步改 Console 与文档。
  nonisolated enum RecordType {
    static let series = "MidsummerSeries"
    static let item = "MidsummerItem"
  }

  private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
  private var database: CKDatabase { container.publicCloudDatabase }

  /// 单次查询上限，避免一次把整库拉回来（设计要求强制分页）。
  private let pageSize = 60

  private init() {}

  // MARK: - 权限

  /// 复用公告 CMS 的白名单，避免两处维护运营名单。
  func isAdmin() async -> Bool {
    await NoticeCloudKitService.shared.isAdmin()
  }

  /// 三态白名单判定。上传入口的显示门控看它，而不是看 `isAdmin()`——
  /// 「明确不在名单里」和「取不到身份」必须分开处理（见 `NoticeCloudKitService.CreatorGate`）。
  func creatorGate() async -> NoticeCloudKitService.CreatorGate {
    await NoticeCloudKitService.shared.creatorGate()
  }

  func currentUserID() async -> String? {
    try? await container.userRecordID().recordName
  }

  // MARK: - 读取

  /// 拉取创作者上传的全部系列（含单品）。
  ///
  /// 只返回系列本身，品牌元信息由 `MidsummerStore` 用 Bundle 种子提供——
  /// 这样本服务不依赖种子常量，职责单一。
  ///
  /// 任何失败都返回 `nil` 而不是抛错：调用方据此回退 Bundle 种子，
  /// 保证未登录 iCloud / 未配置 Schema / 断网时**不白屏**（§T5）。
  func fetchSeries() async -> [MidsummerSeriesDTO]? {
    do {
      let accountStatus = try await container.accountStatus()
      guard accountStatus == .available else {
        print("ℹ️ [Midsummer] iCloud 不可用（status=\(accountStatus.rawValue)），使用 Bundle 种子")
        return nil
      }

      let seriesRecords = try await fetchRecords(
        recordType: RecordType.series, sortedBy: "publishedAt")
      guard !seriesRecords.isEmpty else {
        print("ℹ️ [Midsummer] 公共库暂无创作者上传内容，使用 Bundle 种子")
        return nil
      }
      let itemRecords =
        (try? await fetchRecords(recordType: RecordType.item, sortedBy: "publishedAt")) ?? []

      let itemsBySeries = Dictionary(
        grouping: itemRecords.compactMap { record -> MidsummerItemDTO? in
          // 图片资产随查询已下载到本地临时目录（CKAsset.fileURL），
          // 复制进 Images 目录后只存文件名——显示与一键入库共用这一个名字。
          let sizeChartName = copySizeChartAsset(from: record)
          let coverName = copyItemCoverAsset(from: record)
          let galleryNames = copyItemGalleryAssets(from: record)
          return Self.makeItem(
            from: record,
            sizeChartImageName: sizeChartName,
            coverImageName: coverName,
            galleryImageNames: galleryNames
          )
        }
      ) { $0.seriesID }
      let series = seriesRecords.compactMap { record -> MidsummerSeriesDTO? in
        let seriesID = record["seriesID"] as? String ?? record.recordID.recordName
        return Self.makeSeries(from: record, items: itemsBySeries[seriesID] ?? [])
      }
      print("✅ [Midsummer] 公共库读取成功：\(series.count) 个系列 / \(itemRecords.count) 个单品")
      return series.isEmpty ? nil : series
    } catch {
      print("⚠️ [Midsummer] 公共库读取失败，回退 Bundle 种子：\(error.localizedDescription)")
      return nil
    }
  }

  private func fetchRecords(recordType: String, sortedBy key: String) async throws -> [CKRecord] {
    let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
    query.sortDescriptors = [NSSortDescriptor(key: key, ascending: false)]

    var results: [CKRecord] = []
    var cursor: CKQueryOperation.Cursor?
    repeat {
      let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
      if let current = cursor {
        page = try await database.records(continuingMatchFrom: current, resultsLimit: pageSize)
      } else {
        page = try await database.records(matching: query, resultsLimit: pageSize)
      }
      results.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
      cursor = page.queryCursor
    } while cursor != nil && results.count < 2000

    return results
  }

  // MARK: - 写入（创作者上传）

  func publish(series: MidsummerSeriesDTO, coverImage: UIImage?) async throws {
    let record = CKRecord(recordType: RecordType.series, recordID: CKRecord.ID(recordName: series.id))
    record["seriesID"] = series.id as CKRecordValue
    record["name"] = series.name as CKRecordValue
    record["year"] = series.year as CKRecordValue
    record["launchedOn"] = series.launchedOn as CKRecordValue
    record["stage"] = series.stage.rawValue as CKRecordValue
    record["sizes"] = series.sizes as CKRecordValue
    record["colors"] = series.colors as CKRecordValue
    record["summary"] = (series.summary ?? "") as CKRecordValue
    record["sourceURL"] = series.sourceURL as CKRecordValue
    record["sourceKind"] = "editorial" as CKRecordValue
    record["verified"] = 1 as CKRecordValue
    record["publishedAt"] = Date() as CKRecordValue
    // 价格区间不再上传：它是从单品派生的，上传一份就等于制造第二份真相。
    // 定金区间是来源价带口径、无法归到单品，所以照传，并带上出处。
    if let value = series.depositMin { record["depositMin"] = value as CKRecordValue }
    if let value = series.depositMax { record["depositMax"] = value as CKRecordValue }
    if let value = series.priceSource { record["priceSource"] = value as CKRecordValue }
    if let createdBy = await currentUserID() { record["createdBy"] = createdBy as CKRecordValue }
    if let image = coverImage, let asset = Self.makeAsset(from: image, name: "\(series.id)-cover") {
      record["coverImage"] = asset
    }
    try await save(record)
  }

  /// 发布单品（对齐千牛发布路径：每个单品最多 5 张主图宫格）。
  ///
  /// - `images[0]` 是**主图**，写 `coverImage` 资产；`images[1..<5]` 写 `galleryImage2..5`。
  /// - 以单品 id 为 recordID 整条重写，DTO 字段齐全，重复发布不会丢已有数据。
  func publish(item: MidsummerItemDTO, images: [UIImage], sizeChartImage: UIImage? = nil)
    async throws
  {
    let record = CKRecord(recordType: RecordType.item, recordID: CKRecord.ID(recordName: item.id))
    record["itemID"] = item.id as CKRecordValue
    record["seriesID"] = item.seriesID as CKRecordValue
    record["name"] = item.name as CKRecordValue
    record["kind"] = item.kind.rawValue as CKRecordValue
    record["sizes"] = item.sizes as CKRecordValue
    record["colors"] = item.colors as CKRecordValue
    record["sourceURL"] = item.sourceURL as CKRecordValue
    record["note"] = (item.note ?? "") as CKRecordValue
    record["publishedAt"] = Date() as CKRecordValue
    if let value = item.price { record["price"] = value as CKRecordValue }
    if let value = item.deposit { record["deposit"] = value as CKRecordValue }
    if let value = item.balance { record["balance"] = value as CKRecordValue }
    if let value = item.priceKind { record["priceKind"] = value.rawValue as CKRecordValue }
    if let value = item.priceCapturedOn { record["priceCapturedOn"] = value as CKRecordValue }
    if let value = item.priceNote { record["priceNote"] = value as CKRecordValue }
    if let url = item.itemURL { record["itemURL"] = url as CKRecordValue }
    if let createdBy = await currentUserID() { record["createdBy"] = createdBy as CKRecordValue }

    // 主图 + 附图：与千牛主图宫格一一对应（第 1 格 = coverImage，第 2–5 格 = galleryImage2..5）。
    for (offset, image) in images.prefix(5).enumerated() {
      let assetName = offset == 0 ? "\(item.id)-cover" : "\(item.id)-gallery\(offset + 1)"
      let field = offset == 0 ? "coverImage" : "galleryImage\(offset + 1)"
      if let asset = Self.makeAsset(from: image, name: assetName) {
        record[field] = asset
      }
    }
    // 尺码表图片（双方案设计 §四：尺码表是系列页一等公民）。运营者补录时随单品一起上传。
    if let image = sizeChartImage, let asset = Self.makeAsset(from: image, name: "\(item.id)-sizechart") {
      record["sizeChartImage"] = asset
    }
    try await save(record)
  }

  private func save(_ record: CKRecord) async throws {
    do {
      _ = try await database.save(record)
    } catch let error as CKError {
      throw MidsummerUploadError.from(error)
    }
  }

  // MARK: - CKRecord → DTO

  private nonisolated static func makeSeries(from record: CKRecord, items: [MidsummerItemDTO])
    -> MidsummerSeriesDTO?
  {
    guard let seriesID = record["seriesID"] as? String,
      let name = record["name"] as? String,
      !name.isEmpty
    else { return nil }

    let stage = (record["stage"] as? String).flatMap(MidsummerStage.init(rawValue:)) ?? .inStock
    return MidsummerSeriesDTO(
      id: seriesID,
      name: name,
      year: record["year"] as? Int ?? 0,
      launchedOn: record["launchedOn"] as? String ?? "",
      stage: stage,
      coverImage: nil,
      depositMin: record["depositMin"] as? Int,
      depositMax: record["depositMax"] as? Int,
      priceSource: (record["priceSource"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      sizes: record["sizes"] as? [String] ?? [],
      colors: record["colors"] as? [String] ?? [],
      summary: (record["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      sourceURL: record["sourceURL"] as? String ?? "",
      sourceKind: record["sourceKind"] as? String ?? "editorial",
      verified: (record["verified"] as? Int ?? 0) == 1,
      items: items
    )
  }

  private nonisolated static func makeItem(
    from record: CKRecord,
    sizeChartImageName: String? = nil,
    coverImageName: String? = nil,
    galleryImageNames: [String]? = nil
  ) -> MidsummerItemDTO? {
    guard let itemID = record["itemID"] as? String,
      let seriesID = record["seriesID"] as? String,
      let name = record["name"] as? String,
      !name.isEmpty
    else { return nil }

    return MidsummerItemDTO(
      id: itemID,
      seriesID: seriesID,
      name: name,
      kind: (record["kind"] as? String).flatMap(MidsummerItemKind.init(rawValue:)) ?? .op,
      price: record["price"] as? Int,
      deposit: record["deposit"] as? Int,
      balance: record["balance"] as? Int,
      priceKind: (record["priceKind"] as? String).flatMap(MidsummerPriceKind.init(rawValue:)),
      priceCapturedOn: (record["priceCapturedOn"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      priceNote: (record["priceNote"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      sizes: record["sizes"] as? [String] ?? [],
      colors: record["colors"] as? [String] ?? [],
      coverImage: coverImageName,
      galleryImageNames: galleryImageNames,
      itemURL: record["itemURL"] as? String,
      sourceURL: record["sourceURL"] as? String ?? "",
      note: (record["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      // 规格尚未接入上传表单：CloudKit 侧仍按「无规格」处理，
      // 由 Bundle 种子 `midsummer-series.json` 提供规格组与 SKU 组合。
      // 见 docs/MIDSUMMER_TALE_SPEC_SELECTION.md「规格数据的三个来源」。
      sizeChartImageName: sizeChartImageName,
      specGroups: nil,
      skus: nil
    )
  }

  /// 把随查询下载的尺码表资产（CKAsset 临时文件）复制进 ImageManager 的 Images 目录，
  /// 返回本地文件名。没有资产或复制失败都返回 nil——界面按「待补充」如实展示。
  ///
  /// 文件名带时间戳避免同名覆盖；命名空间 `midsummer-sizechart-` 与衣橱手动上传的图区分。
  private func copySizeChartAsset(from record: CKRecord) -> String? {
    guard let asset = record["sizeChartImage"] as? CKAsset,
      let fileURL = asset.fileURL,
      FileManager.default.fileExists(atPath: fileURL.path)
    else { return nil }

    let fileName = "midsummer-sizechart-\(record.recordID.recordName)-\(Int(Date().timeIntervalSince1970)).jpg"
    let destination = ImageManager.shared.imagesDirectory.appendingPathComponent(fileName)
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: fileURL, to: destination)
      return fileName
    } catch {
      print("⚠️ [Midsummer] 尺码表图复制失败：\(error.localizedDescription)")
      return nil
    }
  }

  /// 把随查询下载的**单品图**资产（CKAsset 临时文件）复制进 ImageManager 的 Images 目录，
  /// 返回本地文件名。没有资产或复制失败都返回 nil——界面回退系列封面并如实标注「待补充」。
  ///
  /// 命名空间 `midsummer-item-` 与尺码表（`midsummer-sizechart-`）、衣橱手动上传的图区分；
  /// 文件名带时间戳，运营者更换图片后旧文件自然不再被引用。
  private func copyItemCoverAsset(from record: CKRecord) -> String? {
    guard let asset = record["coverImage"] as? CKAsset,
      let fileURL = asset.fileURL,
      FileManager.default.fileExists(atPath: fileURL.path)
    else { return nil }

    let fileName = "midsummer-item-\(record.recordID.recordName)-\(Int(Date().timeIntervalSince1970)).jpg"
    let destination = ImageManager.shared.imagesDirectory.appendingPathComponent(fileName)
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: fileURL, to: destination)
      return fileName
    } catch {
      print("⚠️ [Midsummer] 单品图复制失败：\(error.localizedDescription)")
      return nil
    }
  }

  /// 把随查询下载的**单品附图**（galleryImage2..5，千牛宫格第 2–5 格）复制进 Images 目录，
  /// 按槽位顺序返回文件名；缺失或复制失败的槽位自动跳过。
  private func copyItemGalleryAssets(from record: CKRecord) -> [String] {
    (2...5).compactMap { slot in
      guard let asset = record["galleryImage\(slot)"] as? CKAsset,
        let fileURL = asset.fileURL,
        FileManager.default.fileExists(atPath: fileURL.path)
      else { return nil }

      let fileName =
        "midsummer-item-\(record.recordID.recordName)-\(slot)-\(Int(Date().timeIntervalSince1970)).jpg"
      let destination = ImageManager.shared.imagesDirectory.appendingPathComponent(fileName)
      do {
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fileURL, to: destination)
        return fileName
      } catch {
        print("⚠️ [Midsummer] 单品附图复制失败：\(error.localizedDescription)")
        return nil
      }
    }
  }

  // MARK: - 图片

  /// CKAsset 只吃文件 URL，因此先把压缩后的图写到临时目录。
  private nonisolated static func makeAsset(from image: UIImage, name: String) -> CKAsset? {
    let maxEdge: CGFloat = 1200
    let scale = min(1, maxEdge / max(image.size.width, image.size.height))
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(name)
      .appendingPathExtension("jpg")
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      print("⚠️ [Midsummer] 封面写入临时文件失败：\(error.localizedDescription)")
      return nil
    }
    return CKAsset(fileURL: url)
  }
}

// MARK: - 上传错误

nonisolated enum MidsummerUploadError: LocalizedError {
  case notAuthenticated
  case permissionDenied
  case quotaExceeded
  case network
  case other(String)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated: return "请先在系统设置中登录 iCloud，再上传内容。"
    case .permissionDenied:
      return "当前账号没有上传权限。请确认已在 CloudKit Console 把写入权限授予编辑者角色。"
    case .quotaExceeded: return "CloudKit 存储配额已满，请先清理旧封面图。"
    case .network: return "网络不可用，稍后重试即可，已填写的内容不会丢失。"
    case .other(let message): return message
    }
  }

  /// 把 CKError 翻成用户能读懂的话；不要直接把 `CKError` 抛到界面上。
  static func from(_ error: CKError) -> MidsummerUploadError {
    switch error.code {
    case .notAuthenticated: return .notAuthenticated
    case .permissionFailure, .serverRejectedRequest: return .permissionDenied
    case .quotaExceeded: return .quotaExceeded
    case .networkUnavailable, .networkFailure, .requestRateLimited:
      return .network
    default: return .other(error.localizedDescription)
    }
  }
}
