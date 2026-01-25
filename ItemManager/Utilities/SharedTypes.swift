//
//  SharedTypes.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import Foundation

enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"
    
    var id: String { self.rawValue }
}

