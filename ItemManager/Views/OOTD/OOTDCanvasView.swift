
import SwiftUI
import SwiftData

struct OOTDCanvasView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    
    // Selection state
    @State private var selectedItemId: UUID?
    
    // Global Gesture State
    @State private var gestureScale: CGFloat = 1.0
    @State private var gestureRotation: Angle = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Image("ootd_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .clipped()
                    .ignoresSafeArea()
                    // Global Gestures Area (Background)
                    // Gestures moved to container
                
                // Grid or background guide (optional)
            
            ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                CanvasItemView(
                    item: item, 
                    isSelected: selectedItemId == item.id,
                    additionalScale: selectedItemId == item.id ? gestureScale : 1.0,
                    additionalRotation: selectedItemId == item.id ? gestureRotation : .zero,
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
                    if selectedItemId == item.id {
                        selectedItemId = nil
                    } else {
                        selectedItemId = item.id
                    }
                }
            }
        }
        // Move global gestures here to cover everything
        .contentShape(Rectangle()) // Ensure the whole area is tappable
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard selectedItemId != nil else { return }
                        gestureScale = value
                    }
                    .onEnded { value in
                        guard let id = selectedItemId,
                              let index = outfit.items.firstIndex(where: { $0.id == id }) else { return }
                        
                        outfit.items[index].scale *= value
                        gestureScale = 1.0
                    },
                RotationGesture()
                    .onChanged { value in
                        guard selectedItemId != nil else { return }
                        gestureRotation = value
                    }
                    .onEnded { value in
                        guard let id = selectedItemId,
                              let index = outfit.items.firstIndex(where: { $0.id == id }) else { return }
                        
                        outfit.items[index].rotation += value.degrees
                        gestureRotation = .zero
                    }
            )
        )
        // Handle background tap separately to avoid conflict with item tap
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    // Only clear if we didn't tap an item (this is tricky, so we rely on items capturing tap first)
                    // Actually, SwiftUI TapGesture on parent will fire even if child handles it unless child blocks it.
                    // But we want background tap to clear.
                    // Let's rely on hit testing. Items have content. Background is behind.
                    // If we tap an item, its onTapGesture fires.
                    // We need a way to clear selection when tapping EMPTY space.
                }
        )
        .onTapGesture {
            // This will be called if no child view handles the tap
            selectedItemId = nil
        }
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
    var additionalScale: CGFloat
    var additionalRotation: Angle
    
    var onDelete: () -> Void
    var onBringToFront: () -> Void
    var onBringForward: () -> Void
    var onSendBackward: () -> Void
    
    @State private var currentOffset: CGSize = .zero
    // Removed internal scale/rotation states as they are now controlled by parent
    
    var body: some View {
        Group {
            if let cutout = item.cutout, 
               let uiImage = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                // Placeholder for missing image
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
                    
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(item.cutout == nil ? "数据丢失" : "图片丢失")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .frame(width: 200, height: 200) // Base size, adjusted by scale
        .scaleEffect(item.scale * additionalScale)
        .rotationEffect(Angle(degrees: item.rotation) + additionalRotation)
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
            .scaleEffect(item.scale * additionalScale)
            .rotationEffect(Angle(degrees: item.rotation) + additionalRotation)
            .offset(x: item.x + currentOffset.width, y: item.y + currentOffset.height)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    currentOffset = value.translation
                }
                .onEnded { value in
                    item.x += value.translation.width
                    item.y += value.translation.height
                    currentOffset = .zero
                }
        )
    }
}
