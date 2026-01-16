//
//  ImagePickerGrid.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import PhotosUI

struct ImagePickerGrid: View {
    @Binding var imagePaths: [String]
    let maxCount: Int = 9
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择图片 (最多\(maxCount)张，第一张为主图)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Button
                    if imagePaths.count < maxCount {
                        Button(action: {
                            // Placeholder for Image Picker
                        }) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.title)
                                Text("添加")
                                    .font(.caption)
                            }
                            .frame(width: 100, height: 100)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Image List
                    ForEach(Array(imagePaths.enumerated()), id: \.offset) { index, path in
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                            
                            // Delete Button
                            Button(action: {
                                imagePaths.remove(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .padding(4)
                        }
                    }
                }
            }
        }
    }
}
