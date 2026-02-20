//
//  Item.swift
//  ItemManager
//
//  Created by 木鸟 on 1/15/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date = Date()
    
    init(timestamp: Date = Date()) {
        self.timestamp = timestamp
    }
}
