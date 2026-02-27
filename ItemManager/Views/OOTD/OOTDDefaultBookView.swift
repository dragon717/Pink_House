//
//  OOTDDefaultBookView.swift
//  ItemManager
//
//  OOTD 直达默认手帐编辑界面
//

import SwiftUI
import SwiftData

struct OOTDDefaultBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.sortIndex, order: .forward) private var books: [BookGroup]
    @Query(filter: #Predicate<Outfit> { $0.isDeleted == false }, sort: \Outfit.sortIndex) private var allOutfits: [Outfit]
    
    @State private var navigationPath = NavigationPath()
    
    // 获取默认手帐
    private var defaultBook: BookGroup? {
        books.first { $0.title == "默认手帐" } ?? books.first
    }
    
    // 获取默认手帐的第一页
    private var firstPage: Outfit? {
        guard let book = defaultBook else { return nil }
        return allOutfits
            .filter { $0.book?.id == book.id }
            .sorted { $0.sortIndex < $1.sortIndex }
            .first
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                Group {
                    if let book = defaultBook {
                        if let page = firstPage {
                            // 直接显示编辑界面
                            OOTDEditorView(
                                outfit: page,
                                onPageChange: { newOutfit in
                                    // 页面切换时更新导航路径
                                    navigationPath.append(newOutfit)
                                }
                            )
                        } else {
                            // 手帐存在但没有书页，显示空状态并允许创建新书页
                            EmptyPageView(book: book)
                        }
                    } else {
                        // 如果没有手帐，显示创建提示
                        NoBookView(onCreate: createDefaultBook)
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

// MARK: - 无手帐视图
private struct NoBookView: View {
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
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
                onCreate()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .padding(.top)
            
            Spacer()
        }
    }
}

// MARK: - 空书页视图
private struct EmptyPageView: View {
    let book: BookGroup
    @Environment(\.modelContext) private var modelContext
    @State private var showingCreateOptions = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("还没有穿搭书页")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("点击按钮创建新的穿搭书页")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Button {
                showingCreateOptions = true
            } label: {
                Label("新建书页", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .padding(.top)
            
            Spacer()
        }
        .confirmationDialog("选择画布类型", isPresented: $showingCreateOptions) {
            Button("人台画布") {
                addNewPage(canvasType: "mannequin")
            }
            Button("空白画布") {
                addNewPage(canvasType: "blank")
            }
            Button("取消", role: .cancel) {}
        }
    }
    
    private func addNewPage(canvasType: String) {
        // 查询当前手帐的所有书页以确定sortIndex
        // 使用book.id进行过滤，避免在Predicate中捕获外部变量
        let bookID = book.id
        let descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate<Outfit> { outfit in
                outfit.book?.id == bookID && outfit.isDeleted == false
            },
            sortBy: [SortDescriptor(\Outfit.sortIndex, order: .reverse)]
        )
        let existingPages = (try? modelContext.fetch(descriptor)) ?? []
        let maxSortIndex = existingPages.first?.sortIndex ?? 0
        
        let newPage = Outfit(
            note: "新书页 \(Date().formatted(date: .numeric, time: .shortened))",
            canvasType: canvasType,
            book: book
        )
        newPage.sortIndex = maxSortIndex + 1
        
        modelContext.insert(newPage)
        try? modelContext.save()
    }
}

#Preview {
    OOTDDefaultBookView()
}
