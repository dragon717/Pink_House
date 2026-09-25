//
//  ShopCatalogExportArchive.swift
//  ItemManager
//
//  运营端「导出整包（含图片）」的归档打包（tar，USTAR，不压缩）。
//
//  ## 为什么必须带图
//
//  商品图在设备沙盒里是 `local:<文件名>` 引用（Application Support/ShopCatalog/images/）。
//  只导出 JSON 的话，Mac 发布端拿不到图 → 发布包里仍是 `local:` 引用 →
//  其它设备解不出文件 → 商品图一律占位（2026-09-25 实测：数据到了、图全空）。
//  所以导出必须把「引用到的图」一起带走，发布端才能上传成 THMedia。
//
//  ## 为什么用 tar 而不是 zip
//
//    · 图片本身已是 JPEG/PNG，再压缩收益极小，tar 够用；
//    · macOS 自带 `tar -xf`、Python 标准库 `tarfile` 都能读，零依赖；
//    · ZIP 要么引第三方库，要么自己写中央目录；tar 只是「512 字节头 + 数据」。
//
//  纯 Foundation / 无 UI 依赖，可单测。
//

import Foundation

public nonisolated enum ShopCatalogExportArchive {

    /// 归档内的一个条目
    public struct Entry {
        public let name: String   // 归档内路径（ASCII 安全名，如 "images/img-AB12.jpg"）
        public let data: Data

        // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    private static let blockSize = 512

    /// 打包成 tar（USTAR）。条目名必须是 ASCII 且不超 100 字符（超出用 prefix 拆分的场景本工程用不到）。
    public static func tarData(entries: [Entry]) -> Data {
        var output = Data()
        for entry in entries {
            output.append(header(for: entry))
            output.append(entry.data)
            let padding = (blockSize - entry.data.count % blockSize) % blockSize
            if padding > 0 { output.append(Data(repeating: 0, count: padding)) }
        }
        // 结束标记：两个全零块
        output.append(Data(repeating: 0, count: blockSize * 2))
        return output
    }

    /// 目录里哪些图片被引用了：只挑 `local:` 引用对应的文件，缺失的**如实列出**，
    /// 让运营在导出这一步就看见「有引用但没图」，而不是等发布端报错。
    /// - Returns: (可打包的条目, 缺失的文件名)
    ///
    /// ⚠️ 默认值在迁入 SharedCatalog 时**移除**了：原来的默认值
    /// `ShopCatalogImageStore.directory` 在 iOS App 里（依赖 UIKit 的落盘目录），
    /// 共享层拿不到它。调用方必须显式传入自己的图片目录
    /// （iOS 传 `ShopCatalogImageStore.directory`，Mac 传 staging 目录）。
    public static func imageEntries(
        forLocalReferences references: Set<String>,
        imageDirectory: URL
    ) -> (entries: [Entry], missing: [String]) {
        var entries: [Entry] = []
        var missing: [String] = []
        for reference in references.sorted() {
            guard let name = localFileName(in: reference) else { continue }
            let url = imageDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                missing.append(name)
                continue
            }
            entries.append(Entry(name: "images/\(name)", data: data))
        }
        return (entries, missing)
    }

    /// `local:<文件名>` → 文件名；非 local 引用或非法名返回 nil
    public static func localFileName(in reference: String) -> String? {
        let prefix = "local:"
        guard reference.hasPrefix(prefix) else { return nil }
        let name = String(reference.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return name
    }

    // MARK: USTAR 头

    private static func header(for entry: Entry) -> Data {
        var block = Data(repeating: 0, count: blockSize)

        func write(_ string: String, at offset: Int, length: Int) {
            let bytes = Array(string.utf8)
            for (index, byte) in bytes.enumerated() where index < length {
                block[offset + index] = byte
            }
        }
        func writeOctal(_ value: Int, at offset: Int, length: Int) {
            // USTAR 数字字段：右对齐、左侧补 '0'、以 NUL 结尾（长度-1 位八进制 + NUL）
            let text = String(value, radix: 8)
            let width = max(0, length - 1)
            let padded = text.count >= width
                ? String(text.suffix(width))
                : String(repeating: "0", count: width - text.count) + text
            write(padded, at: offset, length: width)
            block[offset + length - 1] = 0
        }

        write(entry.name, at: 0, length: 100)
        writeOctal(0o644, at: 100, length: 8)      // mode
        writeOctal(0, at: 108, length: 8)          // uid
        writeOctal(0, at: 116, length: 8)          // gid
        writeOctal(entry.data.count, at: 124, length: 12)  // size
        writeOctal(Int(Date().timeIntervalSince1970), at: 136, length: 12)  // mtime
        // 148..156 先留空格：checksum 计算时按空格参与求和
        for index in 148..<156 { block[index] = 0x20 }
        block[156] = 0x30                          // typeflag '0' = 普通文件
        write("ustar\u{0}", at: 257, length: 6)    // magic
        write("00", at: 263, length: 2)            // version

        // checksum 字段固定 8 字节：6 位八进制 + NUL + 空格（USTAR 规范形态）
        var sum = 0
        for byte in block { sum += Int(byte) }
        let octal = String(sum, radix: 8)
        let padded = octal.count >= 6
            ? String(octal.suffix(6))
            : String(repeating: "0", count: 6 - octal.count) + octal
        write(padded, at: 148, length: 6)
        block[154] = 0      // NUL
        block[155] = 0x20   // 空格
        return block
    }
}
