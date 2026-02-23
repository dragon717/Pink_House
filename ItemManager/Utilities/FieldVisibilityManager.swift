//
//  FieldVisibilityManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
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
    @AppStorage("fieldOrder") private var fieldOrderRaw: String = ""
    
    @Published var hiddenFields: Set<ClothingField> = []
    @Published var fieldOrder: [ClothingField] = []
    
    init() {
        loadHiddenFields()
        loadFieldOrder()
    }
    
    private func loadHiddenFields() {
        let rawValues = hiddenFieldsRaw.split(separator: ",").map { String($0) }
        hiddenFields = Set(rawValues.compactMap { ClothingField(rawValue: $0) })
    }
    
    private func loadFieldOrder() {
        let rawValues = fieldOrderRaw.split(separator: ",").map { String($0) }
        let savedOrder = rawValues.compactMap { ClothingField(rawValue: $0) }
        
        // Ensure all fields are present
        var finalOrder = savedOrder
        for field in ClothingField.allCases {
            if !finalOrder.contains(field) {
                finalOrder.append(field)
            }
        }
        
        // Remove any invalid/deprecated fields if necessary (though enum helps prevent this)
        finalOrder = finalOrder.filter { ClothingField.allCases.contains($0) }
        
        fieldOrder = finalOrder
    }
    
    private func saveHiddenFields() {
        hiddenFieldsRaw = hiddenFields.map { $0.rawValue }.joined(separator: ",")
    }
    
    private func saveFieldOrder() {
        fieldOrderRaw = fieldOrder.map { $0.rawValue }.joined(separator: ",")
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
    
    func moveField(from source: IndexSet, to destination: Int) {
        var newOrder = fieldOrder
        newOrder.move(fromOffsets: source, toOffset: destination)
        fieldOrder = newOrder
        saveFieldOrder()
        print("FieldVisibilityManager: Order updated to \(fieldOrder.map { $0.rawValue })")
    }
}
