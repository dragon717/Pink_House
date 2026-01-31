//
//  BackgroundEditView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2026/01/31.
//

import SwiftUI

struct BackgroundEditView: View {
    let originalImage: UIImage
    var onSave: (UIImage) -> Void
    var onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // The Image to be edited
                Image(uiImage: originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale *= delta
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                
                // Overlay Controls
                VStack {
                    Spacer()
                    
                    HStack {
                        Button("重置") {
                            withAnimation {
                                scale = 1.0
                                offset = .zero
                                lastScale = 1.0
                                lastOffset = .zero
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.bottom, 60) // Above bottom bar
                    
                    HStack {
                        Button("取消") {
                            onCancel()
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        
                        Button("完成") {
                            // Render the visible part
                            let cropped = renderImage(size: geometry.size)
                            onSave(cropped)
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    @MainActor
    private func renderImage(size: CGSize) -> UIImage {
        let renderer = ImageRenderer(content:
            ZStack {
                // Use the same background color as the view to capture what's seen
                Color.black
                
                Image(uiImage: originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(width: size.width, height: size.height)
        )
        
        // Use device scale for high quality
        renderer.scale = UIScreen.main.scale
        
        return renderer.uiImage ?? originalImage
    }
}

#Preview {
    BackgroundEditView(originalImage: UIImage(systemName: "star.fill")!) { _ in
        print("Saved")
    } onCancel: {
        print("Cancelled")
    }
}
