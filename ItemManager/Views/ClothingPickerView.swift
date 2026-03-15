
import SwiftUI
import SwiftData

struct ClothingPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }, sort: \Clothing.createdAt, order: .reverse) 
    private var allClothings: [Clothing]
    
    @State private var searchText = ""
    var onSelect: (Clothing) -> Void
    
    var filteredClothings: [Clothing] {
        if searchText.isEmpty {
            return allClothings
        } else {
            return allClothings.filter { clothing in
                clothing.name.localizedCaseInsensitiveContains(searchText) ||
                (clothing.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                clothing.types.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredClothings) { clothing in
                    Button {
                        onSelect(clothing)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            // Thumbnail
                            if let firstPath = clothing.imagePaths.first,
                               let uiImage = ImageManager.shared.loadImage(fileName: firstPath) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                    .overlay {
                                        Image(systemName: "tshirt")
                                            .foregroundStyle(.gray)
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(clothing.name.isEmpty ? "未命名" : clothing.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                
                                if let brand = clothing.brand {
                                    Text(brand.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if !clothing.types.isEmpty {
                                Text(clothing.types)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("选择裙装")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索裙装...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
