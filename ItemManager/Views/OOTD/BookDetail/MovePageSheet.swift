import SwiftUI
import SwiftData

struct MovePageSheet: View {
    let page: Outfit
    let currentBook: BookGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }) private var books: [BookGroup]
    
    var body: some View {
        NavigationStack {
            List(books, id: \.persistentModelID) { targetBook in
                if targetBook.persistentModelID != currentBook.persistentModelID {
                    Button {
                        page.book = targetBook
                        page.lastModified = Date()
                        currentBook.lastModified = Date()
                        targetBook.lastModified = Date()
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        HStack {
                            Text(targetBook.title)
                            Spacer()
                            Text("\((targetBook.pages ?? []).filter({ !$0.isDeleted }).count) 页").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("移动到...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
