
import SwiftUI
import SwiftData

struct OOTDCanvasView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    
    // Standard Reference Size (Fixed Canvas Resolution)
    // Using 1080x1440 (3:4 aspect ratio) as the standard coordinate system
    private let canvasWidth: CGFloat = 1080
    private let canvasHeight: CGFloat = 1440
    
    // Selection state
    @State private var selectedItemId: UUID?
    
    // Global Gesture State
    @State private var gestureScale: CGFloat = 1.0
    @State private var gestureRotation: Angle = .zero
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate scale to fit the current view port
            let fitScale = min(
                geometry.size.width / canvasWidth,
                geometry.size.height / canvasHeight
            )
            
            ZStack {
                // Background
                Image("ootd_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
                
                // Canvas Content
                ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                    CanvasItemView(
                        item: item, 
                        isSelected: selectedItemId == item.id,
                        additionalScale: selectedItemId == item.id ? gestureScale : 1.0,
                        additionalRotation: selectedItemId == item.id ? gestureRotation : .zero,
                        fitScale: fitScale, // Pass scale to handle gesture conversion
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
            .frame(width: canvasWidth, height: canvasHeight)
            .scaleEffect(fitScale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Center the scaled canvas
            // Global Gestures Area (Canvas Level)
            .contentShape(Rectangle())
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
                            try? modelContext.save()
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
                            try? modelContext.save()
                        }
                )
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        // Background tap to deselect
                    }
            )
            .onTapGesture {
                selectedItemId = nil
            }
        }
    }
    
    private func deleteItem(_ item: OutfitItem) {
        if let index = outfit.items.firstIndex(where: { $0.id == item.id }) {
            outfit.items.remove(at: index)
            selectedItemId = nil
            modelContext.delete(item)
            try? modelContext.save()
        }
    }
    
    // MARK: - Layer Management
    
    private func bringToFront(_ item: OutfitItem) {
        guard let maxZIndex = outfit.items.map({ $0.zIndex }).max() else { return }
        item.zIndex = maxZIndex + 1
        reindexLayers()
        try? modelContext.save()
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
        try? modelContext.save()
    }
    
    private func sendBackward(_ item: OutfitItem) {
        let sortedItems = outfit.items.sorted(by: { $0.zIndex < $1.zIndex })
        guard let index = sortedItems.firstIndex(where: { $0.id == item.id }),
              index > 0 else { return }
        
        let prevItem = sortedItems[index - 1]
        // Swap zIndex
        (item.zIndex, prevItem.zIndex) = (prevItem.zIndex, item.zIndex)
        
        reindexLayers()
        try? modelContext.save()
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: OutfitItem
    let isSelected: Bool
    var additionalScale: CGFloat
    var additionalRotation: Angle
    var fitScale: CGFloat // Needed to adjust drag translation
    
    var onDelete: () -> Void
    var onBringToFront: () -> Void
    var onBringForward: () -> Void
    var onSendBackward: () -> Void
    
    @State private var currentOffset: CGSize = .zero
    @State private var loadedImage: UIImage?
    @State private var isLoading = true // Default true to prevent flash of missing state
    
    var body: some View {
        Group {
            if let uiImage = loadedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else if item.cutout == nil {
                // Data object missing
                missingPlaceholder(text: "数据丢失")
            } else if isLoading {
                ProgressView()
                    .frame(width: 50, height: 50)
            } else {
                // Image file missing
                missingPlaceholder(text: "图片丢失")
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
                    // Divide translation by fitScale to map back to standard coordinate system
                    currentOffset = CGSize(
                        width: value.translation.width / fitScale,
                        height: value.translation.height / fitScale
                    )
                }
                .onEnded { value in
                    item.x += value.translation.width / fitScale
                    item.y += value.translation.height / fitScale
                    currentOffset = .zero
                    try? modelContext.save()
                }
        )
        .task(id: item.cutout?.imagePath) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let cutout = item.cutout, !cutout.imagePath.isEmpty else {
            isLoading = false
            loadedImage = nil
            return
        }
        
        isLoading = true
        // Try async load
        if let image = await ImageManager.shared.loadImageAsync(fileName: cutout.imagePath) {
            loadedImage = image
        } else {
            loadedImage = nil
        }
        isLoading = false
    }
    
    private func missingPlaceholder(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
            
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
