//
//  RoundedTextField.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI

struct RoundedTextField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var isRequired: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if isRequired {
                        Text("*")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.leading, 4)
            }
            
            TextField(placeholder, text: $text)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
        }
    }
}

#Preview {
    RoundedTextField(title: "裙子名称", placeholder: "例如：JSK,OP", text: .constant(""), isRequired: true)
        .padding()
}
