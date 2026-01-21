
import SwiftUI
import SwiftData

struct OOTDCanvasView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    
    // Selection state
    @State private var selectedItemId: UUID?
    
    var body: some View {
        ZStack {
            Color.white
            
            // Grid or background guide (optional)
            
            ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                CanvasItemView(item: item, isSelected: selectedItemId == item.id)
                    .onTapGesture {
                        selectedItemId = item.id
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemId = nil
        }
    }
}

struct CanvasItemView: View {
    @Bindable var item: OutfitItem
    let isSelected: Bool
    
    @State private var currentOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var currentRotation: Angle = .zero
    
    var body: some View {
        if let cutout = item.cutout, 
           let uiImage = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
            
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200) // Base size, adjusted by scale
                .scaleEffect(item.scale * currentScale)
                .rotationEffect(Angle(degrees: item.rotation) + currentRotation)
                .offset(x: item.x + currentOffset.width, y: item.y + currentOffset.height)
                .overlay(
                    isSelected ? 
                        Rectangle()
                            .strokeBorder(Color.blue, lineWidth: 2)
                            .frame(width: 200, height: 200) // Match frame
                            .scaleEffect(item.scale * currentScale)
                            .rotationEffect(Angle(degrees: item.rotation) + currentRotation)
                            .offset(x: item.x + currentOffset.width, y: item.y + currentOffset.height)
                    : nil
                )
                .gesture(
                    SimultaneousGesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    currentOffset = value.translation
                                }
                                .onEnded { value in
                                    item.x += value.translation.width
                                    item.y += value.translation.height
                                    currentOffset = .zero
                                },
                            MagnificationGesture()
                                .onChanged { value in
                                    currentScale = value
                                }
                                .onEnded { value in
                                    item.scale *= value
                                    currentScale = 1.0
                                }
                        ),
                        RotationGesture()
                            .onChanged { value in
                                currentRotation = value
                            }
                            .onEnded { value in
                                item.rotation += value.degrees
                                currentRotation = .zero
                            }
                    )
                )
        }
    }
}
