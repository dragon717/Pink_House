//
//  SpaceBookSidebarView.swift
//  ItemManager
//
//  空间书架侧边栏视图
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SpaceBookSidebarView: View {
    let books: [SpaceBookGroup]
    let selectedBook: SpaceBookGroup?
    let onSelect: (SpaceBookGroup) -> Void
    var isEditing: Bool = false
    @State private var draggingItem: SpaceBookGroup?

    var body: some View {
        let _ = print("[DEBUG] SpaceBookSidebarView - books count: \(books.count), selectedBook: \(selectedBook?.id.uuidString ?? "nil")")
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(books) { book in
                    let _ = print("[DEBUG] Rendering book: \(book.title), id: \(book.id)")
                    if isEditing {
                        // Editing Mode: Draggable
                        editingBookCell(for: book)
                    } else {
                        // Normal Mode: Tappable
                        normalBookCell(for: book)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
        .frame(width: 90)
        .frame(maxHeight: .infinity)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    @ViewBuilder
    private func normalBookCell(for book: SpaceBookGroup) -> some View {
        SpaceBookView(book: book, isSelected: selectedBook?.id == book.id)
            .frame(width: 60, height: 80)
            .scaleEffect(0.4)
            .frame(width: 60, height: 80)
            .contentShape(Rectangle())
            .onTapGesture {
                print("[DEBUG] Book tapped: \(book.title), id: \(book.id)")
                withAnimation {
                    onSelect(book)
                }
            }
            .opacity(book.id == selectedBook?.id ? 1.0 : 0.6)
    }

    @ViewBuilder
    private func editingBookCell(for book: SpaceBookGroup) -> some View {
        SpaceBookView(book: book, isSelected: false)
            .frame(width: 60, height: 80)
            .scaleEffect(0.4)
            .frame(width: 60, height: 80)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(2)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .offset(x: -5, y: 5)
            }
            .onDrag {
                self.draggingItem = book
                return NSItemProvider(object: book.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: SpaceBookSidebarReorderableDropDelegate(item: book, books: books, draggingItem: $draggingItem))
    }
}

// MARK: - Space Book Sidebar Reorderable Drop Delegate

struct SpaceBookSidebarReorderableDropDelegate: DropDelegate {
    let item: SpaceBookGroup
    let books: [SpaceBookGroup]
    @Binding var draggingItem: SpaceBookGroup?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingItem = draggingItem else { return false }

        if let itemProvider = info.itemProviders(for: [.text]).first {
            itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                if let data = data as? Data,
                   let idString = String(data: data, encoding: .utf8),
                   let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        if let sourceIndex = books.firstIndex(where: { $0.id == uuid }),
                           let destinationIndex = books.firstIndex(where: { $0.id == item.id }) {
                            if sourceIndex != destinationIndex {
                                // Update sort indices
                                let minIndex = min(sourceIndex, destinationIndex)
                                let maxIndex = max(sourceIndex, destinationIndex)

                                if sourceIndex < destinationIndex {
                                    // Moving down
                                    for i in minIndex...maxIndex {
                                        if i == sourceIndex {
                                            books[i].sortIndex = destinationIndex
                                        } else {
                                            books[i].sortIndex -= 1
                                        }
                                    }
                                } else {
                                    // Moving up
                                    for i in minIndex...maxIndex {
                                        if i == sourceIndex {
                                            books[i].sortIndex = destinationIndex
                                        } else {
                                            books[i].sortIndex += 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}
