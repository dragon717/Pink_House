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
    private static let resetFlag = "--reset-wardrobe-perf"
    private static let generatedPrefix = "性能压测裙装"

    /// DEBUG-only launch-argument seeding entry.
    /// Example:
    /// xcrun simctl launch booted <bundle-id> --seed-wardrobe-perf --count 800 --image-dir "$PROJ/tools/perf-samples/wardrobe-images" --reset-wardrobe-perf
    /// Omit --image-dir to use generated fallback images, or pass an explicit sample image directory.
    @discardableResult
    static func seedIfRequested(modelContext: ModelContext) async -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(seedFlag) else { return false }

        let count = parsedInt(after: countFlag, in: arguments) ?? 800
        let imageDirectory = parsedString(after: imageDirFlag, in: arguments)
        let shouldReset = arguments.contains(resetFlag)

        if shouldReset {
            softDeleteExistingPerfItems(modelContext: modelContext)
        }

        let sourceImages = loadSourceImages(from: imageDirectory)
        let fallbackImages = sourceImages.isEmpty ? [makeFallbackImage(index: 0)] : sourceImages
        guard !fallbackImages.isEmpty else {
            AppLogger.error("WardrobePerfSeedService: no source image available")
            return true
        }

        for index in 0..<count {
            if Task.isCancelled { break }

            let sourceImage = fallbackImages[index % fallbackImages.count]
            let imagePath = ImageManager.shared.saveImage(sourceImage, context: modelContext)
            let clothing = Clothing(
                name: "\(generatedPrefix) #\(index + 1)",
                brand: nil,
                types: ["JSK", "OP", "SK", "小物"][index % 4],
                colors: ["粉色", "蓝色", "白色", "紫色", "黑色"][index % 5],
                sizes: ["S", "M", "L", "均码"][index % 4],
                length: ["短款", "常规", "长款"][index % 3],
                condition: index % 7 == 0 ? "非全新" : "全新",
                accessories: index % 5 == 0 ? "蝴蝶结,KC" : "",
                imagePaths: imagePath.map { [$0] } ?? [],
                isShared: false,
                originalPrice: Decimal(180 + (index % 80) * 10),
                price: Decimal(120 + (index % 120) * 8),
                deposit: index % 6 == 0 ? Decimal(50) : Decimal(0),
                balance: index % 6 == 0 ? Decimal(300 + index % 90) : Decimal(0),
                accessoriesPrice: Decimal(index % 9) * Decimal(12),
                purchaseDate: Calendar.current.date(byAdding: .day, value: -index, to: Date()) ?? Date(),
                isDepositPlan: index % 6 == 0,
                note: "Wardrobe perf seed item \(index + 1)",
                stock: (index % 3) + 1,
                status: .onShelf
            )
            clothing.sortIndex = index
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

    private static func loadSourceImages(from directory: String?) -> [UIImage] {
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
            images.append(resizedToSeedThumbnail(image))
        }
        return images
    }

    private static func resizedToSeedThumbnail(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    private static func makeFallbackImage(index: Int) -> UIImage {
        let targetSize = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)
            UIColor.systemPink.withAlphaComponent(0.18).setFill()
            context.fill(rect)

            let insetRect = rect.insetBy(dx: 28, dy: 28)
            UIColor.systemPink.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: insetRect, cornerRadius: 28).fill()

            let label = "P\(index + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold),
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
