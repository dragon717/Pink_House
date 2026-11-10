#!/usr/bin/env python3
"""Run the actual value-only wardrobe filter/index on synthetic data, without Simulator.
Excludes SwiftData extraction, SwiftUI layout and image loading; never reads user data.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
def read(name):
    return (ROOT / name).read_text(encoding='utf-8')
def section(text, start, end):
    return text[text.index(start):text.index(end)]

view = read('ItemManager/Views/WardrobeView.swift')
snapshot = section(view, 'struct WardrobeClothingSnapshot:', 'struct WardrobeFilterInput:')
snapshot = snapshot[:snapshot.index('    @MainActor')] + '}\n'
models = read('ItemManager/Clothing.swift')
settings = read('ItemManager/Services/WardrobeStorage/WardrobeStorageSettings.swift')
source = 'import Foundation\nextension String { var appLocalized: String { self } }\n'
source += section(models, 'enum ClothingCondition:', 'enum ClothingDeletionSource:')
source += section(read('ItemManager/Views/MultiDimensionalFilterSheet.swift'), 'enum DepositStatusFilter:', '// MARK: - 多维筛选候选快照')
source += section(settings, 'nonisolated enum WardrobeStorageIconKind:', 'nonisolated enum WardrobeStorageIconUpdate:')
source += section(read('ItemManager/Views/WardrobeStorage/WardrobeStorageInventory.swift'), 'nonisolated enum WardrobeStorageCategory:', 'nonisolated enum WardrobeShoeFilter:')
source += snapshot
source += section(view, 'struct WardrobeFilterInput:', 'private struct WardrobeProjectionCache')
source += section(view, 'enum WardrobeFilterEngine {', 'private struct WardrobeVisibleItemFramePreferenceKey:')
source += section(read('ItemManager/Services/ClothingFilterService.swift'), 'nonisolated enum WardrobeBrandOrder', 'extension ClothingFilterService {')
source += r'''
let shops = (0..<100).map { _ in UUID() }
let tag = UUID()
func row(_ n: Int, types: String = "JSK", brand: UUID? = nil, tagged: Bool = true) -> WardrobeClothingSnapshot {
    let date = Date(timeIntervalSince1970: Double(n))
    return WardrobeClothingSnapshot(id: UUID(), name: "收藏 \(n)", brandID: brand, brandName: "店家",
        tagIDs: tagged ? [tag] : [], tagNames: tagged ? ["心动"] : [], types: types, colors: "粉色", sizes: "M",
        length: "", condition: "全新", accessories: "", note: "", price: 100,
        wardrobeValueAmount: 100, dressValueAmount: 100, stock: 1, reservationKind: .owned,
        sortIndex: n, purchaseDate: date, createdAt: date, updatedAt: date, lastModified: date,
        isDeleted: false, deletedAt: nil)
}
func input(_ brands: Set<UUID>, tags: Set<UUID> = []) -> WardrobeFilterInput {
    WardrobeFilterInput(snapshots: [], searchText: "", selectedTagIDs: tags, selectedBrandIDs: brands,
        selectedTypes: [], selectedColors: [], selectedSizes: [], selectedLengths: [],
        selectedConditions: [], selectedAccessories: [], depositStatusFilterRawValue: "all",
        sortOptionRawValue: "添加时间从晚到早")
}
// Regression checks with independent expected IDs: partitioning, OR within a dimension,
// intersection across dimensions, empty sentinels, clearing filters and rebuilding after edits.
let a = row(1, brand: shops[0]), b = row(2, brand: shops[1], tagged: false)
let c = row(3), shoe = row(4, types: "鞋", brand: shops[0])
let fixture = WardrobeFilterIndex(snapshots: [a, b, c, shoe], cabinets: [])
assert(WardrobeFilterEngine.evaluate(input([shops[0]]), index: fixture).ids == [a.id])
assert(WardrobeFilterEngine.evaluate(input([shops[0], shops[1]]), index: fixture).ids == [b.id, a.id])
assert(WardrobeFilterEngine.evaluate(input([shops[1]], tags: [tag]), index: fixture).ids.isEmpty)
assert(WardrobeFilterEngine.evaluate(input([], tags: [tag]), index: fixture).ids == [c.id, a.id])
let noBrand = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let noTag = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
assert(WardrobeFilterEngine.evaluate(input([noBrand, shops[0]]), index: fixture).ids == [c.id])
assert(WardrobeFilterEngine.evaluate(input([], tags: [noTag, tag]), index: fixture).ids == [b.id])
assert(WardrobeFilterEngine.evaluate(input([]), index: fixture).ids == [c.id, b.id, a.id])
let refreshed = WardrobeFilterIndex(snapshots: [b, c], cabinets: [])
assert(WardrobeFilterEngine.evaluate(input([shops[0]]), index: refreshed).ids.isEmpty)
print("PASS: 8 independent index/filter regression checks")
for size in [10_000, 50_000] {
    let rows = (0..<size).map { row($0, brand: shops[$0 % shops.count]) }
    let start = DispatchTime.now().uptimeNanoseconds
    let index = WardrobeFilterIndex(snapshots: rows, cabinets: [])
    let preparationMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    var samples: [Double] = []
    var total = 0
    for round in 0..<220 {
        let request = input([shops[round % shops.count]], tags: round % 2 == 0 ? [tag] : [])
        let begin = DispatchTime.now().uptimeNanoseconds
        let result = WardrobeFilterEngine.evaluate(request, index: index)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
        assert(result.ids.count == size / shops.count)
        total += result.ids.count
        if round >= 20 { samples.append(ms) }
    }
    samples.sort()
    print(String(format: "rows=%d shops=100 matches=%d index_ms=%.3f warm_p50_ms=%.3f warm_p95_ms=%.3f warm_max_ms=%.3f checksum=%d",
        size, size / shops.count, preparationMS, samples[100], samples[190], samples.last!, total))
}
'''
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Users/sangyu/Applications/Xcode-27.1.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='pink-filter-benchmark-') as temp:
    swift = Path(temp) / 'main.swift'
    binary = Path(temp) / 'benchmark'
    swift.write_text(source, encoding='utf-8')
    subprocess.run(['xcrun', 'swiftc', '-O', str(swift), '-o', str(binary)], check=True, env=env)
    subprocess.run([str(binary)], check=True, env=env)
