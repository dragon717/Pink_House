//
//  Tag.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import Foundation
import SwiftData

@Model
final class Tag: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#FFB6C1"

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    @Relationship(deleteRule: .nullify)
    var clothings: [Clothing]? = []

    init(name: String, colorHex: String = "#FFB6C1") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}
