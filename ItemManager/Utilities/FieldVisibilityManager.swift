//
//  FieldVisibilityManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/31/26.
//

import SwiftUI
import Combine

enum ClothingField: String, CaseIterable, Identifiable {
    case types = "types"
    case colors = "colors"
    case sizes = "sizes"
    case length = "length"
    case condition = "condition"
    case accessories = "accessories"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .types: return "类型"
        case .colors: return "颜色"
        case .sizes: return "尺码"
        case .length: return "衣长"
        case .condition: return "状况"
        case .accessories: return "小物"
        }
    }
}

class FieldVisibilityManager: ObservableObject {
    static let shared = FieldVisibilityManager()
    
    @AppStorage("hiddenFields") private var hiddenFieldsRaw: String = ""
    
    @Published var hiddenFields: Set<ClothingField> = []
    
    init() {
        loadHiddenFields()
    }
    
    private func loadHiddenFields() {
        let rawValues = hiddenFieldsRaw.split(separator: ",").map { String($0) }
        hiddenFields = Set(rawValues.compactMap { ClothingField(rawValue: $0) })
    }
    
    private func saveHiddenFields() {
        hiddenFieldsRaw = hiddenFields.map { $0.rawValue }.joined(separator: ",")
    }
    
    func isVisible(_ field: ClothingField) -> Bool {
        return !hiddenFields.contains(field)
    }
    
    func toggleVisibility(_ field: ClothingField) {
        if hiddenFields.contains(field) {
            hiddenFields.remove(field)
        } else {
            hiddenFields.insert(field)
        }
        saveHiddenFields()
    }
}
