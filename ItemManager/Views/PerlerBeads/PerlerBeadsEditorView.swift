import SwiftUI
import UIKit
import SwiftData

// MARK: - 拼豆编辑器主视图
struct PerlerBeadsEditorView: View {
    // 初始参数
    var sourceImage: UIImage? = nil
    var initialCanvasModel: PixelCanvasModel? = nil
    var existingPattern: PerlerBeadPattern? = nil  // 编辑现有图案
    var onSave: ((PerlerBeadPattern) -> Void)? = nil  // 保存回调

    // 状态
    @State private var canvasModel: PixelCanvasModel
    @State private var toolMode: PixelCanvasView.ToolMode = .brush
    @State private var showGrid = true
    @State private var showMaterialList = false
    @State private var showSettings = false
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var generatedImage: UIImage?
    @State private var isProcessing = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // 返回确认状态
    @State private var showBackConfirmation = false
    @State private var hasUnsavedChanges = true
    
    // 色卡缩放状态
    @State private var paletteScale: CGFloat = 1.0
    private let minPaletteScale: CGFloat = 0.7
    private let maxPaletteScale: CGFloat = 1.2
    
    // 编辑模式状态
    @State private var isEditMode: Bool = false
    
    // 调色板显示状态
    @State private var showPalette: Bool = false
    
    // 保存对话框状态
    @State private var showSaveDialog = false
    @State private var patternName = ""
    @State private var patternType: PerlerPatternType = .perlerBeads

    // 初始化
    init(
        sourceImage: UIImage? = nil,
        initialCanvasModel: PixelCanvasModel? = nil,
        existingPattern: PerlerBeadPattern? = nil,
        onSave: ((PerlerBeadPattern) -> Void)? = nil
    ) {
        self.sourceImage = sourceImage
        self.initialCanvasModel = initialCanvasModel
        self.existingPattern = existingPattern
        self.onSave = onSave

        if let pattern = existingPattern {
            _canvasModel = State(initialValue: pattern.toCanvasModel())
            _patternName = State(initialValue: pattern.name)
            _patternType = State(initialValue: pattern.typeEnum)
        } else if let model = initialCanvasModel {
            _canvasModel = State(initialValue: model)
            _patternName = State(initialValue: "")
            _patternType = State(initialValue: .perlerBeads)
        } else {
            _canvasModel = State(initialValue: PixelCanvasModel())
            _patternName = State(initialValue: "")
            _patternType = State(initialValue: .perlerBeads)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                GeometryReader { geometry in
                    let availableHeight = geometry.size.height
                    let safeAreaBottom = geometry.safeAreaInsets.bottom
                    let width = geometry.size.width
                    
                    // 根据屏幕宽度决定工具栏高度（宽屏一排，窄屏两排）
                    let isWide = width > 500
                    let toolbarHeight: CGFloat = isWide ? 70 : 110
                    // 调色板横向布局，高度固定
                    let paletteHeight: CGFloat = showPalette ? 90 : 0
                    let canvasHeight = availableHeight - toolbarHeight - paletteHeight - safeAreaBottom - 16
                    
                    VStack(spacing: 8) {
                        // 画布区域
                        PixelCanvasView(
                            canvasModel: canvasModel,
                            showGrid: showGrid,
                            isEditable: isEditMode,
                            isEditMode: isEditMode,
                            toolMode: toolMode
                        )
                        .frame(height: max(canvasHeight, 120))
                        .padding(.horizontal, 8)

                        // 颜色调色板（显示时）- 在工具栏上方，固定高度支持滚动
                        if showPalette {
                            ColorPaletteView(canvasModel: canvasModel, scale: paletteScale)
                                .frame(height: paletteHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // 工具栏 - 固定在底部
                        PerlerCanvasToolbar(
                            canvasModel: canvasModel,
                            toolMode: $toolMode,
                            showGrid: $showGrid,
                            isEditMode: $isEditMode,
                            showPalette: $showPalette,
                            onUndo: {
                                canvasModel.undo()
                            },
                            onRedo: {
                                canvasModel.redo()
                            },
                            onClear: {
                                showClearConfirmation()
                            },
                            onFill: {
                                // 填充刷模式在 PixelCanvasView 中处理
                            },
                            onSave: {
                                savePattern()
                            },
                            onShare: {
                                showShareSheet = true
                            },
                            onIron: {
                                canvasModel.toggleIronMode()
                            }
                        )
                        .frame(height: toolbarHeight)
                        .background(.ultraThinMaterial)
                    }
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("\(canvasModel.resolution.description) · \(canvasModel.paletteSize.description)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // 设置按钮
                        Button(action: { showSettings = true }) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.primary)
                        }

                        // 材料清单按钮
                        Button(action: { showMaterialList = true }) {
                            Image(systemName: "list.bullet.clipboard")
                                .foregroundColor(.pink)
                        }
                    }
                }
            }
            // 使用原生导航栏返回按钮实现二次确认
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButtonWithConfirmation(
                        hasUnsavedChanges: hasUnsavedChanges && canvasModel.hasDrawing,
                        hasExistingPattern: existingPattern != nil,
                        onSaveToDatabase: { 
                            if existingPattern != nil || !patternName.isEmpty {
                                savePatternToDatabase()
                            } else {
                                showSaveDialog = true
                            }
                        },
                        onSaveToPhotos: { savePattern() },
                        onDismiss: { dismiss() }
                    )
                }
            }
            // 保存对话框
            .sheet(isPresented: $showSaveDialog) {
                SavePatternSheet(
                    name: $patternName,
                    patternType: $patternType,
                    onSave: {
                        savePatternToDatabase()
                        dismiss()
                    },
                    onCancel: {
                        showSaveDialog = false
                    }
                )
            }
            // 监听编辑模式变化，自动打开/关闭调色板
            .onChange(of: isEditMode) { _, newValue in
                withAnimation(.spring(response: 0.3)) {
                    if newValue {
                        // 进入编辑模式，自动打开调色板
                        showPalette = true
                    } else {
                        // 退出编辑模式，关闭调色板
                        showPalette = false
                    }
                }
            }
            // 材料清单
            .sheet(isPresented: $showMaterialList) {
                MaterialListView(canvasModel: canvasModel)
            }
            // 设置面板
            .sheet(isPresented: $showSettings) {
                EditorSettingsSheet(canvasModel: canvasModel)
            }
            // 分享
            .sheet(isPresented: $showShareSheet) {
                if let image = generatedImage ?? canvasModel.toUIImage() {
                    ShareSheet(items: [image])
                }
            }
            // 保存成功提示
            .overlay {
                if showSaveSuccess {
                    SaveSuccessToast()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showSaveSuccess = false
                                }
                            }
                        }
                }
            }
            // 处理中遮罩
            .overlay {
                if isProcessing {
                    ProcessingOverlay()
                }
            }
        }
        .onAppear {
            // 如果有源图片，自动转换
            if let image = sourceImage {
                processSourceImage(image)
            }
            
            // 监听填充工具完成通知
            NotificationCenter.default.addObserver(
                forName: .fillToolCompleted,
                object: nil,
                queue: .main
            ) { _ in
                // 填充完成后自动切换回画笔
                toolMode = .brush
            }
        }
    }

    // MARK: - 处理源图片
    private func processSourceImage(_ image: UIImage) {
        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let pixelData = PixelImageProcessor.convertImage(
                image,
                to: canvasModel.resolution,
                paletteSize: canvasModel.paletteSize
            )

            DispatchQueue.main.async {
                canvasModel.pixelData = pixelData
                canvasModel.saveToHistory()
                isProcessing = false
            }
        }
    }

    // MARK: - 清空确认
    private func showClearConfirmation() {
        // 使用简单的确认对话框
        let alert = UIAlertController(
            title: "清空画布",
            message: "确定要清空所有内容吗？此操作不可撤销。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { _ in
            canvasModel.clearCanvas()
        })

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }

    // MARK: - 保存图案到相册
    private func savePattern() {
        generatedImage = canvasModel.toUIImage(scale: 20)

        if let image = generatedImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

            withAnimation {
                showSaveSuccess = true
            }
        }
    }
    
    // MARK: - 保存图案到数据库
    private func savePatternToDatabase() {
        // 生成缩略图
        let thumbnail = canvasModel.toUIImage(scale: 4)
        var thumbnailPath: String? = nil
        
        if let thumbnail = thumbnail {
            thumbnailPath = ImageManager.shared.saveImage(thumbnail, context: modelContext)
        }
        
        let pattern: PerlerBeadPattern
        
        if let existing = existingPattern {
            // 更新现有图案
            existing.update(from: canvasModel, name: patternName.isEmpty ? existing.name : patternName)
            if let path = thumbnailPath {
                existing.thumbnailPath = path
            }
            existing.updatedAt = Date()
            existing.lastModified = Date()
            pattern = existing
        } else {
            // 创建新图案
            pattern = PerlerBeadPattern(
                name: patternName.isEmpty ? "未命名\(patternType.rawValue)" : patternName,
                patternType: patternType,
                resolution: canvasModel.resolution,
                paletteSize: canvasModel.paletteSize,
                canvasStyle: canvasModel.canvasStyle,
                pixelData: canvasModel.pixelData,
                paletteSortOrder: canvasModel.paletteSortOrder,
                thumbnailPath: thumbnailPath
            )
            modelContext.insert(pattern)
        }
        
        do {
            try modelContext.save()
            onSave?(pattern)
            
            withAnimation {
                showSaveSuccess = true
            }
        } catch {
            print("Failed to save pattern: \(error)")
        }
    }
}

// MARK: - 带二次确认的返回按钮
struct BackButtonWithConfirmation: View {
    let hasUnsavedChanges: Bool
    let hasExistingPattern: Bool
    let onSaveToDatabase: () -> Void
    let onSaveToPhotos: () -> Void
    let onDismiss: () -> Void
    
    @State private var showConfirmation = false
    
    var body: some View {
        Button {
            if hasUnsavedChanges {
                showConfirmation = true
            } else {
                onDismiss()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text("返回")
                    .font(.system(size: 17))
            }
        }
        .confirmationDialog("确认返回？", isPresented: $showConfirmation, titleVisibility: .visible) {
            if hasExistingPattern {
                Button("保存修改") {
                    onSaveToDatabase()
                    onDismiss()
                }
            } else {
                Button("保存到作品集") {
                    onSaveToDatabase()
                    onDismiss()
                }
            }
            Button("保存到相册") {
                onSaveToPhotos()
                onDismiss()
            }
            Button("直接返回", role: .destructive) {
                onDismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("您的作品尚未保存，返回将丢失当前编辑内容。")
        }
    }
}

// MARK: - 材料清单视图
struct MaterialListView: View {
    let canvasModel: PixelCanvasModel
    @Environment(\.dismiss) private var dismiss

    var materialList: [(beadColor: BeadColor, count: Int)] {
        canvasModel.getMaterialList()
    }

    var body: some View {
        NavigationStack {
            List {
                // 统计摘要
                Section("统计信息") {
                    HStack {
                        StatCard(
                            icon: "circle.grid.2x2",
                            title: "总数量",
                            value: "\(canvasModel.totalBeads)"
                        )

                        StatCard(
                            icon: "paintpalette",
                            title: "颜色种类",
                            value: "\(canvasModel.usedColorCount)"
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // 材料清单
                Section("所需材料") {
                    if materialList.isEmpty {
                        ContentUnavailableView(
                            "暂无材料",
                            systemImage: "cube.box",
                            description: Text("画布是空的，开始创作吧！")
                        )
                    } else {
                        ForEach(materialList.indices, id: \.self) { index in
                            let item = materialList[index]
                            MaterialRow(
                                rank: index + 1,
                                beadColor: item.beadColor,
                                count: item.count
                            )
                        }
                    }
                }

                // 提示
                Section {
                    Text("建议多准备 10-20% 的拼豆数量，以防制作过程中的损耗")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("材料清单")
            .navigationBarTitleDisplayMode(.inline
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        copyMaterialText()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }

    // 生成可分享的文本
    private func generateMaterialText() -> String {
        var text = "🎨 拼豆材料清单\n"
        text += "分辨率: \(canvasModel.resolution.description)\n"
        text += "总数量: \(canvasModel.totalBeads) 颗\n"
        text += "颜色数: \(canvasModel.usedColorCount) 色\n\n"
        text += "📋 详细清单:\n"

        for item in materialList {
            text += "\(item.beadColor.id) \(item.beadColor.name): \(item.count) 颗\n"
        }

        return text
    }
    
    // 复制材料清单文本到剪贴板
    private func copyMaterialText() {
        let text = generateMaterialText()
        UIPasteboard.general.string = text
        
        // 显示复制成功提示
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - 统计卡片
struct StatCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.pink)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - 材料行
struct MaterialRow: View {
    let rank: Int
    let beadColor: BeadColor
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            // 排名
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(rank <= 3 ? .pink : .secondary)
                .frame(width: 24)

            // 颜色样本
            Circle()
                .fill(beadColor.color)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            // 颜色信息
            VStack(alignment: .leading, spacing: 2) {
                Text(beadColor.name)
                    .font(.body)
                Text(beadColor.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 数量
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text("颗")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 编辑器设置面板
struct EditorSettingsSheet: View {
    @Bindable var canvasModel: PixelCanvasModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // 当前设置
                Section("当前配置") {
                    HStack {
                        Text("分辨率")
                        Spacer()
                        Text(canvasModel.resolution.description)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("颜色数量")
                        Spacer()
                        Text(canvasModel.paletteSize.description)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("画布样式")
                        Spacer()
                        Text(canvasModel.canvasStyle.displayName)
                            .foregroundColor(.secondary)
                    }
                }

                // 更改调色板大小
                Section("调整颜色数量") {
                    Picker("颜色数量", selection: Binding(
                        get: { canvasModel.paletteSize },
                        set: { newSize in
                            canvasModel.updatePaletteSize(newSize)
                        }
                    )) {
                        ForEach(PerlerBeadsConfig.PaletteSize.allCases) { size in
                            Text(size.description)
                                .tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("减少颜色数量会自动将超出范围的颜色设为空白")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 操作
                Section("操作") {
                    Button(action: {
                        canvasModel.clearCanvas()
                        dismiss()
                    }) {
                        Label("清空画布", systemImage: "trash")
                            .foregroundColor(.red)
                    }

                    Button(action: {
                        canvasModel.fillCanvas()
                        dismiss()
                    }) {
                        Label("填充当前颜色", systemImage: "paintbrush.fill")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 保存成功提示
struct SaveSuccessToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("已保存到相册")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.top, 8)
    }
}

// MARK: - 处理中遮罩
struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("正在生成拼豆图案...")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
            )
        }
    }
}

// MARK: - 保存图案对话框
struct SavePatternSheet: View {
    @Binding var name: String
    @Binding var patternType: PerlerPatternType
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("输入名称", text: $name)
                }
                
                Section("类型") {
                    Picker("类型", selection: $patternType) {
                        ForEach(PerlerPatternType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    Text("保存后可以在拼豆工坊列表中查看和管理")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("保存图案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave()
                    }
                    .fontWeight(.bold)
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    PerlerBeadsEditorView()
}
