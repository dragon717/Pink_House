//
//  ClothingEditComponents.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
//

import SwiftUI
import Foundation

// MARK: - Data Models

struct AccessoryItemData: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var deposit: Double
    var balance: Double
    var imagePaths: [String]? = nil
}

// MARK: - Reusable Components

struct PriceRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var value: Double
    
    var body: some View {
        HStack {
            if let subtitle = subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(title)
            }
            Spacer()
            TextField("0", value: Binding<Double?>(
                get: { value == 0 ? nil : value },
                set: { value = $0 ?? 0 }
            ), format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("¥")
                .foregroundStyle(.secondary)
        }
    }
}
