//
//  BackupService.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/25/26.
//

import Foundation
import SwiftData
import UIKit
import Compression

// ... (DTOs and Tar Utilities remain unchanged) ...
// MARK: - Data Transfer Objects

struct BackupManifest: Codable {
    let version: String
    let timestamp: Date
    let deviceName: String
    
    let brands: [BrandDTO]
    let tags: [TagDTO]
    let clothings: [ClothingDTO]
    let storedImages: [StoredImageDTO]
    let cutouts: [CutoutItemDTO]
    let outfits: [OutfitDTO]
    
    // Summary
    let clothingCount: Int
    let imageCount: Int
    let outfitCount: Int
}

struct BrandDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct TagDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct ClothingDTO: Codable {
    let id: UUID
    let name: String
    let brandID: UUID?
    let tagIDs: [UUID]
    let types: String
    let colors: String
    let sizes: String
    let length: String
    let condition: String
    let accessories: String
    let imagePaths: [String]
    let isShared: Bool
    let price: Decimal
    let deposit: Decimal
    let balance: Decimal
    let accessoriesPrice: Decimal
    let purchaseDate: Date
    let depositDate: Date?
    let isDepositPlan: Bool
    let finalPaymentDate: Date?
    let finalPaymentEndDate: Date?
    let note: String
    let stock: Int
    let status: String
    let createdAt: Date
    let updatedAt: Date
}

struct StoredImageDTO: Codable {
    let id: UUID
    let imageHash: String
    let fileName: String
    let refCount: Int
}

struct CutoutItemDTO: Codable {
    let id: UUID
    let originalImageHash: String
    let timestamp: Date
    let category: String
    let imagePath: String
    let width: Double
    let height: Double
    let linkedClothingID: UUID?
}

struct OutfitDTO: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let snapshotPath: String?
    let items: [OutfitItemDTO]
}

struct OutfitItemDTO: Codable {
    let id: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let zIndex: Int
    let cutoutID: UUID?
}

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
        
        // Init stream struct manually since Swift import might not provide full zero-init via default constructor if arguments are missing
        // Actually `compression_stream()` works if all fields have defaults, but C struct mapping can be tricky.
        // Let's initialize all fields explicitly to 0 or use the pointer directly in init.
        // Note: src_ptr cannot be nil in Swift binding even if src_size is 0, so we pass a valid pointer (destinationBuffer) casted.
        self.stream = compression_stream(dst_ptr: destinationBuffer, dst_size: bufferSize, src_ptr: UnsafePointer(destinationBuffer), src_size: 0, state: nil)
        
        // Init stream
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZFSE)
        guard status == COMPRESSION_STATUS_OK else { throw BackupService.BackupError.compressionFailed }
        
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
        let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attr[.size] as? Int ?? 0
        
        let header = try createHeader(fileName: fileName, size: fileSize)
        try writer.write(header)
        
        // Stream read file
        if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? fileHandle.close() }
            
            let bufferSize = 65536
            while true {
                let data = try fileHandle.read(upToCount: bufferSize)
                if let data = data, !data.isEmpty {
                    try writer.write(data)
                } else {
                    break
                }
            }
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
        
        // Magic (257) - ustar
        let magic = "ustar\0"
        header.replaceSubrange(257..<263, with: magic.data(using: .utf8)!)
        
        // Version (263) - 00
        let version = "00"
        header.replaceSubrange(263..<265, with: version.data(using: .utf8)!)
        
        // Checksum (148) - Calculate last
        let spaces = "        " // 8 spaces
        header.replaceSubrange(148..<156, with: spaces.data(using: .utf8)!)
        
        var checksum: Int = 0
        for byte in header {
            checksum += Int(byte)
        }
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
            
            // Check for empty block (end of archive)
            if header.allSatisfy({ $0 == 0 }) {
                break
            }
            
            // Parse Name
            let nameBytes = header.subdata(in: 0..<100)
            guard let nameString = String(data: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) else {
                offset += 512
                continue
            }
            
            // Parse Size (124, 12 bytes)
            let sizeBytes = header.subdata(in: 124..<136)
            guard let sizeString = String(data: sizeBytes.prefix(while: { $0 != 0 }), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let size = Int(sizeString, radix: 8) else {
                offset += 512
                continue
            }
            
            offset += 512
            
            // Read Data
            if offset + size <= data.count {
                let fileData = data.subdata(in: offset..<offset+size)
                entries.append(TarEntry(name: nameString, data: fileData))
                
                // Skip padding
                let padding = (512 - (size % 512)) % 512
                offset += size + padding
            } else {
                break
            }
        }
        
        return entries
    }
}

// MARK: - Backup Service

@MainActor
class BackupService {
    static let shared = BackupService()
    
    enum BackupError: Error {
        case dataFetchFailed
        case fileCreateFailed
        case imageNotFound(String)
        case archiveFailed
        case invalidArchive
        case compressionFailed
    }
    
    private init() {}
    
    // MARK: - Export
    
    // Robust ID-based processing to allow skipping individual corrupt objects (Ghost Objects)
    nonisolated private func processByIDs<T: PersistentModel, ResultType>(
        context: ModelContext,
        descriptor: FetchDescriptor<T>,
        entityName: String,
        process: (T) -> ResultType?
    ) throws -> [ResultType] {
        print("### Export: Fetching IDs for \(entityName)...")
        
        // 关键修复 1：在执行 Fetch 之前强制 reconciled。
        // 这将确保背景上下文与持久化存储（SQLite）的状态对齐，清除那些已经物理删除但内存中还存留 ID 的“僵尸”缓存。
        context.processPendingChanges()
        
        // 关键修复 2：禁用挂起更改。
        var safeDescriptor = descriptor
        safeDescriptor.includePendingChanges = false
        
        let allItems = try context.fetch(safeDescriptor)
        let totalCount = allItems.count
        print("### Export: Found \(totalCount) \(entityName) items (Excl. Pending). Starting processing...")
        
        var results: [ResultType] = []
        var successCount = 0
        var failCount = 0
        
        // 2. Iterate and process one by one
        for (index, item) in allItems.enumerated() {
            // Periodic log
            if index > 0 && index % 100 == 0 {
                print("### Export \(entityName): Processed \(index)/\(totalCount)...")
            }
            
            let id = item.persistentModelID
            
            // 关键修复 3：使用 do-catch 包装 model(for:)。
            // 当 SwiftData 发现数据在存储中消失时，直接访问 item 或调用 model(for:) 可能会抛出致命错误或异常。
            // 通过显式 Catch，我们可以优雅地跳过这些在 Fetch 后可能又被变更的“僵尸”对象。
            do {
                guard let safeItem = try context.model(for: id) as? T else {
                    print("### Export \(entityName): 跳过无效对象 (Index: \(index), ID: \(id))")
                    failCount += 1
                    continue
                }
                
                if safeItem.isDeleted {
                    print("### Export \(entityName): 跳过已删除对象 (Index: \(index))")
                    failCount += 1
                    continue
                }
                
                if let result = process(safeItem) {
                    results.append(result)
                    successCount += 1
                } else {
                    failCount += 1
                }
            } catch {
                print("### Export \(entityName): 捕获到僵尸对象 (ID: \(id)). 已跳过。错误: \(error)")
                failCount += 1
                continue
            }
        }
        
        print("### Export \(entityName): Finished. Success: \(successCount), Skipped/Failed: \(failCount)")
        return results
    }
    
    nonisolated func exportBackup(container: ModelContainer) async throws -> URL {
        // Immediate Log to verify execution start
        print("### Export: exportBackup called on background service.")
        
        let imagesDir = await ImageManager.shared.imagesDirectory
        // 0. Capture MainActor properties
        let deviceName = await UIDevice.current.name
        
        print("### Export: Captured device info. Starting background task...")
        
        // Run everything in a detached task with a NEW ModelContext
        return try await Task.detached(priority: .medium) {
            print("### Export: Background task started.")
            
            // Create a local context for background work
            let context = ModelContext(container)
            // Note: Keeping autosaveEnabled = true (default) or false?
            // User reported crash with save(). Let's keep it default aka true but we won't trigger save explicitly.
            // Actually, false is safer for read-only Ops.
            context.autosaveEnabled = false
            
            // Shared file collection
            var filesToBackup: Set<String> = []
            
            // 1. Brands
            let brandDTOs: [BrandDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<Brand>(), entityName: "Brands") { b in
                return BrandDTO(id: b.id, name: b.name, colorHex: b.colorHex)
            }
            
            // 2. Tags
            let tagDTOs: [TagDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<Tag>(), entityName: "Tags") { t in
                return TagDTO(id: t.id, name: t.name, colorHex: t.colorHex)
            }
            
            // 3. Stored Images
            let storedImageDTOs: [StoredImageDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<StoredImage>(), entityName: "StoredImages") { img in
                filesToBackup.insert(img.fileName)
                return StoredImageDTO(id: img.id, imageHash: img.imageHash, fileName: img.fileName, refCount: img.refCount)
            }
            
            // 4. Clothings (Move earlier to serve as reference)
            var clothingDescriptor = FetchDescriptor<Clothing>()
            clothingDescriptor.relationshipKeyPathsForPrefetching = [\Clothing.brand, \Clothing.tags]
            let clothingDTOs: [ClothingDTO] = try self.processByIDs(context: context, descriptor: clothingDescriptor, entityName: "Clothings") { c in
                // 收集图片路径以便后续打包
                for path in c.imagePaths {
                    filesToBackup.insert(path)
                }
                
                var brandUUID: UUID? = nil
                var tagUUIDs: [UUID] = []
                
                // 关键防御：访问关联时使用 do-catch 和安全性检查
                do {
                    // 尝试触碰关联对象，如果其 backing data 丢失，这里可能会抛出异常或触发内部错误
                    if let brand = c.brand {
                        brandUUID = brand.id
                    }
                    tagUUIDs = c.tags?.compactMap { $0.id } ?? []
                } catch {
                    print("### Export Clothings [ID: \(c.id)]: 获取关联 Brand/Tags 时发现僵尸对象。")
                }
                
                return ClothingDTO(
                    id: c.id,
                    name: c.name,
                    brandID: brandUUID,
                    tagIDs: tagUUIDs,
                    types: c.types,
                    colors: c.colors,
                    sizes: c.sizes,
                    length: c.length,
                    condition: c.condition,
                    accessories: c.accessories,
                    imagePaths: c.imagePaths,
                    isShared: c.isShared,
                    price: c.price,
                    deposit: c.deposit,
                    balance: c.balance,
                    accessoriesPrice: c.accessoriesPrice,
                    purchaseDate: c.purchaseDate,
                    depositDate: c.depositDate,
                    isDepositPlan: c.isDepositPlan,
                    finalPaymentDate: c.finalPaymentDate,
                    finalPaymentEndDate: c.finalPaymentEndDate,
                    note: c.note,
                    stock: c.stock,
                    status: c.status.rawValue,
                    createdAt: c.createdAt,
                    updatedAt: c.updatedAt
                )
            }
            
            // 5. Cutouts
            var cutoutDescriptor = FetchDescriptor<CutoutItem>()
            cutoutDescriptor.relationshipKeyPathsForPrefetching = [\CutoutItem.linkedClothing]
            let cutoutDTOs: [CutoutItemDTO] = try self.processByIDs(context: context, descriptor: cutoutDescriptor, entityName: "Cutouts") { c in
                if !c.imagePath.isEmpty {
                    filesToBackup.insert((c.imagePath as NSString).lastPathComponent)
                }
                
                var clothingID: UUID? = nil
                do {
                    // 这里是原先崩溃的核心点。
                    // 触碰关联前检查对象是否还在 context 中
                    if let clothing = c.linkedClothing {
                        clothingID = clothing.id
                    }
                } catch {
                    print("### Export Cutouts [ID: \(c.id)]: 发现失效的关联 Clothing，跳过。")
                }
                
                return CutoutItemDTO(
                    id: c.id,
                    originalImageHash: c.originalImageHash,
                    timestamp: c.timestamp,
                    category: c.category,
                    imagePath: c.imagePath,
                    width: c.width,
                    height: c.height,
                    linkedClothingID: clothingID
                )
            }
            
            // 6. Outfits
            var outfitDescriptor = FetchDescriptor<Outfit>()
            outfitDescriptor.relationshipKeyPathsForPrefetching = [\Outfit.items]
            let outfitDTOs: [OutfitDTO] = try self.processByIDs(context: context, descriptor: outfitDescriptor, entityName: "Outfits") { o in
                if let snapshot = o.snapshotPath {
                    filesToBackup.insert((snapshot as NSString).lastPathComponent)
                }
                
                var items: [OutfitItemDTO] = []
                // 注意：o.items 访问也可能由于 cascading delete 的不一致导致异常
                do {
                    let outfitItems = o.items
                    for item in outfitItems {
                        // 关联关系安全性检查
                        do {
                            // 通过触碰 persistentModelID 和 cutout 关联来检测对象是否存活
                            let _ = item.persistentModelID
                            let cutoutID = item.cutout?.id
                            
                            if !item.isDeleted {
                                let itemDTO = OutfitItemDTO(
                                    id: item.id,
                                    x: item.x,
                                    y: item.y,
                                    rotation: item.rotation,
                                    scale: item.scale,
                                    zIndex: item.zIndex,
                                    cutoutID: cutoutID
                                )
                                items.append(itemDTO)
                            }
                        } catch {
                            print("### Export Outfits: 发现失效的关联 OutfitItem，跳过。")
                            continue
                        }
                    }
                } catch {
                    print("### Export Outfits [ID: \(o.id)]: 访问 items 列表失败。")
                }
                
                return OutfitDTO(
                    id: o.id,
                    createdAt: o.createdAt,
                    note: o.note,
                    snapshotPath: o.snapshotPath,
                    items: items
                )
            }
            
            let manifest = BackupManifest(
                version: "1.0",
                timestamp: Date(),
                deviceName: deviceName,
                brands: brandDTOs,
                tags: tagDTOs,
                clothings: clothingDTOs,
                storedImages: storedImageDTOs,
                cutouts: cutoutDTOs,
                outfits: outfitDTOs,
                clothingCount: clothingDTOs.count,
                imageCount: storedImageDTOs.count,
                outfitCount: outfitDTOs.count
            )
            
            print("### Export: Collecting files (\(filesToBackup.count) files)...")
            
            let fileList = Array(filesToBackup)
            
            // 4. Create Temp File
            let fileName = "少女心愿\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "")).save"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            // 5. Init Streaming Writer
            let compressionWriter = try StreamingCompressionWriter(url: tempURL)
            let tarWriter = TarStreamWriter(writer: compressionWriter)
            
            defer {
                try? compressionWriter.close()
            }
            
            // 6. Write Manifest
            let jsonEncoder = JSONEncoder()
            jsonEncoder.dateEncodingStrategy = .iso8601
            let jsonData = try jsonEncoder.encode(manifest)
            try tarWriter.appendEntry(fileName: "manifest.json", data: jsonData)
            
            // 7. Write Images (Streamed)
            let totalFiles = fileList.count
            for (i, fileName) in fileList.enumerated() {
                if i > 0 && i % 50 == 0 {
                    print("### Export: Archiving file \(i)/\(totalFiles)...")
                }
                
                let fileURL = imagesDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try tarWriter.appendEntry(fileName: fileName, fileURL: fileURL)
                }
            }
            
            // 8. Finalize
            try tarWriter.finalize()
            try compressionWriter.close()
            print("### Export: Backup file ready at \(tempURL)")
            
            return tempURL
        }.value
    }
    
    // MARK: - Import
    
    func importBackup(from url: URL, context: ModelContext) throws {
        // 1. Read Data (To be optimized to stream later if needed)
        let compressedData = try Data(contentsOf: url)
        
        // 2. Decompress
        let tarData = try (compressedData as NSData).decompressed(using: .lzfse) as Data
        
        // 3. Extract TAR
        let entries = TarReader.extract(data: tarData)
        
        // 4. Find Manifest
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
            throw BackupError.invalidArchive
        }
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        let manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestEntry.data)
        
        // 5. Restore Images
        let imagesDir = ImageManager.shared.imagesDirectory
        for entry in entries where entry.name != "manifest.json" {
            let fileURL = imagesDir.appendingPathComponent(entry.name)
            // Skip if exists? Or overwrite? Restore usually implies overwrite or ensuring existence.
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try entry.data.write(to: fileURL)
            }
        }
        
        // 6. Restore Data
        // Helper map for UUIDs if we were remapping, but here we keep UUIDs.
        
        // Restore Brands
        let existingBrands = try context.fetch(FetchDescriptor<Brand>())
        var brandMap: [UUID: Brand] = Dictionary(uniqueKeysWithValues: existingBrands.map { ($0.id, $0) })
        
        for dto in manifest.brands {
            if let existing = brandMap[dto.id] {
                // Update
                existing.name = dto.name
                existing.colorHex = dto.colorHex
            } else {
                // Create
                let newBrand = Brand(name: dto.name, colorHex: dto.colorHex)
                newBrand.id = dto.id
                context.insert(newBrand)
                brandMap[dto.id] = newBrand
            }
        }
        
        // Restore Tags
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagMap: [UUID: Tag] = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.id, $0) })
        
        for dto in manifest.tags {
            if let existing = tagMap[dto.id] {
                existing.name = dto.name
                existing.colorHex = dto.colorHex
            } else {
                let newTag = Tag(name: dto.name, colorHex: dto.colorHex)
                newTag.id = dto.id
                context.insert(newTag)
                tagMap[dto.id] = newTag
            }
        }
        
        // Restore StoredImages (Metadata)
        let existingImages = try context.fetch(FetchDescriptor<StoredImage>())
        var imageMap: [UUID: StoredImage] = Dictionary(uniqueKeysWithValues: existingImages.map { ($0.id, $0) })
        
        for dto in manifest.storedImages {
            if let existing = imageMap[dto.id] {
                existing.refCount = dto.refCount
                existing.fileName = dto.fileName
                existing.imageHash = dto.imageHash
            } else {
                let newImage = StoredImage(imageHash: dto.imageHash, fileName: dto.fileName)
                newImage.id = dto.id
                newImage.refCount = dto.refCount
                context.insert(newImage)
                imageMap[dto.id] = newImage
            }
        }
        
        // Restore Clothing
        let existingClothings = try context.fetch(FetchDescriptor<Clothing>())
        var clothingMap: [UUID: Clothing] = Dictionary(uniqueKeysWithValues: existingClothings.map { ($0.id, $0) })
        
        for dto in manifest.clothings {
            let clothing: Clothing
            if let existing = clothingMap[dto.id] {
                clothing = existing
                // Update properties
                clothing.name = dto.name
                clothing.types = dto.types
                clothing.colors = dto.colors
                clothing.sizes = dto.sizes
                clothing.length = dto.length
                clothing.condition = dto.condition
                clothing.accessories = dto.accessories
                clothing.imagePaths = dto.imagePaths
                clothing.isShared = dto.isShared
                clothing.price = dto.price
                clothing.deposit = dto.deposit
                clothing.balance = dto.balance
                clothing.accessoriesPrice = dto.accessoriesPrice
                clothing.purchaseDate = dto.purchaseDate
                clothing.depositDate = dto.depositDate
                clothing.isDepositPlan = dto.isDepositPlan
                clothing.finalPaymentDate = dto.finalPaymentDate
                clothing.finalPaymentEndDate = dto.finalPaymentEndDate
                clothing.note = dto.note
                clothing.stock = dto.stock
                clothing.status = ClothingStatus(rawValue: dto.status) ?? .onShelf
                clothing.createdAt = dto.createdAt
                clothing.updatedAt = dto.updatedAt
            } else {
                clothing = Clothing(name: dto.name)
                clothing.id = dto.id
                context.insert(clothing)
                clothingMap[dto.id] = clothing
                
                // Set props
                clothing.types = dto.types
                clothing.colors = dto.colors
                clothing.sizes = dto.sizes
                clothing.length = dto.length
                clothing.condition = dto.condition
                clothing.accessories = dto.accessories
                clothing.imagePaths = dto.imagePaths
                clothing.isShared = dto.isShared
                clothing.price = dto.price
                clothing.deposit = dto.deposit
                clothing.balance = dto.balance
                clothing.accessoriesPrice = dto.accessoriesPrice
                clothing.purchaseDate = dto.purchaseDate
                clothing.depositDate = dto.depositDate
                clothing.isDepositPlan = dto.isDepositPlan
                clothing.finalPaymentDate = dto.finalPaymentDate
                clothing.finalPaymentEndDate = dto.finalPaymentEndDate
                clothing.note = dto.note
                clothing.stock = dto.stock
                clothing.status = ClothingStatus(rawValue: dto.status) ?? .onShelf
                clothing.createdAt = dto.createdAt
                clothing.updatedAt = dto.updatedAt
            }
            
            // Link Brand
            if let brandID = dto.brandID, let brand = brandMap[brandID] {
                clothing.brand = brand
            }
            
            // Link Tags
            clothing.tags = dto.tagIDs.compactMap { tagMap[$0] }
        }
        
        // Restore Cutouts
        let existingCutouts = try context.fetch(FetchDescriptor<CutoutItem>())
        var cutoutMap: [UUID: CutoutItem] = Dictionary(uniqueKeysWithValues: existingCutouts.map { ($0.id, $0) })
        
        for dto in manifest.cutouts {
            let cutout: CutoutItem
            if let existing = cutoutMap[dto.id] {
                cutout = existing
                cutout.category = dto.category
                cutout.imagePath = dto.imagePath
                cutout.width = dto.width
                cutout.height = dto.height
            } else {
                cutout = CutoutItem(
                    originalImageHash: dto.originalImageHash,
                    category: dto.category,
                    imagePath: dto.imagePath,
                    width: dto.width,
                    height: dto.height
                )
                cutout.id = dto.id
                context.insert(cutout)
                cutoutMap[dto.id] = cutout
            }
            
            if let linkedID = dto.linkedClothingID, let clothing = clothingMap[linkedID] {
                cutout.linkedClothing = clothing
            }
        }
        
        // Restore Outfits
        let existingOutfits = try context.fetch(FetchDescriptor<Outfit>())
        var outfitMap: [UUID: Outfit] = Dictionary(uniqueKeysWithValues: existingOutfits.map { ($0.id, $0) })
        
        for dto in manifest.outfits {
            let outfit: Outfit
            if let existing = outfitMap[dto.id] {
                outfit = existing
                outfit.note = dto.note
                outfit.snapshotPath = dto.snapshotPath
                // Clear existing items to rebuild? Or merge?
                // Safest to clear and rebuild items as they are owned by Outfit
                if !outfit.items.isEmpty {
                    // This is tricky with SwiftData cascade.
                    // Let's delete old items manually?
                    // For now, assume we just add missing ones or if ID matches update.
                }
            } else {
                outfit = Outfit(note: dto.note, snapshotPath: dto.snapshotPath)
                outfit.id = dto.id
                context.insert(outfit)
                outfitMap[dto.id] = outfit
            }
            
            // Restore Outfit Items
            // First map existing items
            let existingItems = outfit.items
            var itemMap: [UUID: OutfitItem] = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            
            for itemDTO in dto.items {
                let item: OutfitItem
                if let existingItem = itemMap[itemDTO.id] {
                    item = existingItem
                    item.x = itemDTO.x
                    item.y = itemDTO.y
                    item.rotation = itemDTO.rotation
                    item.scale = itemDTO.scale
                    item.zIndex = itemDTO.zIndex
                } else {
                    item = OutfitItem(cutout: nil, x: itemDTO.x, y: itemDTO.y, rotation: itemDTO.rotation, scale: itemDTO.scale, zIndex: itemDTO.zIndex)
                    item.id = itemDTO.id
                    item.outfit = outfit // Relationship
                    // context.insert(item) // Relationship assignment should handle insert
                }
                
                if let cutoutID = itemDTO.cutoutID, let cutout = cutoutMap[cutoutID] {
                    item.cutout = cutout
                }
            }
        }
        
        try context.save()
    }
}
