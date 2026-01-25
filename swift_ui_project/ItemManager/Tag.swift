//
//  Tag.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    
    @Relationship(inverse: \Clothing.tags)
    var clothings: [Clothing]?
    
    init(name: String, colorHex: String = "#FFB6C1") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}
