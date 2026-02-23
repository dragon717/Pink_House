//
//  Brand.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/17/26.
//

import Foundation
import SwiftData

@Model
final class Brand: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#FFB6C1"
    var imagePath: String? = nil // Optional path to brand image

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    @Relationship(deleteRule: .nullify)
    var clothings: [Clothing]? = []

    init(name: String, colorHex: String = "#FFB6C1", imagePath: String? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.imagePath = imagePath
    }
}
