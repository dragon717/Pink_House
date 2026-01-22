
import SwiftUI
import SwiftData

struct OOTDCanvasView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    
    // Selection state
    @State private var selectedItemId: UUID?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("ootd_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .clipped()
                    .ignoresSafeArea()
                
                // Grid or background guide (optional)
            
            ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                CanvasItemView(
                    item: item, 
                    isSelected: selectedItemId == item.id,
                    onDelete: {
                        deleteItem(item)
                    },
                    onBringToFront: {
                        bringToFront(item)
                    },
                    onBringForward: {
                        bringForward(item)
                    },
                    onSendBackward: {
                        sendBackward(item)
                    }
                )
                .onTapGesture {
                    selectedItemId = item.id
                }
            }
        }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemId = nil
        }
    }
    
    private func deleteItem(_ item: OutfitItem) {
        if let index = outfit.items.firstIndex(where: { $0.id == item.id }) {
            outfit.items.remove(at: index)
            selectedItemId = nil
            modelContext.delete(item)
        }
    }
    
    // MARK: - Layer Management
    
    private func bringToFront(_ item: OutfitItem) {
        guard let maxZIndex = outfit.items.map({ $0.zIndex }).max() else { return }
        item.zIndex = maxZIndex + 1
        reindexLayers()
    }
    
    private func bringForward(_ item: OutfitItem) {
        let sortedItems = outfit.items.sorted(by: { $0.zIndex < $1.zIndex })
        guard let index = sortedItems.firstIndex(where: { $0.id == item.id }),
              index < sortedItems.count - 1 else { return }
        
        let nextItem = sortedItems[index + 1]
        // Swap zIndex
        (item.zIndex, nextItem.zIndex) = (nextItem.zIndex, item.zIndex)
        
        // Ensure strictly greater if equal (though swap should handle distinct values)
        if item.zIndex <= nextItem.zIndex {
            item.zIndex = nextItem.zIndex + 1
        }
        
        reindexLayers()
    }
    
    private func sendBackward(_ item: OutfitItem) {
        let sortedItems = outfit.items.sorted(by: { $0.zIndex < $1.zIndex })
        guard let index = sortedItems.firstIndex(where: { $0.id == item.id }),
              index > 0 else { return }
        
        let prevItem = sortedItems[index - 1]
        // Swap zIndex
        (item.zIndex, prevItem.zIndex) = (prevItem.zIndex, item.zIndex)
        
        reindexLayers()
    }
    
    private func reindexLayers() {
        // Re-assign zIndexes to be sequential to keep numbers manageable
        let sortedItems = outfit.items.sorted(by: { $0.zIndex < $1.zIndex })
        for (index, item) in sortedItems.enumerated() {
            item.zIndex = index
        }
    }
}

struct CanvasItemView: View {
    @Bindable var item: OutfitItem
    let isSelected: Bool
    var onDelete: () -> Void
    var onBringToFront: () -> Void
    var onBringForward: () -> Void
    var onSendBackward: () -> Void
    
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
                    ZStack {
                        if isSelected {
                            Rectangle()
                                .strokeBorder(Color.blue, lineWidth: 2)
                            
                            // Delete Button (Top Right)
                            Button(action: onDelete) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .offset(x: 12, y: -12)
                            
                            // Bring to Front (Top Left) - 置顶
                            Button(action: onBringToFront) {
                                Image(systemName: "arrow.up.to.line.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                    .background(Circle().fill(Color.white))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .offset(x: -12, y: -12)
                            
                            // Bring Forward (Bottom Left) - 加一层
                            Button(action: onBringForward) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.green)
                                    .background(Circle().fill(Color.white))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .offset(x: -12, y: 12)
                            
                            // Send Backward (Bottom Right) - 减一层
                            Button(action: onSendBackward) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.orange)
                                    .background(Circle().fill(Color.white))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .offset(x: 12, y: 12)
                        }
                    }
                    .frame(width: 200, height: 200) // Match frame
                    .scaleEffect(item.scale * currentScale)
                    .rotationEffect(Angle(degrees: item.rotation) + currentRotation)
                    .offset(x: item.x + currentOffset.width, y: item.y + currentOffset.height)
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
