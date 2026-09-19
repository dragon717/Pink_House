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
          let variantNames = copyVariantImageAssets(from: record)
          return Self.makeItem(
            from: record,
            sizeChartImageName: sizeChartName,
            coverImageName: coverName,
            galleryImageNames: galleryNames,
            variantImageNames: variantNames
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

  /// 发布系列。返回系列封面的本地文件名（乐观更新用；没传图返回 nil）。
  @discardableResult
  func publish(series: MidsummerSeriesDTO, coverImage: UIImage?) async throws -> String? {
    // 权限预校验：公共库写入是创作者能力，非创作者在**建 CKRecord 之前**就被拦下。
    // 真正的写权限仍在 CloudKit Security Roles，这里挡的是 App 内越权调用。
    try CreatorAccess.requireCreator(.cloudPublish)
    // recordName 为空串会抛 ObjC 异常 CKException（Swift catch 拦不住，直接闪退），
    // 这里提前拦成可捕获的错误。
    guard !series.id.isEmpty else {
      throw MidsummerUploadError.other("系列 id 为空，无法上传，请重新进入发布页再试。")
    }
    let record = CKRecord(recordType: RecordType.series, recordID: CKRecord.ID(recordName: series.id))
    record["seriesID"] = series.id as CKRecordValue
    record["name"] = series.name as CKRecordValue
    record["year"] = series.year as CKRecordValue
    record["launchedOn"] = series.launchedOn as CKRecordValue
    record["stage"] = series.stage.rawValue as CKRecordValue
    // CloudKit 不允许用空列表初始化新字段（"cannot use an empty list"），
    // 所以列表字段只在非空时写入；读取侧 `?? []` 兜底。
    if !series.sizes.isEmpty { record["sizes"] = series.sizes as CKRecordValue }
    if !series.colors.isEmpty { record["colors"] = series.colors as CKRecordValue }
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
    var localCoverName: String?
    if let image = coverImage, let made = Self.makeAsset(from: image, name: "\(series.id)-cover") {
      record["coverImage"] = made.asset
      localCoverName = made.localName
    }
    try await save(record)
    return localCoverName
  }

  /// 发布单品（对齐千牛发布路径：每个单品最多 5 张主图宫格）。
  ///
  /// - `images[0]` 是**主图**，写 `coverImage` 资产；`images[1..<5]` 写 `galleryImage2..5`。
  /// - `variantImages` 是**款式对应图**（`款式名 → 图`，图2「粉色JSK / 粉色OP」样式）：
  ///   与主图宫格分开存，按传入顺序写 `variantImage1..8` 资产槽，
  ///   `款式名 → 槽位字段` 的映射序列化进 `variantImageMap` 字符串字段。
  /// - 以单品 id 为 recordID 整条重写，DTO 字段齐全，重复发布不会丢已有数据。
  ///   因此调用方传 `variantImages` 时必须带上**全部**款式图（已有 + 新增），
  ///   只传增量会把其余款式图整条抹掉。
  /// - 返回各图落盘后的**本地文件名**，调用方回填 DTO 做乐观更新（界面立刻有图）。
  @discardableResult
  func publish(
    item: MidsummerItemDTO, images: [UIImage], sizeChartImage: UIImage? = nil,
    variantImages: [(name: String, image: UIImage)] = []
  ) async throws -> MidsummerPublishedImages
  {
    // 同上：发布到公共库先过创作者校验（改价 / 换图落到基础条目时走的就是这条路）。
    try CreatorAccess.requireCreator(.cloudPublish)
    // 同 publish(series:)：空 recordName 会抛 ObjC 异常直接闪退，提前拦住。
    guard !item.id.isEmpty, !item.seriesID.isEmpty else {
      throw MidsummerUploadError.other("单品 id 未生成，无法上传，请重新进入发布页再试。")
    }
    let record = CKRecord(recordType: RecordType.item, recordID: CKRecord.ID(recordName: item.id))
    record["itemID"] = item.id as CKRecordValue
    record["seriesID"] = item.seriesID as CKRecordValue
    record["name"] = item.name as CKRecordValue
    record["kind"] = item.kind.rawValue as CKRecordValue
    // 同上：空列表不能写（CloudKit 限制），读取侧 `?? []` 兜底。
    if !item.sizes.isEmpty { record["sizes"] = item.sizes as CKRecordValue }
    if !item.colors.isEmpty { record["colors"] = item.colors as CKRecordValue }
    record["sourceURL"] = item.sourceURL as CKRecordValue
    record["note"] = (item.note ?? "") as CKRecordValue
    record["publishedAt"] = Date() as CKRecordValue
    if let value = item.price { record["price"] = value as CKRecordValue }
    // 预约价（全款预约）：与 price / deposit / balance 同为四类价格之一，
    // 读取侧 `makeItem` 会读它——漏写会出现「改价面板保存成功、回读后价格复原」的假象。
    if let value = item.preorderPrice { record["preorderPrice"] = value as CKRecordValue }
    if let value = item.deposit { record["deposit"] = value as CKRecordValue }
    if let value = item.balance { record["balance"] = value as CKRecordValue }
    if let value = item.priceKind { record["priceKind"] = value.rawValue as CKRecordValue }
    if let value = item.priceCapturedOn { record["priceCapturedOn"] = value as CKRecordValue }
    if let value = item.priceNote { record["priceNote"] = value as CKRecordValue }
    if let url = item.itemURL { record["itemURL"] = url as CKRecordValue }
    // 规格组 / SKU 表（2026-09-19 根因修复）：之前云端往返恒为 nil——创作者投稿、
    // 改价面板整条重写、跨设备同步之后，商品会退化成「无规格单品」，用户侧
    // 看不到颜色分类 / 尺码栏位，入库也直接按单品落。序列化成 JSON 字符串字段，
    // 避开 CloudKit 列表字段的限制（不能写空列表、字典类型受限）。
    if let json = Self.specGroupsJSON(item.specGroups) {
      record["specGroupsJSON"] = json as CKRecordValue
    }
    if let json = Self.skusJSON(item.skus) {
      record["skusJSON"] = json as CKRecordValue
    }
    if let createdBy = await currentUserID() { record["createdBy"] = createdBy as CKRecordValue }

    // 主图 + 附图：与千牛主图宫格一一对应（第 1 格 = coverImage，第 2–5 格 = galleryImage2..5）。
    var uploadedCoverName: String?
    var uploadedGalleryNames: [String] = []
    for (offset, image) in images.prefix(5).enumerated() {
      let assetName = offset == 0 ? "\(item.id)-cover" : "\(item.id)-gallery\(offset + 1)"
      let field = offset == 0 ? "coverImage" : "galleryImage\(offset + 1)"
      if let made = Self.makeAsset(from: image, name: assetName) {
        record[field] = made.asset
        if offset == 0 {
          uploadedCoverName = made.localName
        } else {
          uploadedGalleryNames.append(made.localName)
        }
      }
    }
    // 尺码表图片（双方案设计 §四：尺码表是系列页一等公民）。运营者补录时随单品一起上传。
    var uploadedSizeChartName: String?
    if let image = sizeChartImage,
      let made = Self.makeAsset(from: image, name: "\(item.id)-sizechart")
    {
      record["sizeChartImage"] = made.asset
      uploadedSizeChartName = made.localName
    }
    // 款式对应图：每个款式一张专属图，图和款式一一对应（不是堆进主图宫格）。
    // 槽位按传入顺序分配 `variantImage1..8`；映射（款式名 → 槽位字段）序列化成
    // JSON 存进字符串字段 `variantImageMap`，读取侧按它把资产还原成字典。
    var uploadedVariantNames: [String: String] = [:]
    if !variantImages.isEmpty {
      var map: [String: String] = [:]
      for (index, entry) in variantImages.prefix(Self.maxVariantImageSlots).enumerated() {
        let field = "variantImage\(index + 1)"
        guard let made = Self.makeAsset(from: entry.image, name: "\(item.id)-\(field)") else {
          continue
        }
        record[field] = made.asset
        map[entry.name] = field
        uploadedVariantNames[entry.name] = made.localName
      }
      if let data = try? JSONEncoder().encode(map),
        let json = String(data: data, encoding: .utf8)
      {
        record["variantImageMap"] = json as CKRecordValue
      }
    }
    // 款式尺码表映射（款式 → 本地文件名）。尺码表图以文件名引用（多为随包种子图，
    // 每台设备都有），不随 record 传资产；映射序列化进 `sizeChartMap` 字符串字段。
    if let chartMap = item.sizeChartImages, !chartMap.isEmpty,
      let data = try? JSONEncoder().encode(chartMap),
      let json = String(data: data, encoding: .utf8)
    {
      record["sizeChartMap"] = json as CKRecordValue
    }
    try await save(record)
    return MidsummerPublishedImages(
      coverImageName: uploadedCoverName,
      galleryImageNames: uploadedGalleryNames,
      sizeChartImageName: uploadedSizeChartName,
      variantImageNames: uploadedVariantNames
    )
  }

  /// 款式对应图的资产槽上限。一个淘宝链接里的款式很少超过 8 个；
  /// 超出的款式图会被跳过（界面仍展示款式名，只是没有图位）。
  nonisolated static let maxVariantImageSlots = 8

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
    galleryImageNames: [String]? = nil,
    variantImageNames: [String: String]? = nil
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
      preorderPrice: record["preorderPrice"] as? Int,
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
      // 规格组 / SKU 表从 JSON 字符串字段还原（2026-09-19 起云端往返保留规格，
      // 上传时填的颜色分类 / 尺码在用户侧与入库时都能看到）；旧记录没有这些键，
      // 解码为 nil，与「无规格单品」同口径。
      sizeChartImageName: sizeChartImageName,
      sizeChartImages: Self.decodeSizeChartMap(from: record),
      variantImageNames: variantImageNames,
      specGroups: Self.decodeSpecGroups(from: record["specGroupsJSON"] as? String),
      skus: Self.decodeSkus(from: record["skusJSON"] as? String)
    )
  }

  // MARK: - 规格序列化（specGroups / skus 的云端往返）

  /// 规格组序列化成 JSON 字符串。nil / 空 / 编码失败都返回 nil（不写 record）。
  nonisolated static func specGroupsJSON(_ groups: [MidsummerSpecGroup]?) -> String? {
    guard let groups, !groups.isEmpty,
      let data = try? JSONEncoder().encode(groups)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// SKU 表序列化成 JSON 字符串。nil / 空 / 编码失败都返回 nil（不写 record）。
  nonisolated static func skusJSON(_ skus: [MidsummerSKU]?) -> String? {
    guard let skus, !skus.isEmpty,
      let data = try? JSONEncoder().encode(skus)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// 从字符串字段还原规格组。字段缺失 / 解析失败都返回 nil，与「无规格」同口径。
  nonisolated static func decodeSpecGroups(from json: String?) -> [MidsummerSpecGroup]? {
    guard let json, let data = json.data(using: .utf8),
      let groups = try? JSONDecoder().decode([MidsummerSpecGroup].self, from: data),
      !groups.isEmpty
    else { return nil }
    return groups
  }

  /// 从字符串字段还原 SKU 表。字段缺失 / 解析失败都返回 nil，与「无约束」同口径。
  nonisolated static func decodeSkus(from json: String?) -> [MidsummerSKU]? {
    guard let json, let data = json.data(using: .utf8),
      let skus = try? JSONDecoder().decode([MidsummerSKU].self, from: data),
      !skus.isEmpty
    else { return nil }
    return skus
  }

  /// 从 `sizeChartMap` 字符串字段还原款式尺码表映射。字段缺失/解析失败都返回 nil。
  private nonisolated static func decodeSizeChartMap(from record: CKRecord)
    -> [MidsummerItemDTO.SizeChartEntry]?
  {
    guard let json = record["sizeChartMap"] as? String,
      let data = json.data(using: .utf8),
      let entries = try? JSONDecoder().decode([MidsummerItemDTO.SizeChartEntry].self, from: data),
      !entries.isEmpty
    else { return nil }
    return entries
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

  /// 把随查询下载的**款式对应图**（variantImage1..8 + variantImageMap 映射）复制进 Images 目录，
  /// 返回 `款式名 → 本地文件名`。映射缺失 / 解析失败 / 资产缺失都按缺图处理，
  /// 不影响其余字段——界面按「款式图待补充」如实展示。
  private func copyVariantImageAssets(from record: CKRecord) -> [String: String]? {
    guard let json = record["variantImageMap"] as? String,
      let data = json.data(using: .utf8),
      let map = try? JSONDecoder().decode([String: String].self, from: data),
      !map.isEmpty
    else { return nil }

    var result: [String: String] = [:]
    for (variantName, field) in map {
      guard let asset = record[field] as? CKAsset,
        let fileURL = asset.fileURL,
        FileManager.default.fileExists(atPath: fileURL.path)
      else { continue }

      let fileName =
        "midsummer-item-\(record.recordID.recordName)-\(field)-\(Int(Date().timeIntervalSince1970)).jpg"
      let destination = ImageManager.shared.imagesDirectory.appendingPathComponent(fileName)
      do {
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fileURL, to: destination)
        result[variantName] = fileName
      } catch {
        print("⚠️ [Midsummer] 款式图「\(variantName)」复制失败：\(error.localizedDescription)")
      }
    }
    return result.isEmpty ? nil : result
  }

  // MARK: - 图片

  /// CKAsset 只吃文件 URL：压缩后的图写到临时目录供 CKAsset 引用，
  /// **同时在 ImageManager 的 Images 目录落一份持久副本**（命名空间 `midsummer-upload-`）。
  /// 返回本地文件名给调用方回填 DTO——发布页乐观更新立刻有图，不用等云端刷新回填。
  /// （类是 @MainActor，本方法保持 MainActor 隔离以访问 ImageManager；调用方均在类内。）
  private static func makeAsset(from image: UIImage, name: String)
    -> (asset: CKAsset, localName: String)?
  {
    let maxEdge: CGFloat = 1200
    let scale = min(1, maxEdge / max(image.size.width, image.size.height))
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }

    let localName = "midsummer-upload-\(name)-\(Int(Date().timeIntervalSince1970)).jpg"
    let persistentURL = ImageManager.shared.imagesDirectory.appendingPathComponent(localName)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(name)
      .appendingPathExtension("jpg")
    do {
      try data.write(to: persistentURL, options: .atomic)
      try data.write(to: tempURL, options: .atomic)
    } catch {
      print("⚠️ [Midsummer] 图片落盘失败：\(error.localizedDescription)")
      return nil
    }
    return (CKAsset(fileURL: tempURL), localName)
  }
}

// MARK: - 上传错误

/// 发布单品后返回的**本地**图片文件名（ImageManager Images 目录内）。
/// 调用方回填 DTO 后做乐观更新——不等云端刷新，发布页/详情页立刻能显示图。
nonisolated struct MidsummerPublishedImages {
  var coverImageName: String?
  var galleryImageNames: [String]
  var sizeChartImageName: String?
  /// 款式对应图：`款式名 → 本地文件名`（未传款式图时为空字典）。
  var variantImageNames: [String: String] = [:]
}

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
