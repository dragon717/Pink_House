//
//  SharedTypes.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import Foundation

enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"
    
    var id: String { self.rawValue }
}

enum HomeTab {
    case wardrobe
    case depositPlan
}

