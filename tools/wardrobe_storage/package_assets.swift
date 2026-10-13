import AppKit
import Foundation

// Run from the repository root: swift tools/wardrobe_storage/package_assets.swift
// ImageGen supplies the cutout alpha. This only slices the production sprite atlas.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("docs/design/wardrobe-storage")
let catalog = root.appendingPathComponent("ItemManager/Assets.xcassets/ThemeSkin/WardrobeStorage")
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1},\"properties\":{\"provides-namespace\":false}}\n".utf8)
    .write(to: catalog.appendingPathComponent("Contents.json"))

func load(_ name: String) throws -> CGImage {
    let data = try Data(contentsOf: source.appendingPathComponent(name))
    guard let bitmap = NSBitmapImageRep(data: data), let image = bitmap.cgImage else {
        throw NSError(domain: "WardrobeStorageAssets", code: 1)
    }
    return image
}

func export(_ image: CGImage, rect: CGRect, name: String) throws {
    guard let crop = image.cropping(to: rect) else {
        throw NSError(domain: "WardrobeStorageAssets", code: 2)
    }
    let folder = catalog.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let bitmap = NSBitmapImageRep(cgImage: crop)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WardrobeStorageAssets", code: 3)
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"))
    let contents: [String: Any] = [
        "images": [["filename": "\(name).png", "idiom": "universal"]],
        "info": ["author": "xcode", "version": 1]
    ]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appendingPathComponent("Contents.json"))
    print("\(name): \(crop.width) × \(crop.height), alpha preserved")
}

let cabinet = try load("cabinet-source.png")
precondition(cabinet.width == 1024 && cabinet.height == 1536)
try export(cabinet, rect: CGRect(x: 122, y: 0, width: 780, height: 281), name: "storage_cabinet_crown")
try export(cabinet, rect: CGRect(x: 122, y: 511, width: 780, height: 253), name: "storage_cabinet_shelf")
try export(cabinet, rect: CGRect(x: 122, y: 1234, width: 780, height: 274), name: "storage_cabinet_base")

let shoes = try load("shoe-sprites-source.png")
precondition(shoes.width == shoes.height && shoes.width % 2 == 0)
let size = shoes.width / 2
for (index, name) in ["storage_shoes_blush", "storage_shoes_sneakers", "storage_shoes_boots", "storage_shoes_black"].enumerated() {
    try export(shoes, rect: CGRect(x: (index % 2) * size, y: (index / 2) * size, width: size, height: size), name: name)
}

let categoryAtlases: [(String, [String])] = [
    ("bag-sprites-source.png", ["storage_bags_blush", "storage_bags_heart", "storage_bags_black", "storage_bags_basket"]),
    ("accessory-sprites-source.png", ["storage_accessories_bow", "storage_accessories_necklace", "storage_accessories_bonnet", "storage_accessories_brooch"]),
    ("beauty-sprites-source.png", ["storage_beauty_perfume", "storage_beauty_lipstick", "storage_beauty_compact", "storage_beauty_cream"]),
    ("lifestyle-sprites-source.png", ["storage_lifestyle_bear", "storage_lifestyle_cup", "storage_lifestyle_journal", "storage_lifestyle_bunny"])
]
for (file, names) in categoryAtlases {
    let atlas = try load(file)
    precondition(atlas.width == atlas.height && atlas.width % 2 == 0)
    let bitmap = NSBitmapImageRep(cgImage: atlas)
    precondition(bitmap.hasAlpha && (bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01,
                 "Sprite atlas requires ImageGen's transparent alpha")
    let side = atlas.width / 2
    for (index, name) in names.enumerated() {
        try export(atlas, rect: CGRect(x: (index % 2) * side, y: (index / 2) * side, width: side, height: side), name: name)
    }
}
