//
//  OOTDDefaultBookView.swift
//  ItemManager
//
//  OOTD 直达默认手帐编辑界面
//

import SwiftUI
import SwiftData

// MARK: - 通知名称扩展
extension Notification.Name {
    static let magicStickerPageMoved = Notification.Name("magicStickerPageMoved")
    static let navigateToBook = Notification.Name("navigateToBook")
    static let navigateToBookDetail = Notification.Name("navigateToBookDetail")
}

struct OOTDDefaultBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.sortIndex, order: .forward) private var books: [BookGroup]
    @Query(filter: #Predicate<Outfit> { $0.isDeleted == false }, sort: \Outfit.sortIndex) private var allOutfits: [Outfit]

    @State private var navigationPath = NavigationPath()

    // Toast 状态
    @State private var showingSuccessToast = false
    @State private var successMessage = ""

    // 获取默认手帐（魔法贴纸使用"默认手帐"作为默认名，不借用其他手帐）
    private var defaultBook: BookGroup? {
        books.first { $0.title == "默认手帐" }
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
                            // 直接显示编辑界面（魔法贴纸模式：隐藏工具栏，显示贴纸库）
                            OOTDEditorView(
                                outfit: page,
                                onPageChange: { newOutfit in
                                    // 页面切换时更新导航路径
                                    navigationPath.append(newOutfit)
                                },
                                initialToolbarVisible: false,
                                initialStickerLibraryVisible: true
                            )
                        } else {
                            // 手帐存在但没有书页，显示空状态并允许创建新书页
                            EmptyPageView(book: book)
                        }
                    } else {
                        // 如果没有手帐，自动创建"默认手帐"
                        AutoCreateBookView(onAutoCreate: createDefaultBook)
                    }
                }

                // 成功提示 Toast - 显示在最上层
                if showingSuccessToast {
                    MagicStickerSuccessToast(message: successMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingSuccessToast)
                }
            }
            .navigationTitle("魔法贴纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .magicStickerPageMoved)) { notification in
            if let bookTitle = notification.userInfo?["bookTitle"] as? String,
               let bookID = notification.userInfo?["bookID"] as? UUID {
                // 显示成功提示
                successMessage = "已加入「\(bookTitle)」"
                showingSuccessToast = true

                // 1.5秒后隐藏提示并导航到对应手帐
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showingSuccessToast = false

                    // 发送通知跳转到 OOTD 页面
                    NotificationCenter.default.post(
                        name: .navigateToBook,
                        object: nil,
                        userInfo: ["bookID": bookID, "bookTitle": bookTitle]
                    )

                    // 再延迟一点时间，确保 OOTDView 已经创建后再发送第二次通知
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(
                            name: .navigateToBookDetail,
                            object: nil,
                            userInfo: ["bookID": bookID, "bookTitle": bookTitle]
                        )
                    }
                }
            }
        }
    }

    private func createDefaultBook() {
        // 创建手帐
        let book = BookGroup(title: "默认手帐")
        modelContext.insert(book)

        // 同时创建第一页（空白画布），让用户可以直接进入编辑器
        let firstPage = Outfit(
            note: "OOTD",
            canvasType: "blank",
            book: book
        )
        firstPage.sortIndex = 0
        modelContext.insert(firstPage)

        try? modelContext.save()
    }
}

// MARK: - 成功提示Toast (魔法贴纸专用)
struct MagicStickerSuccessToast: View {
    let message: String

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.pink.opacity(0.9))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 60)
    }
}

// MARK: - 自动创建手帐视图（魔法贴纸无需手动创建）
private struct AutoCreateBookView: View {
    let onAutoCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.pink.opacity(0.6))

            Text("正在准备魔法贴纸...")
                .font(.title2)
                .foregroundColor(.primary)

            ProgressView()
                .scaleEffect(1.2)
                .padding(.top)

            Spacer()
        }
        .onAppear {
            // 自动创建默认手帐，无需用户手动操作
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onAutoCreate()
            }
        }
    }
}

// MARK: - 空书页视图（魔法贴纸自动创建书页）
private struct EmptyPageView: View {
    let book: BookGroup
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.pink.opacity(0.6))

            Text("正在准备新书页...")
                .font(.title3)
                .foregroundStyle(.secondary)

            ProgressView()
                .scaleEffect(1.2)
                .padding(.top)

            Spacer()
        }
        .onAppear {
            // 魔法贴纸模式：自动创建空白书页
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                createNewPage()
            }
        }
    }

    private func createNewPage() {
        let newPage = Outfit(
            note: "OOTD",
            canvasType: "blank",
            book: book
        )
        newPage.sortIndex = 0

        modelContext.insert(newPage)
        try? modelContext.save()
    }
}

#Preview {
    OOTDDefaultBookView()
}
