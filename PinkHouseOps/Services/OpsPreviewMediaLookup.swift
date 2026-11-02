import Foundation
import PinkHouseOpsCore

/// 冷目录扫描和首次摘要核验也不能进入 SwiftUI 的主线程求值。
actor OpsPreviewMediaLookup {
    private let lookup = OpsCachedMediaLookup()
    func file(in directory: URL, hash: String) -> URL? {
        guard !Task.isCancelled else { return nil }
        return lookup.file(in: directory, hash: hash)
    }
}
