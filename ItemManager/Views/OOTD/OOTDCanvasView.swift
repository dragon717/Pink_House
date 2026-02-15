
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
    
    // Alert State
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: OutfitItem?
    
    // 工具栏显示状态 - 由父视图控制
    @Binding var isToolbarVisible: Bool
    // 贴纸库显示状态
    @Binding var isStickerLibraryVisible: Bool
    
    // Callback for when canvas content changes (for snapshot updates)
    var onCanvasChange: (() -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate scale to fit the current view port
            let fitScale = min(
                geometry.size.width / canvasWidth,
                geometry.size.height / canvasHeight
            )
            
            // 工具栏宽度（显示时64+padding，隐藏时0）
            let toolbarWidth: CGFloat = isToolbarVisible ? 72 : 0
            
            HStack(spacing: 0) {
                // 左侧工具栏
                if isToolbarVisible {
                    CanvasToolbarView(
                        outfit: outfit,
                        selectedItemId: $selectedItemId,
                        isVisible: $isToolbarVisible,
                        isStickerLibraryVisible: $isStickerLibraryVisible,
                        onDelete: { item in
                            deleteItem(item)
                        },
                        onBringToFront: { item in
                            bringToFront(item)
                        },
                        onBringForward: { item in
                            bringForward(item)
                        },
                        onSendBackward: { item in
                            sendBackward(item)
                        },
                        onSendToBack: { item in
                            sendToBack(item)
                        },
                        onResetTransform: { item in
                            resetTransform(item)
                        }
                    )
                    .padding(.leading, 8)
                    .frame(width: toolbarWidth)
                    .transition(.move(edge: .leading))
                }
                
                // Canvas Area - 占据剩余空间
                ZStack {
                    // 画布内容
                    canvasContent(fitScale: fitScale, geometry: geometry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 顶部贴纸管理栏 - 悬浮在画布上方
                    VStack {
                        CanvasStickerBarView(
                            outfit: outfit,
                            selectedItemId: $selectedItemId,
                            onDeleteItem: { item in
                                deleteItem(item)
                            },
                            onBringToFront: { item in
                                bringToFront(item)
                            }
                        )
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - 画布内容
    private func canvasContent(fitScale: CGFloat, geometry: GeometryProxy) -> some View {
        ZStack {
            // Background
            if outfit.canvasType == "blank" {
                Color.white
                    .frame(width: canvasWidth, height: canvasHeight)
            } else if outfit.canvasType == "custom",
                      let path = outfit.backgroundImagePath,
                      let uiImage = ImageManager.shared.loadImage(fileName: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            } else {
                Image("ootd")
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            }
            
            // Canvas Content
            ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                CanvasItemView(
                    item: item,
                    selectedItemId: $selectedItemId,
                    additionalScale: selectedItemId == item.id ? gestureScale : 1.0,
                    additionalRotation: selectedItemId == item.id ? gestureRotation : .zero,
                    onDelete: {
                        itemToDelete = item
                        showingDeleteAlert = true
                    },
                    onBringToFront: {
                        bringToFront(item)
                    },
                    onBringForward: {
                        bringForward(item)
                    },
                    onSendBackward: {
                        sendBackward(item)
                    },
                    onUpdate: {
                        saveContext()
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
            
            // Counter Display - Top Right
            VStack {
                HStack {
                    Spacer()
                    Text("\(outfit.items.count)/20")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .padding(40)
                }
                Spacer()
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .coordinateSpace(name: "ootdCanvas")
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
                        print("[OOTD] Scale updated for item \(id): \(outfit.items[index].scale)")
                        saveContext()
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
                        print("[OOTD] Rotation updated for item \(id): \(outfit.items[index].rotation)")
                        saveContext()
                    }
            )
        )
        .onTapGesture {
            selectedItemId = nil
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
                itemToDelete = nil
            }
            Button("取消", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("确定要删除这个抠图吗？此操作无法撤销。")
        }
        .onAppear {
            print("[OOTD] Canvas appeared with \(outfit.items.count) items")
            for item in outfit.items {
                print("[OOTD] Item \(item.id): x=\(item.x), y=\(item.y), scale=\(item.scale), rot=\(item.rotation), z=\(item.zIndex)")
            }
        }
    }
    
    
    private func deleteItem(_ item: OutfitItem) {
        if let index = outfit.items.firstIndex(where: { $0.id == item.id }) {
            print("[OOTD] Deleting item \(item.id)")
            outfit.items.remove(at: index)
            selectedItemId = nil
            modelContext.delete(item)
            saveContext()
        }
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
            print("[OOTD] Context saved successfully")
            onCanvasChange?()
        } catch {
            print("[OOTD] Failed to save context: \(error)")
        }
    }
    
    // MARK: - Layer Management
    
    private func bringToFront(_ item: OutfitItem) {
        guard let maxZIndex = outfit.items.map({ $0.zIndex }).max() else { return }
        item.zIndex = maxZIndex + 1
        reindexLayers()
        print("[OOTD] Brought item \(item.id) to front")
        saveContext()
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
        print("[OOTD] Brought item \(item.id) forward")
        saveContext()
    }
    
    private func sendBackward(_ item: OutfitItem) {
        let sortedItems = outfit.items.sorted(by: { $0.zIndex < $1.zIndex })
        guard let index = sortedItems.firstIndex(where: { $0.id == item.id }),
              index > 0 else { return }
        
        let prevItem = sortedItems[index - 1]
        // Swap zIndex
        (item.zIndex, prevItem.zIndex) = (prevItem.zIndex, item.zIndex)
        
        reindexLayers()
        print("[OOTD] Sent item \(item.id) backward")
        saveContext()
    }
    
    private func reindexLayers() {
        // Re-assign zIndexes to be sequential to keep numbers manageable
        let sortedItems = outfit.items.sorted(by: { $0.zIndex < $1.zIndex })
        for (index, item) in sortedItems.enumerated() {
            item.zIndex = index
        }
    }
    
    private func sendToBack(_ item: OutfitItem) {
        guard let minZIndex = outfit.items.map({ $0.zIndex }).min() else { return }
        item.zIndex = minZIndex - 1
        reindexLayers()
        print("[OOTD] Sent item \(item.id) to back")
        saveContext()
    }
    
    private func resetTransform(_ item: OutfitItem) {
        item.rotation = 0
        item.scale = 1.0
        print("[OOTD] Reset transform for item \(item.id)")
        saveContext()
    }
}

// MARK: - 旋转+缩放手柄视图
struct ResizeHandleView: View {
    @Bindable var item: OutfitItem
    let onRotationChange: (Double) -> Void
    let onScaleChange: (Double) -> Void
    let onTransformEnd: () -> Void
    
    @State private var initialAngle: Double = 0
    @State private var initialScale: Double = 1.0
    @State private var isDragging = false
    @State private var startLocation: CGPoint = .zero
    @State private var startDistance: CGFloat = 0
    @State private var currentLocation: CGPoint = .zero
    
    // 贴纸中心点（相对于画布）
    private var itemCenter: CGPoint {
        CGPoint(x: item.x, y: item.y)
    }
    
    var body: some View {
        ZStack {
            // 旋转+缩放按钮 - 使用旋转图标
            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.purple)
                .background(Circle().fill(Color.white))
                .shadow(radius: 2)
                .scaleEffect(isDragging ? 1.2 : 1.0)
                .animation(.spring(response: 0.2), value: isDragging)
        }
        .gesture(
            DragGesture(coordinateSpace: .named("ootdCanvas"))
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        initialAngle = item.rotation
                        initialScale = item.scale
                        startLocation = value.startLocation
                        
                        // 计算初始时手指相对于贴纸中心的位置
                        let deltaX = startLocation.x - itemCenter.x
                        let deltaY = startLocation.y - itemCenter.y
                        startDistance = sqrt(deltaX * deltaX + deltaY * deltaY)
                    }
                    
                    currentLocation = value.location
                    
                    // 计算当前手指相对于贴纸中心的位置
                    let currentDeltaX = currentLocation.x - itemCenter.x
                    let currentDeltaY = currentLocation.y - itemCenter.y
                    let currentDistance = sqrt(currentDeltaX * currentDeltaX + currentDeltaY * currentDeltaY)
                    
                    // 计算旋转角度（atan2返回弧度，转换为角度）
                    let currentAngle = atan2(currentDeltaY, currentDeltaX) * 180 / .pi
                    let startDeltaX = startLocation.x - itemCenter.x
                    let startDeltaY = startLocation.y - itemCenter.y
                    let startAngle = atan2(startDeltaY, startDeltaX) * 180 / .pi
                    
                    // 角度差即为旋转增量
                    var angleDelta = currentAngle - startAngle
                    // 处理角度跨越-180/180的情况
                    if angleDelta > 180 {
                        angleDelta -= 360
                    } else if angleDelta < -180 {
                        angleDelta += 360
                    }
                    
                    let newRotation = initialAngle + Double(angleDelta)
                    onRotationChange(newRotation)
                    
                    // 计算缩放比例（基于距离比例）
                    if startDistance > 0 {
                        let scaleRatio = currentDistance / startDistance
                        let newScale = max(0.3, min(3.0, initialScale * Double(scaleRatio)))
                        onScaleChange(newScale)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    onTransformEnd()
                }
        )
    }
}

// MARK: - CanvasItemView
struct CanvasItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: OutfitItem
    @Binding var selectedItemId: UUID?
    
    var isSelected: Bool {
        selectedItemId == item.id
    }
    
    var additionalScale: CGFloat
    var additionalRotation: Angle
    
    var onDelete: () -> Void
    var onBringToFront: () -> Void
    var onBringForward: () -> Void
    var onSendBackward: () -> Void
    var onUpdate: () -> Void // New callback for drag end
    
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
                        .strokeBorder(Color.pink, lineWidth: 2)
                    
                    // 左上角：向上一层
                    Button(action: onBringForward) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                            .background(Circle().fill(Color.white))
                            .shadow(radius: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: -14, y: -14)
                    
                    // 右上角：删除（带二次确认）
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                            .background(Circle().fill(Color.white))
                            .shadow(radius: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 14, y: -14)
                    
                    // 左下角：向下一层
                    Button(action: onSendBackward) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                            .background(Circle().fill(Color.white))
                            .shadow(radius: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .offset(x: -14, y: 14)
                    
                    // 右下角：旋转+缩放手柄
                    ResizeHandleView(
                        item: item,
                        onRotationChange: { angle in
                            item.rotation = angle
                        },
                        onScaleChange: { scale in
                            item.scale = scale
                        },
                        onTransformEnd: onUpdate
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 14, y: 14)
                    
                    // Name Tag (Bottom Center)
                    if let name = item.cutout?.clothingName, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .offset(y: 40)
                            .fixedSize()
                    }
                }
            }
            .frame(width: 200, height: 200)
            .scaleEffect(item.scale * additionalScale)
            .rotationEffect(Angle(degrees: item.rotation) + additionalRotation)
            .offset(x: item.x + currentOffset.width, y: item.y + currentOffset.height)
        )
        .gesture(
            DragGesture(coordinateSpace: .named("ootdCanvas"))
                .onChanged { value in
                    // 如果有选中的抠图，且不是当前抠图，则不响应
                    if let selectedId = selectedItemId, selectedId != item.id {
                        return
                    }
                    
                    // 如果没有选中的抠图，则选中当前抠图
                    if selectedItemId == nil {
                        selectedItemId = item.id
                    }
                    
                    currentOffset = value.translation
                }
                .onEnded { value in
                    // 如果有选中的抠图，且不是当前抠图，则不响应
                    if let selectedId = selectedItemId, selectedId != item.id {
                        return
                    }
                    
                    item.x += value.translation.width
                    item.y += value.translation.height
                    currentOffset = .zero
                    print("[OOTD] Moved item \(item.id) to (\(item.x), \(item.y))")
                    onUpdate()
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
