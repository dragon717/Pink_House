import Foundation
import UIKit
import Photos
import SharedCatalog

/// 收到系统相册的保存完成回执后才报告成功；下载不阻塞主线程。
@MainActor
enum ShopCatalogPhotoSaver {
    enum SaveError: LocalizedError {
        case unavailable, permissionDenied
        var errorDescription: String? {
            switch self {
            case .unavailable: return "保存失败：找不到原图".appLocalized
            case .permissionDenied: return "保存失败：请允许添加照片到相册".appLocalized
            }
        }
    }

    static func save(references: [String]) async throws -> Int {
        guard !references.isEmpty else { throw SaveError.unavailable }
        var images: [UIImage] = []
        for reference in references {
            let source = ShopCatalogImageSource.resolve(reference, asset: { ShopCatalogStore.shared.asset(id: $0) })
            do {
                let image = try await ShopCatalogImageLoader.load(source, mediaStore: .shared, session: .shared)
                images.append(image)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SaveError.unavailable
            }
        }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            throw SaveError.permissionDenied
        }
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges {
            for image in images { PHAssetChangeRequest.creationRequestForAsset(from: image) }
        }
        return images.count
    }
}
