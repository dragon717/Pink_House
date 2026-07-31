import Foundation
import UIKit
import Combine

/// Local-only V1 catalog. CloudKit public upload is documented in docs/TIME_HALL_CLOUDKIT_UPLOAD_PLAN.md.
@MainActor
final class TimeHallCatalogStore: ObservableObject {
    static let shared = TimeHallCatalogStore()

    @Published private(set) var catalog: TimeHallCatalogDTO?
    @Published private(set) var treasuredIDs: Set<String> = []

    private let treasureKey = "timeHall.treasured.v1"
    private let imageSubdir = "TimeHall/images"

    private init() {
        loadCatalog()
        treasuredIDs = Set(UserDefaults.standard.stringArray(forKey: treasureKey) ?? [])
    }

    var dresses: [TimeHallDressDTO] {
        catalog?.dresses ?? []
    }

    var collections: [TimeHallCollectionDTO] {
        catalog?.collections ?? []
    }

    var years: [Int] {
        Array(Set(collections.map(\.year))).sorted(by: >)
    }

    func dresses(in collection: TimeHallCollectionDTO) -> [TimeHallDressDTO] {
        let map = Dictionary(uniqueKeysWithValues: dresses.map { ($0.id, $0) })
        return collection.dressIds.compactMap { map[$0] }
    }

    func collections(for year: Int) -> [TimeHallCollectionDTO] {
        collections.filter { $0.year == year }
    }

    func styleBubbles() -> [TimeHallStyleBubble] {
        var counts: [String: Int] = [:]
        for dress in dresses {
            for tag in dress.stylesZH where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { TimeHallStyleBubble(id: $0.key, label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label < rhs.label
            }
    }

    func dresses(withStyle label: String) -> [TimeHallDressDTO] {
        dresses.filter { $0.stylesZH.contains(label) || $0.styles.contains(label) }
    }

    func isTreasured(_ id: String) -> Bool {
        treasuredIDs.contains(id)
    }

    func toggleTreasure(_ id: String) {
        if treasuredIDs.contains(id) {
            treasuredIDs.remove(id)
        } else {
            treasuredIDs.insert(id)
        }
        UserDefaults.standard.set(Array(treasuredIDs), forKey: treasureKey)
    }

    func image(named fileName: String) -> UIImage? {
        let ns = fileName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? nil : ns.pathExtension
        let candidates: [URL?] = [
            Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: imageSubdir),
            Bundle.main.url(forResource: base, withExtension: ext, subdirectory: imageSubdir),
            Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "Resources/\(imageSubdir)"),
            Bundle.main.url(forResource: base, withExtension: ext),
            Bundle.main.url(forResource: fileName, withExtension: nil)
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        // Last resort: scan bundle for matching filename (folder sync layout varies)
        if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
            if let match = urls.first(where: { $0.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame }) {
                return UIImage(contentsOfFile: match.path)
            }
        }
        return nil
    }

    private func loadCatalog() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "TimeHall"),
            Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Resources/TimeHall"),
            Bundle.main.url(forResource: "catalog", withExtension: "json")
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            print("❌ TimeHallCatalogStore: catalog.json missing")
            return
        }
        do {
            let decoded = try JSONDecoder().decode(TimeHallCatalogDTO.self, from: Data(contentsOf: url))
            catalog = decoded
            assert(!decoded.dresses.isEmpty, "TimeHall catalog must contain dresses")
        } catch {
            print("❌ TimeHallCatalogStore: decode failed \(error)")
        }
    }
}