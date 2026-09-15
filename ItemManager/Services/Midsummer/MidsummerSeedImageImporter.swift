import Foundation

// MARK: - Bundle 内置种子图导入
//
// `ItemManager/Resources/Midsummer/SeedImages/` 里的静态素材随包分发
// （工程是 Xcode 16 文件系统同步组，文件放进去即自动入包，无需改 pbxproj）。
// 种子 JSON 引用的文件名（`seed-` 前缀）在运行期由这里拷入
// `ImageManager` 的 Images 目录——不登录 iCloud、无云端数据也能直接显示。
//
// 幂等：目标已存在则跳过，重复启动零开销；只增不删，用户删除/更换款式图
// 不会被下次启动覆盖回来。

nonisolated enum MidsummerSeedImageImporter {
  /// 种子图文件名前缀（樱花小羊系列）。新增系列种子图时扩展该清单。
  static let filePrefixes = ["seed-sakura-lamb-"]

  static func importIfNeeded() async {
    let bundleFiles = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil)?
      .filter { url in filePrefixes.contains { url.lastPathComponent.hasPrefix($0) } }
      ?? []
    guard !bundleFiles.isEmpty else { return }

    // ImageManager 是 @MainActor：目录 URL 在主线程取一次，拷贝在后台做。
    let directory = await ImageManager.shared.imagesDirectory
    let fileManager = FileManager.default
    var imported = 0

    for source in bundleFiles {
      let destination = directory.appendingPathComponent(source.lastPathComponent)
      guard !fileManager.fileExists(atPath: destination.path) else { continue }
      do {
        try fileManager.copyItem(at: source, to: destination)
        imported += 1
      } catch {
        print("⚠️ [Midsummer] 种子图导入失败 \(source.lastPathComponent)：\(error.localizedDescription)")
      }
    }

    if imported > 0 {
      print("✅ [Midsummer] 内置种子图已导入 \(imported) 张（共 \(bundleFiles.count) 张随包）")
    }
  }
}
