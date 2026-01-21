
import SwiftUI
import SwiftData

struct OOTDCutoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CutoutItem.timestamp, order: .reverse) private var cutouts: [CutoutItem]
    
    var onSelect: (CutoutItem) -> Void
    var onAddPhoto: () -> Void
    
    @State private var isExpanded: Bool = false
    
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
                            CutoutThumbnail(item: item)
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
                            CutoutThumbnail(item: item)
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
    let item: CutoutItem
    
    var body: some View {
        if let image = ImageManager.shared.loadImage(fileName: item.imagePath) {
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
            Color.gray
                .frame(width: 72, height: 72)
                .cornerRadius(8)
        }
    }
}
