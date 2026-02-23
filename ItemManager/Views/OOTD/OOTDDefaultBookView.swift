//
//  OOTDDefaultBookView.swift
//  ItemManager
//
//  OOTD 直达默认手帐视图
//

import SwiftUI
import SwiftData

struct OOTDDefaultBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.sortIndex, order: .forward) private var books: [BookGroup]
    
    @State private var navigationPath = NavigationPath()
    @State private var isSidebarVisible = true
    
    // 获取默认手帐
    private var defaultBook: BookGroup? {
        books.first { $0.title == "默认手帐" } ?? books.first
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                Group {
                    if let book = defaultBook {
                        BookDetailView(
                            book: book,
                            navigationPath: $navigationPath,
                            isSidebarVisible: $isSidebarVisible,
                            onBack: nil,
                            showLeadingToolbar: false
                        )
                    } else {
                        // 如果没有手帐，显示创建提示
                        VStack(spacing: 20) {
                            Image(systemName: "book.pages")
                                .font(.system(size: 60))
                                .foregroundColor(.pink.opacity(0.6))
                            
                            Text("还没有手帐")
                                .font(.title2)
                                .foregroundColor(.primary)
                            
                            Text("请先创建一本手帐")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button("创建默认手帐") {
                                createDefaultBook()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                            .padding(.top)
                        }
                    }
                }
            }
            .navigationTitle("OOTD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
    
    private func createDefaultBook() {
        let book = BookGroup(title: "默认手帐")
        modelContext.insert(book)
        try? modelContext.save()
    }
}

#Preview {
    OOTDDefaultBookView()
}
