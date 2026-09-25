//
//  ShopCatalogJSONCoding.swift
//  ItemManager
//
//  ShopCatalog 全链路 JSON 编解码的唯一口径（2026-09-22 第三版收口 R01）。
//
//  ## 为什么需要这个文件
//
//  事故形态：`persist()` 用 `.iso8601` 编码草稿，而 `loadDrafts()` 用**默认**
//  `JSONDecoder()`（默认策略 = `secondsSince1970` 数值时间戳）读取。ISO8601 字符串
//  在默认策略下解码必然失败，失败后又被 `?? []` 兜成「空草稿箱」——
//  于是带日期的草稿在重启后整体消失，下一次保存还会用空库覆盖掉旧文件，
//  运营侧表现为「草稿丢了，而且找不回来」。
//
//  修复分三件事，全部收敛在这里：
//
//  1. **编解码同源**：读写的日期策略必须成对，统一走 `encoder()` / `decoder()`。
//  2. **兼容确实存在的历史格式**：ISO8601（含/不含小数秒）、纯日期、秒级与毫秒级
//     数值时间戳都能读回来 —— 存量文件不是「错误数据」，只是旧口径。
//  3. **失败可见**：解码失败由调用方决定如何处置（保留原文件 / 备份 / 报错），
//     本层只负责抛出可诊断的错误，绝不静默返回空数组。
//
//  nonisolated 纯逻辑，可单测（见 ShopCatalogDraftPersistenceRegressionTests）。
//

import Foundation

public nonisolated enum ShopCatalogJSONCoding {

    // MARK: 编码器

    /// 全链路统一编码器：日期一律 ISO8601（与 `decoder()` 的解析口径配对）。
    public static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        return encoder
    }

    // MARK: 解码器

    /// 全链路统一解码器：日期走宽容解析（见 `decodeDate`），兼容历史落盘格式。
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        return decoder
    }

    /// 宽容日期解析：按「最可能的格式」依次尝试，全部失败才抛错。
    ///
    /// 支持（均为仓库里**确实出现过**的落盘形态）：
    ///   · `2026-09-22T15:16:46Z`        ISO8601（无小数秒）
    ///   · `2026-09-22T15:16:46.123Z`    ISO8601（含小数秒）
    ///   · `2026-09-22`                  纯日期（迁移产物与手工编辑常见）
    ///   · `1758543406`                  秒级时间戳（默认策略历史落盘）
    ///   · `1758543406123`               毫秒级时间戳
    ///
    /// 数值类型的秒 / 毫秒区分按量级判定：|v| ≥ 1e11 视为毫秒（1e11 秒 ≈ 公元 5138 年，
    /// 不可能是业务时间），否则按秒解释。
    public nonisolated static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Double.self) {
            if abs(number) >= 1e11 {
                return Date(timeIntervalSince1970: number / 1000.0)
            }
            return Date(timeIntervalSince1970: number)
        }

        let text = try container.decode(String.self)
        if let date = Self.date(fromISO8601: text) { return date }
        if let date = Self.date(fromPlainDate: text) { return date }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "无法解析日期「\(text)」：既不是 ISO8601，也不是纯日期或时间戳")
    }

    // MARK: 内部解析

    private static func date(fromISO8601 text: String) -> Date? {
        if let date = iso8601Fractional.date(from: text) { return date }
        if let date = iso8601Plain.date(from: text) { return date }
        return nil
    }

    /// `yyyy-MM-dd`（可带 ` HH:mm:ss`）：迁移产物与手工编辑产出的常见形态
    private static func date(fromPlainDate text: String) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - 草稿文件损坏（R01：解码失败不得当成空库）

public nonisolated enum ShopCatalogDraftFileError: LocalizedError {
    /// 草稿文件存在但无法解析。**原文件已保留**并备份到 `backupURL`，
    /// 在人工确认前不允许任何写回（防止空库覆盖掉还能抢救的旧文件）。
    case corrupt(original: URL, backup: URL?, reason: String)

    /// 在「文件损坏待处理」状态下尝试写入被拒绝（保护性拦截，不是写入失败）。
    case writeBlockedByCorruptFile(URL)

    /// 写盘失败：内存与磁盘均未变化，可直接重试
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .corrupt(let original, let backup, let reason):
            var text = "草稿文件无法解析（\(reason)）。原文件已保留：\(original.lastPathComponent)"
            if let backup {
                text += "，已备份为 \(backup.lastPathComponent)"
            }
            text += "。请先人工确认或移除坏文件后再保存，期间不会覆盖旧数据。"
            return text
        case .writeBlockedByCorruptFile(let url):
            return "草稿文件 \(url.lastPathComponent) 处于「损坏待处理」状态，已阻止写入以避免覆盖可抢救的旧数据。请处理坏文件后重试。"
        case .writeFailed(let detail):
            return "草稿写入失败：\(detail)。草稿箱未发生变化，请重试。"
        }
    }
}
