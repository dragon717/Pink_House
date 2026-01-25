//
//  BackupArchiveUtils.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/26/26.
//

import Foundation
import Compression

// MARK: - Streaming Writer Utilities

/// A helper class to write compressed data stream to a file.
/// Uses LZFSE compression.
class StreamingCompressionWriter {
    private let fileHandle: FileHandle
    private var stream: compression_stream
    private let bufferSize = 65536
    private let destinationBuffer: UnsafeMutablePointer<UInt8>
    private var isInitialized = false
    
    init(url: URL) throws {
        // Create file
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: url)
        self.destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        
        self.stream = compression_stream(dst_ptr: destinationBuffer, dst_size: bufferSize, src_ptr: UnsafePointer(destinationBuffer), src_size: 0, state: nil)
        
        // Init stream
        let status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZFSE)
        guard status == COMPRESSION_STATUS_OK else { 
            destinationBuffer.deallocate()
            try? fileHandle.close()
            throw BackupService.BackupError.compressionFailed 
        }
        
        isInitialized = true
    }
    
    func write(_ data: Data) throws {
        guard isInitialized else { return }
        
        try data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) in
            guard let baseAddress = sourcePtr.baseAddress else { return }
            
            stream.src_ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            stream.src_size = data.count
            
            while stream.src_size > 0 {
                let status = compression_stream_process(&stream, 0) // No flag
                
                if status == COMPRESSION_STATUS_ERROR { throw BackupService.BackupError.compressionFailed }
                
                // If produced output
                let bytesWritten = bufferSize - stream.dst_size
                if bytesWritten > 0 {
                    let chunk = Data(bytes: destinationBuffer, count: bytesWritten)
                    try fileHandle.write(contentsOf: chunk)
                    stream.dst_ptr = destinationBuffer
                    stream.dst_size = bufferSize
                }
            }
        }
    }
    
    func close() throws {
        guard isInitialized else { return }
        
        // Finalize
        while true {
            let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            
            let bytesWritten = bufferSize - stream.dst_size
            if bytesWritten > 0 {
                let chunk = Data(bytes: destinationBuffer, count: bytesWritten)
                try fileHandle.write(contentsOf: chunk)
                stream.dst_ptr = destinationBuffer
                stream.dst_size = bufferSize
            }
            
            if status == COMPRESSION_STATUS_END { break }
            if status == COMPRESSION_STATUS_ERROR { throw BackupService.BackupError.compressionFailed }
        }
        
        compression_stream_destroy(&stream)
        destinationBuffer.deallocate()
        try fileHandle.close()
        isInitialized = false
    }
    
    deinit {
        if isInitialized {
            compression_stream_destroy(&stream)
            destinationBuffer.deallocate()
            try? fileHandle.close()
        }
    }
}

class TarStreamWriter {
    private let writer: StreamingCompressionWriter
    
    init(writer: StreamingCompressionWriter) {
        self.writer = writer
    }
    
    func appendEntry(fileName: String, data: Data) throws {
        let header = try createHeader(fileName: fileName, size: data.count)
        try writer.write(header)
        try writer.write(data)
        try writePadding(size: data.count)
    }
    
    func appendEntry(fileName: String, fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("TarStreamWriter: File missing at \(fileURL.path)")
            throw BackupService.BackupError.imageNotFound(fileName)
        }
        
        let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attr[.size] as? Int ?? 0
        
        let header = try createHeader(fileName: fileName, size: fileSize)
        try writer.write(header)
        
        // Stream read file
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        let bufferSize = 65536
        var totalRead = 0
        while true {
            let data = try fileHandle.read(upToCount: bufferSize)
            if let data = data, !data.isEmpty {
                try writer.write(data)
                totalRead += data.count
            } else {
                break
            }
        }
        
        if totalRead != fileSize {
            print("TarStreamWriter: File size mismatch for \(fileName). Expected \(fileSize), got \(totalRead)")
            throw BackupService.BackupError.archiveFailed
        }
        
        try writePadding(size: fileSize)
    }
    
    func finalize() throws {
        // Two empty blocks
        try writer.write(Data(count: 1024))
    }
    
    private func createHeader(fileName: String, size: Int) throws -> Data {
        var header = Data(count: 512)
        
        // Name (0)
        let nameData = fileName.data(using: .utf8)!
        let nameLength = min(nameData.count, 100)
        header.replaceSubrange(0..<nameLength, with: nameData.prefix(nameLength))
        
        // Mode (100) - 0000644
        let mode = "0000644\0"
        header.replaceSubrange(100..<108, with: mode.data(using: .utf8)!)
        
        // UID (108)
        let uid = "0000000\0"
        header.replaceSubrange(108..<116, with: uid.data(using: .utf8)!)
        
        // GID (116)
        let gid = "0000000\0"
        header.replaceSubrange(116..<124, with: gid.data(using: .utf8)!)
        
        // Size (124) - Octal string
        let sizeString = String(format: "%011o\0", size)
        header.replaceSubrange(124..<136, with: sizeString.data(using: .utf8)!)
        
        // MTime (136)
        let mtime = String(format: "%011o\0", Int(Date().timeIntervalSince1970))
        header.replaceSubrange(136..<148, with: mtime.data(using: .utf8)!)
        
        // Typeflag (156) - '0' for normal file
        header[156] = 48 // '0'
        
        // Magic (257) - ustar + \0
        let magic = "ustar\0"
        header.replaceSubrange(257..<263, with: magic.data(using: .utf8)!)
        
        // Version (263) - 00
        let version = "00"
        header.replaceSubrange(263..<265, with: version.data(using: .utf8)!)
        
        // Checksum (148) - 8 bytes: 6 octal digits + \0 + space
        let spaces = "        " 
        header.replaceSubrange(148..<156, with: spaces.data(using: .utf8)!)
        
        var checksum: Int = 0
        for byte in header {
            checksum += Int(byte)
        }
        // 标准格式为 6位八进制 + \0 + " "
        let checksumString = String(format: "%06o\0 ", checksum)
        header.replaceSubrange(148..<156, with: checksumString.data(using: .utf8)!)
        
        return header
    }
    
    private func writePadding(size: Int) throws {
        let paddingSize = (512 - (size % 512)) % 512
        if paddingSize > 0 {
            try writer.write(Data(count: paddingSize))
        }
    }
}

class TarReader {
    struct TarEntry {
        let name: String
        let data: Data
    }
    
    static func extract(data: Data) -> [TarEntry] {
        var entries: [TarEntry] = []
        var offset = 0
        
        while offset + 512 <= data.count {
            let header = data.subdata(in: offset..<offset+512)
            
            // 检查空块（存档结束）
            if header.allSatisfy({ $0 == 0 }) {
                // 有些 TAR 文件中间可能有空块，但按标准应该是最后两个
                // 探测下一个 512 字节是否也是 0
                if offset + 1024 <= data.count && data.subdata(in: offset+512..<offset+1024).allSatisfy({ $0 == 0 }) {
                    break
                }
                offset += 512
                continue
            }
            
            // 尝试解析文件名和大小
            let nameBytes = header.subdata(in: 0..<100)
            let nameString = String(data: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let sizeBytes = header.subdata(in: 124..<136)
            let sizeString = String(data: sizeBytes.prefix(while: { $0 != 0 }), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 基础校验：如果名字为空或大小不是纯八进制数字，可能是损坏块
            guard let name = nameString, !name.isEmpty,
                  let sizeStr = sizeString, let size = Int(sizeStr, radix: 8) else {
                // 鲁棒性增强：如果 header 看起来不对，尝试每 512 字节滑动查找潜在的下一个 header
                offset += 512
                continue
            }
            
            offset += 512
            
            // 读取数据
            if offset + size <= data.count {
                let fileData = data.subdata(in: offset..<offset+size)
                entries.append(TarEntry(name: name, data: fileData))
                
                // 跳过填充
                let padding = (512 - (size % 512)) % 512
                offset += size + padding
            } else {
                // 数据不完整，尝试截断读取或寻找下一个
                break
            }
        }
        
        return entries
    }
}
