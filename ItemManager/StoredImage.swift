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
    var id: UUID = UUID()
    var imageHash: String = "" // SHA256 hash
    var fileName: String = ""
    var refCount: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModified: Date = Date() // iCloud 同步时间戳
    
    init(imageHash: String, fileName: String) {
        self.id = UUID()
        self.imageHash = imageHash
        self.fileName = fileName
        self.refCount = 1
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastModified = Date()
    }
}
