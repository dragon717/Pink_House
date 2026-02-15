//
//  SpaceBookSidebarView.swift
//  ItemManager
//
//  空间书架侧边栏视图
//

import SwiftUI
import SwiftData

struct SpaceBookSidebarView: View {
    let books: [SpaceBookGroup]
    let selectedBook: SpaceBookGroup?
    let onSelect: (SpaceBookGroup) -> Void

    var body: some View {
        let _ = print("[DEBUG] SpaceBookSidebarView - books count: \(books.count), selectedBook: \(selectedBook?.id.uuidString ?? "nil")")
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(books) { book in
                    let _ = print("[DEBUG] Rendering book: \(book.title), id: \(book.id)")
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
}
