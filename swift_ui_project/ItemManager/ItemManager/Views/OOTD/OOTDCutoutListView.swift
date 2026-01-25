
import SwiftUI
import SwiftData

struct OOTDCutoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CutoutItem.timestamp, order: .reverse) private var cutouts: [CutoutItem]
    
    @Binding var isExpanded: Bool
    var onSelect: (CutoutItem) -> Void
    var onAddPhoto: () -> Void
    
    @State private var showErrorAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 5)
            
            if isExpanded {
                // Expanded View (Grid)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        addButton
                        
                        ForEach(cutouts) { item in
                            CutoutThumbnail(imagePath: item.imagePath, onDelete: {
                                deleteCutout(item)
                            })
                            .onTapGesture {
                                onSelect(item)
                                withAnimation { isExpanded = false }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                // Minimized View (Horizontal Scroll)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        addButton
                        
                        ForEach(cutouts.prefix(10)) { item in
                            CutoutThumbnail(imagePath: item.imagePath) // Minimized view usually doesn't show delete button to prevent accidental tap, or we can add it too.
                                .onTapGesture {
                                    onSelect(item)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 5)
        .onTapGesture {
            // Expand on tap if not tapping an item (handled above)
            // But wait, tapping an item adds it. Tapping background expands?
            // Let's add a button to expand or use drag.
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height < -50 {
                        withAnimation { isExpanded = true }
                    } else if value.translation.height > 50 {
                        withAnimation { isExpanded = false }
                    }
                }
        )
        .alert("请稍后再试", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("删除操作暂时无法完成")
        }
    }
    
    private func deleteCutout(_ item: CutoutItem) {
        // Capture the image path before deleting the item
        let imagePath = item.imagePath
        
        // 1. Immediately delete from UI/Context with animation
        withAnimation {
            modelContext.delete(item)
        }
        
        // 2. Handle resource cleanup and persistence asynchronously
        // Using Task ensures this runs on the MainActor (since View is MainActor) but allows the UI loop to proceed
        Task {
            // Decrement ref count / delete image file (file IO is backgrounded internally in ImageManager)
            ImageManager.shared.deleteImage(fileName: imagePath, context: modelContext)
            
            // Save context with error handling
            do {
                try modelContext.save()
            } catch {
                // If save fails, show error alert
                // Note: We don't rollback UI here because delete(item) is a memory operation 
                // and save failure is rare/critical.
                print("Delete failed: \(error)")
                showErrorAlert = true
            }
        }
    }
    
    var addButton: some View {
        Button(action: onAddPhoto) {
            VStack {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                Text("抠图")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(width: 72, height: 72)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct CutoutThumbnail: View {
    let imagePath: String
    var onDelete: (() -> Void)? = nil
    
    @State private var image: UIImage?
    
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Color.gray.opacity(0.1)
                        .frame(width: 72, height: 72)
                        .cornerRadius(8)
                }
            }
            .task {
                if image == nil {
                    // Request downsampled image (72pt * scale)
                    let targetSize = CGSize(width: 72 * displayScale, height: 72 * displayScale)
                    image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: targetSize)
                }
            }
            
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                }
                .offset(x: 5, y: -5)
            }
        }
    }
}
