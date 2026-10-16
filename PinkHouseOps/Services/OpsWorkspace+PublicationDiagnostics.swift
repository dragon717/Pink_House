import Foundation
import SharedCatalog
import PinkHouseOpsCore

extension OpsWorkspace {
    /// 通过保存面板导出本机已存在的比较证据；不拉取、不合并、不发布，也不读取凭证。
    func publicationDiagnostics() throws -> Data {
        func object<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: ShopCatalogJSONCoding.encoder().encode(value))
        }
        var result: [String: Any] = [
            "draftID": draft?.id ?? "", "revision": currentRevision,
            "targetEnvironment": OpsCloudSyncModel.shared.targetEnvironment.rawValue,
            "baseline": try object(baseline), "local": try object(catalog)
        ]
        if let baselineCatalog { result["baselineCatalog"] = try object(baselineCatalog) }
        result["environmentBaselines"] = try object(draft?.environmentBaselines ?? [:])
        var downloads: [[String: Any]] = []
        let directories = try FileManager.default.contentsOfDirectory(
            at: OpsCloudSyncModel.shared.jobsDirectory, includingPropertiesForKeys: nil)
        var latest: [String: (URL, [String: Any])] = [:]
        // 仅固定 pull 产物，不递归打包工作目录，避免凭证、图片或无关日志混入。
        for directory in directories where directory.lastPathComponent.hasPrefix("pull-") {
            let manifestURL = directory.appendingPathComponent("pull-manifest.json")
            let catalogURL = directory.appendingPathComponent("shop-catalog.json")
            guard let manifest = try? Data(contentsOf: manifestURL),
                  let manifestObject = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
                  let environment = manifestObject["targetEnvironment"] as? String,
                  ShopCatalogPublishTargetEnvironment(rawValue: environment) != nil,
                  FileManager.default.fileExists(atPath: catalogURL.path)
            else { continue }
            if let previous = latest[environment] {
                let seq = manifestObject["releaseSeq"] as? Int ?? -1
                let oldSeq = previous.1["releaseSeq"] as? Int ?? -1
                if seq < oldSeq { continue }
                if seq == oldSeq, (manifestObject["pulledAt"] as? String ?? "") <= (previous.1["pulledAt"] as? String ?? "") { continue }
            }
            latest[environment] = (directory, manifestObject)
        }
        for environment in latest.keys.sorted() {
            guard let (directory, manifestObject) = latest[environment] else { continue }
            let catalogURL = directory.appendingPathComponent("shop-catalog.json")
            let downloaded = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(contentsOf: catalogURL))
            var entry: [String: Any] = ["directory": directory.lastPathComponent,
                                       "manifest": manifestObject, "catalog": try object(downloaded)]
            if let preview = mergePreview(from: catalogURL, environment: environment) {
                entry["conflicts"] = preview.conflicts
            }
            downloads.append(entry)
        }
        result["downloads"] = downloads
        return try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    }
}
