import Foundation
import UIKit
import CryptoKit

@MainActor
enum OOTDCutoutResolver {
    static func resolveCutouts(
        for clothings: [Clothing],
        from allCutouts: [CutoutItem]
    ) -> (found: [CutoutItem], missing: [Clothing]) {
        var found: [CutoutItem] = []
        var missing: [Clothing] = []
        var usedCutoutIDs = Set<UUID>()

        for clothing in clothings {
            if let cutout = resolveSingleCutout(for: clothing, from: allCutouts, excluding: usedCutoutIDs) {
                found.append(cutout)
                usedCutoutIDs.insert(cutout.id)
            } else {
                missing.append(clothing)
            }
        }

        return (found, missing)
    }

    private static func resolveSingleCutout(
        for clothing: Clothing,
        from allCutouts: [CutoutItem],
        excluding usedCutoutIDs: Set<UUID>
    ) -> CutoutItem? {
        if let replacedID = clothing.replacedCutoutID,
           let replaced = allCutouts.first(where: { $0.id == replacedID && !usedCutoutIDs.contains($0.id) }) {
            if replaced.linkedClothingID == nil {
                replaced.linkedClothingID = clothing.id
            }
            if replaced.clothingName != clothing.name {
                replaced.clothingName = clothing.name
            }
            return replaced
        }

        let linkedMatches = allCutouts
            .filter { $0.linkedClothingID == clothing.id && !usedCutoutIDs.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
        if let linked = linkedMatches.first {
            if linked.clothingName != clothing.name {
                linked.clothingName = clothing.name
            }
            return linked
        }

        let clothingPathSet = Set(
            clothing.imagePaths.map { ($0 as NSString).lastPathComponent }.filter { !$0.isEmpty }
        )
        if !clothingPathSet.isEmpty {
            let pathMatches = allCutouts
                .filter {
                    !usedCutoutIDs.contains($0.id) &&
                    clothingPathSet.contains(($0.imagePath as NSString).lastPathComponent)
                }
                .sorted { left, right in
                    let leftScore = (left.linkedClothingID == nil || left.linkedClothingID == clothing.id) ? 1 : 0
                    let rightScore = (right.linkedClothingID == nil || right.linkedClothingID == clothing.id) ? 1 : 0
                    if leftScore != rightScore { return leftScore > rightScore }
                    return left.timestamp > right.timestamp
                }
            if let pathMatch = pathMatches.first {
                if pathMatch.linkedClothingID == nil {
                    pathMatch.linkedClothingID = clothing.id
                }
                if pathMatch.clothingName != clothing.name {
                    pathMatch.clothingName = clothing.name
                }
                return pathMatch
            }
        }

        if let imageHash = hashForClothingImage(clothing),
           let hashMatch = allCutouts
            .filter({ !usedCutoutIDs.contains($0.id) && $0.originalImageHash == imageHash })
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first {
            if hashMatch.linkedClothingID == nil {
                hashMatch.linkedClothingID = clothing.id
            }
            if hashMatch.clothingName != clothing.name {
                hashMatch.clothingName = clothing.name
            }
            return hashMatch
        }

        return nil
    }

    private static func hashForClothingImage(_ clothing: Clothing) -> String? {
        guard let firstPath = clothing.imagePaths.first else { return nil }
        let fileName = (firstPath as NSString).lastPathComponent
        guard !fileName.isEmpty,
              let image = ImageManager.shared.loadImage(fileName: fileName),
              let data = image.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

