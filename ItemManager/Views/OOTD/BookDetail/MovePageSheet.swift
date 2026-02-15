import SwiftUI
import SwiftData

struct MovePageSheet: View {
    let page: Outfit
    let currentBook: BookGroup
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }) private var books: [BookGroup]
    
    var body: some View {
        NavigationStack {
            List(books) { targetBook in
                if targetBook.id != currentBook.id {
                    Button {
                        page.book = targetBook
                        dismiss()
                    } label: {
                        HStack {
                            Text(targetBook.title)
                            Spacer()
                            Text("\(targetBook.pages.filter({ !$0.isDeleted }).count) 页").foregroundStyle(.secondary)
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
