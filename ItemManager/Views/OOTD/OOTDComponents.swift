
import SwiftUI
import SwiftData
import PhotosUI

// MARK: - OOTD / 魔法贴纸底图配置

enum OOTDCanvasType {
    static let blank = "blank"
    static let mannequin = "mannequin"
    static let custom = "custom"
}

struct OOTDMannequinBackground: Identifiable, Hashable {
    let id: String
    let displayName: String
    let assetName: String
    let avatarCharacterID: AvatarCharacterID?
    let avatarHairStyleID: AvatarHairStyleID

    static let defaultID = "ootd_mannequin_default"
    static let legacyAssetName = "ootd"
    static let shortBobID = "\(AvatarCharacterID.girlV1.rawValue)_short_bob"

    static let all: [OOTDMannequinBackground] = [
        OOTDMannequinBackground(
            id: defaultID,
            displayName: "基础线稿人台",
            assetName: "ootd_mannequin_default"
        ),
        OOTDMannequinBackground(
            id: AvatarCharacterID.girlV1.rawValue,
            displayName: AvatarCharacterID.girlV1.displayName,
            assetName: AvatarCharacterID.girlV1.staticImageName,
            avatarCharacterID: .girlV1
        ),
        OOTDMannequinBackground(
            id: shortBobID,
            displayName: "少女小人·短发",
            assetName: AvatarCharacterID.girlV1.staticImageName,
            avatarCharacterID: .girlV1,
            avatarHairStyleID: .shortBob
        )
    ]

    init(
        id: String,
        displayName: String,
        assetName: String,
        avatarCharacterID: AvatarCharacterID? = nil,
        avatarHairStyleID: AvatarHairStyleID = .defaultLongPink
    ) {
        self.id = id
        self.displayName = displayName
        self.assetName = assetName
        self.avatarCharacterID = avatarCharacterID
        self.avatarHairStyleID = avatarHairStyleID
    }

    static var defaultBackground: OOTDMannequinBackground {
        all[0]
    }

    var selectionSubtitle: String {
        if avatarCharacterID != nil {
            return "\(avatarHairStyleID.displayName)，透明发型层，可参与骨骼动作。"
        }
        return "适合快速开始搭配拼贴。"
    }

    var canvasScale: CGFloat {
        avatarCharacterID == nil ? 1.0 : 0.55
    }

    /// Manifest-gated exposure: only list mannequin choices whose image asset is actually bundled.
    static var available: [OOTDMannequinBackground] {
        all.filter(\.isAvailable)
    }

    private var isAvailable: Bool {
        #if canImport(UIKit)
        if let avatarCharacterID {
            return AvatarStaticImageResolver.isAvailable(
                characterID: avatarCharacterID,
                hairStyleID: avatarHairStyleID
            )
        }
        return UIImage(named: assetName) != nil
        #else
        return avatarCharacterID != nil
        #endif
    }

    static func resolve(_ id: String?) -> OOTDMannequinBackground {
        guard let id,
              let match = all.first(where: { $0.id == id }) else {
            return defaultBackground
        }
        return match
    }

    static func resolvedAssetName(for id: String?) -> String {
        let candidate = resolve(id)
        if UIImage(named: candidate.assetName) != nil {
            return candidate.assetName
        }
        // Compatibility fallback for older builds/data if the new catalog asset is missing.
        if UIImage(named: legacyAssetName) != nil {
            return legacyAssetName
        }
        return candidate.assetName
    }
}

struct OOTDMannequinBackgroundView: View {
    let mannequinAssetID: String?
    var contentMode: ContentMode = .fill
    var opacity: Double = 1
    var isMotionEnabled: Bool = false

    private var background: OOTDMannequinBackground {
        OOTDMannequinBackground.resolve(mannequinAssetID)
    }

    var body: some View {
        Group {
            if let avatarID = background.avatarCharacterID {
                AvatarCharacterView(
                    request: AvatarRenderRequest(
                        characterID: avatarID,
                        action: isMotionEnabled ? .wave : .stickerPresent,
                        expression: .neutral,
                        hairStyleID: background.avatarHairStyleID,
                        preferredBackend: .staticImage,
                        isPaused: !isMotionEnabled
                    ),
                    contentMode: contentMode
                )
                .scaleEffect(background.canvasScale)
            } else {
                image(OOTDMannequinBackground.resolvedAssetName(for: mannequinAssetID))
            }
        }
        .opacity(opacity)
    }

    @ViewBuilder
    private func image(_ name: String) -> some View {
        let base = Image(name).resizable()
        switch contentMode {
        case .fill:
            base.scaledToFill()
        case .fit:
            base.scaledToFit()
        @unknown default:
            base.scaledToFit()
        }
    }
}

struct OOTDBackgroundSelectionSheet: View {
    let currentCanvasType: String
    let currentMannequinAssetID: String?
    let onSelectBlank: () -> Void
    let onSelectMannequin: (OOTDMannequinBackground) -> Void
    let onSelectCustomImage: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var selectedMannequinID: String {
        OOTDMannequinBackground.resolve(currentMannequinAssetID).id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    optionButton(
                        title: "空白书页",
                        subtitle: "使用纯白底图，适合自由拼贴。",
                        systemImage: "square.dashed",
                        isSelected: currentCanvasType == OOTDCanvasType.blank
                    ) {
                        onSelectBlank()
                        dismiss()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("人台")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        let mannequins = OOTDMannequinBackground.available
                        if mannequins.isEmpty {
                            ContentUnavailableView(
                                "暂无可用人台",
                                systemImage: "tshirt",
                                description: Text("当前版本暂未提供可选择的人台底图。")
                            )
                        } else {
                            ForEach(mannequins) { mannequin in
                                Button {
                                    onSelectMannequin(mannequin)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        mannequinThumbnail(mannequin)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(mannequin.displayName)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(mannequin.selectionSubtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if currentCanvasType == OOTDCanvasType.mannequin,
                                           selectedMannequinID == mannequin.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.pink)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(
                                                currentCanvasType == OOTDCanvasType.mannequin && selectedMannequinID == mannequin.id
                                                ? Color.pink.opacity(0.55)
                                                : Color.primary.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    optionButton(
                        title: "图库自定义图片",
                        subtitle: "从图库选择图片，并继续使用 3:4 裁剪。",
                        systemImage: "photo.on.rectangle.angled",
                        isSelected: currentCanvasType == OOTDCanvasType.custom
                    ) {
                        dismiss()
                        DispatchQueue.main.async {
                            onSelectCustomImage()
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("更换底图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func optionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .pink)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.pink : Color.pink.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.pink)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.pink.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mannequinThumbnail(_ mannequin: OOTDMannequinBackground) -> some View {
        if UIImage(named: mannequin.assetName) != nil {
            OOTDMannequinBackgroundView(
                mannequinAssetID: mannequin.id,
                contentMode: .fill
            )
                .frame(width: 52, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        } else {
            Image(systemName: "tshirt")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 70)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

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
