#!/usr/bin/env python3
"""迁包时的两处**必要**改动（可重复跑，已改过就跳过）。

从 `ItemManager/` 搬到 `SharedCatalog` 后，有两个地方在共享层里不成立，
必须在补 `public` 之前先改掉：

1. `ShopCatalogSyncProtocol` 补媒体输入约束常量。
   原来这两个常量只存在于 Mac 端 `protocol.py`（`MAX_MEDIA_BYTES` /
   `MEDIA_MIME_ALLOWLIST`），Swift 侧没有。共享层要做「图片规范化 + 入库门槛」，
   就必须有同一份口径 —— 否则就会变成「两端各写一个数字」。

2. `ShopCatalogExportArchive.imageEntries` **去掉默认参数**。
   原签名 `imageDirectory: URL = ShopCatalogImageStore.directory`，
   而 `ShopCatalogImageStore` 在 iOS App 里（依赖 UIKit 的落盘目录），
   共享层拿不到它 —— 带着这个默认值共享包根本编不过。
   改成必填，让调用方各自传入（iOS 传 `ShopCatalogImageStore.directory`，
   Mac 传自己的 staging 目录）。
"""
import pathlib
import sys

PROTOCOL = pathlib.Path(
    "Sources/SharedCatalog/Sync/ShopCatalogCloudSyncProtocol.swift")
ARCHIVE = pathlib.Path(
    "Sources/SharedCatalog/Publishing/ShopCatalogExportArchive.swift")

CONSTANTS_ANCHOR = """    static func mediaReference(contentHash: String) -> String {
        "\\(mediaReferencePrefix)\\(contentHash)"
    }
"""

CONSTANTS_ADDITION = CONSTANTS_ANCHOR + """
    // MARK: 媒体输入约束（与 protocol.py 的 MEDIA_MIME_ALLOWLIST / MAX_MEDIA_BYTES 逐字对齐）

    /// 单张媒体的字节上限（Mac 端 `MAX_MEDIA_BYTES` = 20 MiB）。
    ///
    /// 为什么要有：运营商品图经「长边 1600 / JPEG 0.85」处理后远小于此，
    /// 超限基本可以判定是误选了相机原图。发布端会**硬报错**而不是压缩兜底 ——
    /// 悄悄换掉运营选的图比构建失败危险得多。
    static let maxMediaBytes = 20 * 1024 * 1024

    /// 允许进入公共库的图片类型（Mac 端 `MEDIA_MIME_ALLOWLIST`）。
    ///
    /// 只放客户端确实能解码的类型（`ShopCatalogMediaStore.inferredFileExtension`
    /// 的魔数判定口径）：jpeg / png / gif / webp / heic。
    /// 「传上去但客户端显示不出来」比「构建失败」难查得多。
    static let mediaMimeAllowlist: [String] = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/heic",
    ]

    static func isAllowedMediaMimeType(_ mimeType: String) -> Bool {
        mediaMimeAllowlist.contains(mimeType.lowercased())
    }
"""

ARCHIVE_OLD = """    static func imageEntries(
        forLocalReferences references: Set<String>,
        imageDirectory: URL = ShopCatalogImageStore.directory
    ) -> (entries: [Entry], missing: [String]) {"""

ARCHIVE_NEW = """    ///
    /// ⚠️ 默认值在迁入 SharedCatalog 时**移除**了：原来的默认值
    /// `ShopCatalogImageStore.directory` 在 iOS App 里（依赖 UIKit 的落盘目录），
    /// 共享层拿不到它。调用方必须显式传入自己的图片目录
    /// （iOS 传 `ShopCatalogImageStore.directory`，Mac 传 staging 目录）。
    static func imageEntries(
        forLocalReferences references: Set<String>,
        imageDirectory: URL
    ) -> (entries: [Entry], missing: [String]) {"""


def main() -> int:
    text = PROTOCOL.read_text(encoding="utf-8")
    if "maxMediaBytes" in text:
        print("· 协议常量已存在，跳过")
    else:
        assert text.count(CONSTANTS_ANCHOR) == 1, "协议锚点未唯一命中"
        PROTOCOL.write_text(
            text.replace(CONSTANTS_ANCHOR, CONSTANTS_ADDITION, 1), encoding="utf-8")
        print("✅ 协议常量已补")

    text = ARCHIVE.read_text(encoding="utf-8")
    if "imageDirectory: URL\n" in text:
        print("· 归档签名已是必填，跳过")
    else:
        assert text.count(ARCHIVE_OLD) == 1, "归档锚点未唯一命中"
        ARCHIVE.write_text(text.replace(ARCHIVE_OLD, ARCHIVE_NEW, 1), encoding="utf-8")
        print("✅ 归档层签名已调整")
    return 0


if __name__ == "__main__":
    sys.exit(main())
