//
//  SpaceBookGridView.swift
//  ItemManager
//
//  空间书架网格视图
//

import SwiftUI
import SwiftData

struct SpaceBookGridView: View {
    let books: [SpaceBookGroup]
    let onBookTap: (SpaceBookGroup) -> Void
    let onDelete: (SpaceBookGroup) -> Void
    let onRename: (SpaceBookGroup) -> Void
    let onSetCover: (SpaceBookGroup) -> Void
    var namespace: Namespace.ID?
    var openingBook: SpaceBookGroup?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            if books.isEmpty {
                ThemeSkinEmptyStateSurface {
                    ContentUnavailableView {
                        Label("暂无空间手帐".appLocalized, systemImage: "cube.transparent")
                    } description: {
                        Text("点击右上角 + 创建新的空间手帐".appLocalized)
                    }
                    .foregroundStyle(emptyStateForegroundColor)
                }
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                    ForEach(books) { book in
                        Button {
                            onBookTap(book)
                        } label: {
                            if book.id == openingBook?.id {
                                Color.clear.frame(width: 160, height: 220)
                            } else {
                                SpaceBookView(book: book, namespace: namespace)
                            }
                        }
                        .captureGuideTarget(books.first?.id == book.id ? .spaceBookFirstBookCard : nil)
                        .buttonStyle(BouncingButtonStyle())
                        .contextMenu {
                            Button {
                                onRename(book)
                            } label: {
                                Label("重命名".appLocalized, systemImage: "pencil")
                            }

                            Button {
                                onSetCover(book)
                            } label: {
                                Label("设置封面".appLocalized, systemImage: "photo")
                            }

                            Button(role: .destructive) {
                                onDelete(book)
                            } label: {
                                Label("删除手帐".appLocalized, systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        // 底部悬浮 Dock 避让：空间书架最后一排书会被 Dock 盖住。
        .avoidingBottomDock()
    }
    
    private var emptyStateForegroundColor: some ShapeStyle {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.secondary
    }
}
