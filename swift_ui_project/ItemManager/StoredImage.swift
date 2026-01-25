//
//  StoredImage.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import Foundation
import SwiftData

@Model
final class StoredImage {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var imageHash: String // SHA256 hash
    var fileName: String
    var refCount: Int
    var createdAt: Date
    var updatedAt: Date
    
    init(imageHash: String, fileName: String) {
        self.id = UUID()
        self.imageHash = imageHash
        self.fileName = fileName
        self.refCount = 1
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
