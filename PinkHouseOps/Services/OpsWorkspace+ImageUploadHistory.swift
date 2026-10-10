import Foundation
import SwiftData
import SharedCatalog

/// 保存完整资源元数据，目录被合并、替换或表单归零后仍能找到上传的副本。
struct OpsUploadedImageRecord: Codable {
    var asset: CatalogAsset
    var name: String
    var uploadedAt: Date
}

struct OpsImageLibraryItem: Identifiable {
    var asset: CatalogAsset
    var name: String
    var fileURL: URL?
    var uploadedAt: Date
    var id: String { asset.id }
}

extension OpsWorkspace {
    /// 本机素材跨系列、跨目录草稿复用，未选中前不把其它草稿的资源写入当前目录。
    func loadImageUploadHistory() {
        guard let records = try? context.fetch(FetchDescriptor<OpsCatalogDraftRecord>()) else { return }
        var items: [OpsImageLibraryItem] = []
        for record in records {
            let directory = rootDirectory.appendingPathComponent("staging", isDirectory: true)
                .appendingPathComponent(record.stagingFolderName, isDirectory: true)
            let history = record.uploadedImageHistoryJSON.flatMap {
                try? decodeUploadedImageHistory($0)
            } ?? []
            for uploaded in history {
                items.append(OpsImageLibraryItem(asset: uploaded.asset, name: uploaded.name,
                    fileURL: historyFileURL(asset: uploaded.asset, directory: directory), uploadedAt: uploaded.uploadedAt))
            }
            // 旧版本没有记录原文件名，沿用原有资源和 staging 字节，不能把旧图隐藏掉。
            let recordedIDs = Set(history.map { $0.asset.id })
            if let catalog = try? ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: record.catalogJSON) {
                for asset in catalog.assets where !recordedIDs.contains(asset.id) {
                    if let url = historyFileURL(asset: asset, directory: directory) {
                        items.append(OpsImageLibraryItem(asset: asset,
                            name: (asset.originalURL as NSString).lastPathComponent,
                            fileURL: url, uploadedAt: record.createdAt))
                    }
                }
            }
        }
        items.sort {
            if $0.uploadedAt != $1.uploadedAt { return $0.uploadedAt > $1.uploadedAt }
            // 同图优先采用仍存在的副本，其余同秒记录按名称与 id 稳定排列。
            if ($0.fileURL != nil) != ($1.fileURL != nil) { return $0.fileURL != nil }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
        var combined: [OpsImageLibraryItem] = []
        var indices: [String: Int] = [:]
        for item in items {
            if let index = indices[item.id] {
                if combined[index].fileURL == nil { combined[index].fileURL = item.fileURL }
            } else {
                indices[item.id] = combined.count
                combined.append(item)
            }
        }
        imageUploadHistory = combined
    }

    func imageLibraryItems(uploadsOnly: Bool, search: String) -> [OpsImageLibraryItem] {
        var items = imageUploadHistory
        if !uploadsOnly {
            let historyIDs = Set(items.map(\.id))
            items += catalog.assets.filter { !historyIDs.contains($0.id) }.map {
                OpsImageLibraryItem(asset: $0, name: ($0.originalURL as NSString).lastPathComponent,
                    fileURL: stagedFileURL(forReference: $0.originalURL), uploadedAt: .distantPast)
            }
        }
        return items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// 上传时立即保存历史，不依赖配图「确定」或系列提交。资源清单与历史使用同一次落盘。
    @discardableResult
    func saveImportedImageHistory(_ names: [(id: String, name: String)]) -> Bool {
        guard let draft, !draft.isCorrupted else { return false }
        let previousJSON = draft.uploadedImageHistoryJSON
        do {
            var history = try previousJSON.map {
                try decodeUploadedImageHistory($0)
            } ?? []
            for item in names {
                guard let asset = asset(for: item.id) else { continue }
                history.removeAll { $0.asset.id == item.id }
                history.insert(OpsUploadedImageRecord(asset: asset, name: item.name, uploadedAt: Date()), at: 0)
            }
            draft.uploadedImageHistoryJSON = try JSONEncoder().encode(history)
            loadImageUploadHistory()
            guard saveDraft() else {
                draft.uploadedImageHistoryJSON = previousJSON
                lastError = "图片副本已导入，但上传历史保存失败：" + (lastError ?? "未知原因")
                return false
            }
            return true
        } catch {
            draft.uploadedImageHistoryJSON = previousJSON
            lastError = "上传历史保存失败（原历史保留）：\(error.localizedDescription)"
            return false
        }
    }

    /// 选择历史素材时拷贝到当前 staging。复制原字节，不重新编码、改变图片身份。
    func useImageLibraryItem(_ item: OpsImageLibraryItem) -> String? {
        guard canMutate() else { return nil }
        if let current = asset(for: item.id), stagedFileURL(forReference: current.originalURL) != nil {
            return current.id
        }
        guard let source = item.fileURL else {
            lastError = "这张历史图片的本机副本暂不可用，请补充图片后再选择。"
            return nil
        }
        do {
            let data = try Data(contentsOf: source)
            let hash = ShopCatalogSyncProtocol.sha256Hex(data)
            if let expected = ShopCatalogSyncProtocol.resolvedMediaKey(item.asset.mediaKey), hash != expected {
                lastError = "历史图片副本校验失败，请重新上传此图片。"
                return nil
            }
            let fileName = hash + "." + source.pathExtension
            let target = stagingDirectory.appendingPathComponent(fileName)
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            if (try? Data(contentsOf: target)) != data { try data.write(to: target, options: .atomic) }
            var asset = item.asset
            asset.originalURL = "local:" + fileName
            asset.previewURL = asset.originalURL
            asset.thumbnailURL = asset.originalURL
            asset.mediaKey = hash
            if let index = catalog.assets.firstIndex(where: { $0.id == asset.id }) { catalog.assets[index] = asset }
            else { catalog.assets.append(asset) }
            markDirty()
            guard saveImportedImageHistory([(asset.id, item.name)]) else { return nil }
            lastError = nil
            return asset.id
        } catch {
            lastError = "历史图片读取失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func decodeUploadedImageHistory(_ data: Data) throws -> [OpsUploadedImageRecord] {
        // 保留亚秒上传顺序，跨草稿重复上传同图时使用最近的原文件名。
        if let records = try? JSONDecoder().decode([OpsUploadedImageRecord].self, from: data) { return records }
        return try ShopCatalogJSONCoding.decoder().decode([OpsUploadedImageRecord].self, from: data)
    }

    private func historyFileURL(asset: CatalogAsset, directory: URL) -> URL? {
        var candidates: [String] = []
        for reference in [asset.originalURL, asset.previewURL, asset.thumbnailURL].compactMap({ $0 }) {
            if let name = ShopCatalogMediaReferences.localFileName(in: reference),
               name == (name as NSString).lastPathComponent { candidates.append(name) }
            else if let hash = ShopCatalogSyncProtocol.mediaContentHash(in: reference) {
                candidates += ["jpg", "png", "webp", "heic", "gif"].map { "\(hash).\($0)" }
            }
        }
        for name in candidates {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
