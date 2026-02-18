
import SwiftUI
import SwiftData
import PhotosUI

// MARK: - OOTD Content Area (Canvas + Cutout List)
struct OOTDContentArea: View {
    @Binding var currentOutfit: Outfit?
    @Binding var isListExpanded: Bool
    @Binding var isProcessing: Bool
    let processingMessage: String
    @Binding var isToolbarVisible: Bool
    @Binding var isStickerLibraryVisible: Bool
    let geometry: GeometryProxy
    
    // 翻页相关参数（可选，用于支持翻页功能）
    var currentPageIndex: Int = 0
    var totalPages: Int = 1
    var hasPreviousPage: Bool = false
    var hasNextPage: Bool = false
    var onPreviousPage: (() -> Void)? = nil
    var onNextPage: (() -> Void)? = nil
    
    // Actions
    let onAddToOutfit: (CutoutItem) -> Void
    let onAddPhoto: () -> Void
    let onBatchAdd: ([CutoutItem]) -> Bool
    let onUpdate: () -> Void
    
    var body: some View {
        let isLandscape = geometry.size.width > geometry.size.height
        
        ZStack {
            if isLandscape {
                // Landscape Layout: HStack (Canvas + Sidebar)
                HStack(spacing: 0) {
                    // Canvas Area
                    if let outfit = currentOutfit {
                        OOTDCanvasView(
                            outfit: outfit,
                            isToolbarVisible: $isToolbarVisible,
                            isStickerLibraryVisible: $isStickerLibraryVisible,
                            currentPageIndex: currentPageIndex,
                            totalPages: totalPages,
                            hasPreviousPage: hasPreviousPage,
                            hasNextPage: hasNextPage,
                            onPreviousPage: onPreviousPage ?? {},
                            onNextPage: onNextPage ?? {},
                            onCanvasChange: onUpdate
                        )
                        .id(outfit.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("开始新的穿搭", systemImage: "tshirt.fill")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Right Sidebar (Cutout List) - 贴纸库
                    if isStickerLibraryVisible {
                        OOTDCutoutListView(
                            isExpanded: $isListExpanded,
                            isLandscape: true,
                            onSelect: onAddToOutfit,
                            onAddPhoto: onAddPhoto,
                            onBatchAdd: onBatchAdd
                        )
                        .frame(width: isListExpanded ? 320 : 100) // Width control
                        .background(Color(uiColor: .systemBackground))
                        .transition(.move(edge: .trailing))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isListExpanded)
                        .overlay(alignment: .leading) {
                             // Toggle Handle
                             Button(action: {
                                 withAnimation {
                                     isListExpanded.toggle()
                                 }
                             }) {
                                 Image(systemName: isListExpanded ? "chevron.right" : "chevron.left")
                                     .font(.system(size: 16, weight: .bold))
                                     .foregroundColor(.secondary)
                                     .padding(8)
                                     .background(.ultraThinMaterial)
                                     .clipShape(Circle())
                                     .shadow(radius: 2)
                             }
                             .padding(.leading, -16) // Offset to overlap or sit on edge
                             .offset(x: 10) // Push it a bit inside
                        }
                    }
                }
            } else {
                // Portrait Layout: ZStack (Canvas + Bottom Sheet)
                ZStack {
                    if let outfit = currentOutfit {
                        OOTDCanvasView(
                            outfit: outfit,
                            isToolbarVisible: $isToolbarVisible,
                            isStickerLibraryVisible: $isStickerLibraryVisible,
                            currentPageIndex: currentPageIndex,
                            totalPages: totalPages,
                            hasPreviousPage: hasPreviousPage,
                            hasNextPage: hasNextPage,
                            onPreviousPage: onPreviousPage ?? {},
                            onNextPage: onNextPage ?? {},
                            onCanvasChange: onUpdate
                        )
                        .id(outfit.id)
                    } else {
                        ContentUnavailableView("开始新的穿搭", systemImage: "tshirt.fill")
                    }
                    
                    // 贴纸库 - 底部弹出
                    if isStickerLibraryVisible {
                        VStack {
                            Spacer()
                            OOTDCutoutListView(
                                isExpanded: $isListExpanded,
                                isLandscape: false,
                                onSelect: onAddToOutfit,
                                onAddPhoto: onAddPhoto,
                                onBatchAdd: onBatchAdd
                            )
                            .frame(height: isListExpanded ? geometry.size.height * 0.8 : 200)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isListExpanded)
                        }
                    }
                }
            }
            
            if isProcessing {
                Color.black.opacity(0.4)
                .ignoresSafeArea()
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(processingMessage)
                        .foregroundColor(.white)
                        .padding(.top)
                }
            }
        }
    }
}

// MARK: - Alerts Modifier
struct OOTDAlertsModifier: ViewModifier {
    @Binding var showingRenameAlert: Bool
    @Binding var newName: String
    let onRename: () -> Void
    
    @Binding var showingDeleteCurrentAlert: Bool
    let onDeleteCurrent: () -> Void
    
    @Binding var showingLimitAlert: Bool
    
    @Binding var showingBatchConfirmation: Bool
    let onBatchProcess: () -> Void
    
    @Binding var showingRepairConfirmation: Bool
    let onRepair: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("重命名搭配", isPresented: $showingRenameAlert) {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) { }
                Button("确定", action: onRename)
            }
            .alert("删除当前搭配", isPresented: $showingDeleteCurrentAlert) {
                Button("删除", role: .destructive, action: onDeleteCurrent)
                Button("取消", role: .cancel) { }
            } message: {
                Text("确定要删除当前搭配吗？此操作无法撤销。")
            }
            .alert("数量已达上限", isPresented: $showingLimitAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("每个搭配最多只能添加20个抠图。")
            }
            .alert("批量处理", isPresented: $showingBatchConfirmation) {
                Button("开始扫描", role: .destructive, action: onBatchProcess)
                Button("取消", role: .cancel) {}
            } message: {
                Text("将扫描衣橱中所有裙装并尝试生成抠图。这可能需要一些时间。")
            }
            .alert("修复数据", isPresented: $showingRepairConfirmation) {
                Button("开始深度修复", action: onRepair)
                Button("取消", role: .cancel) {}
            } message: {
                Text("将扫描所有搭配，尝试通过哈希匹配、关联服饰匹配等方式，找回丢失的图片引用。")
            }
    }
}
