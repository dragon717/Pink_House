//
//  AsyncDownsampledImage.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI

/// A view that asynchronously loads and downsamples an image to the specified size.
/// Optimized for memory usage and list performance.
struct AsyncDownsampledImage<Content: View, Placeholder: View>: View {
    let fileName: String
    let targetSize: CGSize
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    init(
        fileName: String,
        targetSize: CGSize,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.fileName = fileName
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: fileName) {
            // Check in-memory cache first (fast path)
            if let cached = await ImageManager.shared.cachedImage(fileName: fileName, targetSize: targetSize) {
                self.image = cached
                self.isLoading = false
                return
            }
            
            // Load asynchronously
            let loadedImage = await ImageManager.shared.loadImageAsync(fileName: fileName, targetSize: targetSize)
            
            // Update UI on MainActor
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// Convenience init for common usage
extension AsyncDownsampledImage where Content == Image, Placeholder == Color {
    init(fileName: String, size: CGSize) {
        self.init(
            fileName: fileName,
            targetSize: size,
            content: { uiImage in
                Image(uiImage: uiImage)
                    .resizable()
            },
            placeholder: {
                Color.gray.opacity(0.1)
            }
        )
    }
}
