//
//  BackupArchiveUtils.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/26/26.
//

import Foundation

// MARK: - Native Package Wrapper (FileWrapper based)

/// 使用苹果原生的 FileWrapper 机制进行文件的打包和序列化。
/// 这是最稳定的方式，规避了自定义 TAR 头信息对齐和流式压缩不匹配的风险。
class NativePackageWrapper {
    
    /// 将 Manifest 和相关图片文件打包为单个加密/压缩的 Data
    /// - Parameters:
    ///   - manifestData: JSON 格式的 manifest
    ///   - imageFiles: [文件名: 文件真实路径]
    static func createPackage(manifestData: Data, imageFiles: [String: URL]) throws -> Data {
        let rootWrapper = FileWrapper(directoryWithFileWrappers: [:])
        
        // 1. 添加 Manifest
        let manifestWrapper = FileWrapper(regularFileWithContents: manifestData)
        manifestWrapper.preferredFilename = "manifest.json"
        rootWrapper.addFileWrapper(manifestWrapper)
        
        // 2. 批量添加图片
        for (fileName, fileURL) in imageFiles {
            do {
                let fileWrapper = try FileWrapper(url: fileURL, options: .immediate)
                fileWrapper.preferredFilename = fileName
                rootWrapper.addFileWrapper(fileWrapper)
            } catch {
                print("NativePackageWrapper: Skipping missing or unreadable file: \(fileName) at \(fileURL.path)")
            }
        }
        
        // 3. 序列化为 Data
        guard let packageData = rootWrapper.serializedRepresentation else {
            throw BackupService.BackupError.archiveFailed
        }
        
        // 4. 压缩 (使用官方标准的 LZFSE 头部)
        let compressed = try (packageData as NSData).compressed(using: .lzfse)
        
        return compressed as Data
    }
    
    /// 从 .save 数据中还原出文件列表
    /// - Returns: [文件名: 数据内容]
    static func unwrapPackage(data: Data) throws -> [String: Data] {
        // 1. 解压缩 (自动识别 LZFSE 标志)
        let decompressed: NSData
        do {
            decompressed = try (data as NSData).decompressed(using: .lzfse)
        } catch {
            throw BackupService.BackupError.decompressionFailed(reason: "LZFSE header mismatch or corrupted data: \(error.localizedDescription)")
        }
        
        // 2. 通过 FileWrapper 还原目录结构
        guard let rootWrapper = try? FileWrapper(serializedRepresentation: decompressed as Data),
              rootWrapper.isDirectory,
              let childWrappers = rootWrapper.fileWrappers else {
            throw BackupService.BackupError.invalidArchive
        }
        
        var result: [String: Data] = [:]
        for (key, wrapper) in childWrappers {
            if let fileData = wrapper.regularFileContents {
                // 使用 key (通常是 preferredFilename) 作为文件名索引
                result[key] = fileData
            }
        }
        
        return result
    }
}
