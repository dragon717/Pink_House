#if DEBUG
import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum WardrobePerfSeedService {
    private static let seedFlag = "--seed-wardrobe-perf"
    private static let countFlag = "--count"
    private static let imageDirFlag = "--image-dir"
    private static let imagesPerItemFlag = "--images-per-item"
    private static let accessoriesPerItemFlag = "--accessories-per-item"
    private static let seedImageSizeFlag = "--seed-image-size"
    private static let resetFlag = "--reset-wardrobe-perf"
    private static let generatedPrefix = "性能压测裙装"

    /// DEBUG-only launch-argument seeding entry.
    /// Example:
    /// xcrun simctl launch booted <bundle-id> --seed-wardrobe-perf --count 10000 --images-per-item 20 --accessories-per-item 50 --seed-image-size 2048 --image-dir "$PROJ/tools/perf-samples/wardrobe-images" --reset-wardrobe-perf
    /// Omit --image-dir to use generated fallback images, or pass an explicit sample image directory.
    @discardableResult
    static func seedIfRequested(modelContext: ModelContext) async -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(seedFlag) else { return false }

        let count = parsedInt(after: countFlag, in: arguments) ?? 800
        let imagesPerItem = boundedInt(parsedInt(after: imagesPerItemFlag, in: arguments) ?? 1, min: 1, max: 20)
        let accessoriesPerItem = boundedInt(parsedInt(after: accessoriesPerItemFlag, in: arguments) ?? 0, min: 0, max: 50)
        let seedImageSize = boundedInt(parsedInt(after: seedImageSizeFlag, in: arguments) ?? 512, min: 200, max: 2048)
        let imageDirectory = parsedString(after: imageDirFlag, in: arguments)
        let shouldReset = arguments.contains(resetFlag)

        if shouldReset {
            softDeleteExistingPerfItems(modelContext: modelContext)
        }

        let sourceImages = loadSourceImages(from: imageDirectory, maxDimension: CGFloat(seedImageSize))
        let fallbackImages = sourceImages.isEmpty
            ? (0..<imagesPerItem).map { makeFallbackImage(index: $0, dimension: CGFloat(seedImageSize)) }
            : sourceImages
        guard !fallbackImages.isEmpty else {
            AppLogger.error("WardrobePerfSeedService: no source image available")
            return true
        }
        let seedImagePaths = fallbackImages.compactMap { image in
            ImageManager.shared.saveImage(image, context: modelContext, triggerImageSync: false)
        }

        for index in 0..<count {
            if Task.isCancelled { break }

            let imagePaths = makeSeedImagePaths(
                index: index,
                imagesPerItem: imagesPerItem,
                seedImagePaths: seedImagePaths
            )
            let clothing = Clothing(
                name: "\(generatedPrefix) #\(index + 1)",
                brand: nil,
                types: ["JSK", "OP", "SK", "小物"][index % 4],
                colors: ["粉色", "蓝色", "白色", "紫色", "黑色"][index % 5],
                sizes: ["S", "M", "L", "均码"][index % 4],
                length: ["短款", "常规", "长款"][index % 3],
                condition: index % 7 == 0 ? "非全新" : "全新",
                accessories: index % 5 == 0 ? "蝴蝶结,KC" : "",
                imagePaths: imagePaths,
                isShared: false,
                originalPrice: Decimal(180 + (index % 80) * 10),
                price: Decimal(120 + (index % 120) * 8),
                deposit: index % 6 == 0 ? Decimal(50) : Decimal(0),
                balance: index % 6 == 0 ? Decimal(300 + index % 90) : Decimal(0),
                accessoriesPrice: 0,
                purchaseDate: Calendar.current.date(byAdding: .day, value: -index, to: Date()) ?? Date(),
                isDepositPlan: index % 6 == 0,
                note: "Wardrobe perf seed item \(index + 1)",
                stock: (index % 3) + 1,
                status: .onShelf
            )
            clothing.sortIndex = index
            if accessoriesPerItem > 0 {
                let accessoryItems = makeAccessoryItems(
                    clothingIndex: index,
                    count: accessoriesPerItem,
                    imagePaths: imagePaths
                )
                clothing.accessoryItems = accessoryItems
                clothing.accessoriesPrice = accessoryItems.reduce(Decimal(0)) { $0 + $1.price }
            }
            modelContext.insert(clothing)

            if index % 50 == 49 {
                try? modelContext.save()
                await Task.yield()
            }
        }

        do {
            try modelContext.save()
            FeatureUnlockManager.shared.refreshClothingCountCache(from: modelContext, reason: "wardrobe-perf-seed")
            AppLogger.info("WardrobePerfSeedService: seeded \(count) wardrobe items")
        } catch {
            AppLogger.error("WardrobePerfSeedService: save failed \(error)")
        }

        return true
    }

    private static func parsedInt(after flag: String, in arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
    }

    private static func parsedString(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func boundedInt(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    private static func makeSeedImagePaths(
        index: Int,
        imagesPerItem: Int,
        seedImagePaths: [String]
    ) -> [String] {
        guard !seedImagePaths.isEmpty else { return [] }
        return (0..<imagesPerItem).map { offset in
            seedImagePaths[(index + offset) % seedImagePaths.count]
        }
    }

    private static func makeAccessoryItems(
        clothingIndex: Int,
        count: Int,
        imagePaths: [String]
    ) -> [AccessoryItem] {
        let firstImagePath = imagePaths.first
        return (0..<count).map { index in
            AccessoryItem(
                name: "压测小物 \(clothingIndex + 1)-\(index + 1)",
                price: Decimal((index % 9) + 1) * Decimal(12),
                deposit: Decimal(index % 3) * Decimal(10),
                balance: Decimal(index % 5) * Decimal(18),
                sortIndex: index,
                imagePaths: firstImagePath.map { [$0] }
            )
        }
    }

    private static func softDeleteExistingPerfItems(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { clothing in
            clothing.deletedAt == nil
        })

        guard let existingItems = try? modelContext.fetch(descriptor).filter({ $0.name.hasPrefix(generatedPrefix) }) else { return }
        for item in existingItems {
            item.isDeleted = true
            item.deletedAt = Date()
            item.lastModified = Date()
        }
        try? modelContext.save()
    }

    private static func loadSourceImages(from directory: String?, maxDimension: CGFloat) -> [UIImage] {
        guard let directory, !directory.isEmpty else { return [] }
        let rootURL = URL(fileURLWithPath: directory)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var images: [UIImage] = []
        for case let fileURL as URL in enumerator {
            guard images.count < 64 else { break }
            let ext = fileURL.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic"].contains(ext),
                  let image = UIImage(contentsOfFile: fileURL.path) else { continue }
            images.append(resizedToSeedImage(image, maxDimension: maxDimension))
        }
        return images
    }

    private static func resizedToSeedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func makeFallbackImage(index: Int, dimension: CGFloat) -> UIImage {
        let targetSize = CGSize(width: dimension, height: dimension)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)
            UIColor.systemPink.withAlphaComponent(0.18).setFill()
            context.fill(rect)

            let insetRect = rect.insetBy(dx: 28, dy: 28)
            UIColor.systemPink.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: insetRect, cornerRadius: max(28, dimension * 0.08)).fill()

            let label = "P\(index + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(34, dimension * 0.14), weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let labelSize = label.size(withAttributes: attributes)
            label.draw(
                at: CGPoint(x: (targetSize.width - labelSize.width) / 2, y: (targetSize.height - labelSize.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
#endif
