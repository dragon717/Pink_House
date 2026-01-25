//
//  Brand.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/17/26.
//

import Foundation
import SwiftData

@Model
final class Brand {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    
    @Relationship(inverse: \Clothing.brand)
    var clothings: [Clothing]?
    
    init(name: String, colorHex: String = "#FFB6C1") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}
