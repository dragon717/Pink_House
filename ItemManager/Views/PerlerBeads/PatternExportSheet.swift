import SwiftUI
import UIKit

// MARK: - 耗材项视图
struct MaterialItemView: View {
    let color: BeadColor
    let count: Int
    
    var body: some View {
        VStack(spacing: 6) {
            // 颜色圆点
            Circle()
                .fill(Color(color.uiColor))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            // 色号
            Text(color.id)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
            
            // 数量
            Text("×\(count)")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(width: 50)
    }
}

// MARK: - 图纸导出设置
struct PatternExportSettings {
    var showGrid: Bool = true
    var showGuidelines: Bool = true
    var showRowColLabels: Bool = true
    var showColorIds: Bool = true        // 格子上显示耗材型号
    var showMaterials: Bool = true      // 顶部显示耗材列表
    var showImageSize: Bool = true
    var showBeadCount: Bool = true
    var showWatermark: Bool = true
    var watermarkText: String = ""
    
    init() {
        // 默认水印内容：少女心愿 + 当前日期
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        let dateString = formatter.string(from: Date())
        self.watermarkText = "少女心愿IOS APP#\(dateString)"
    }
}

// MARK: - 图纸导出设置Sheet
struct PatternExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var canvasModel: PixelCanvasModel
    
    @State private var settings = PatternExportSettings()
    @State private var previewImage: UIImage?
    @State private var isGenerating = false
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var isSharing = false
    
    // 预览缩放和拖动状态
    @State private var previewScale: CGFloat = 1.0
    @State private var previewOffset: CGSize = .zero
    @State private var lastPreviewScale: CGFloat = 1.0
    @State private var lastPreviewOffset: CGSize = .zero
    
    // 导出图片
    private var exportedImage: UIImage? {
        previewImage
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 设置选项区域
                    settingsSection()
                    
                    // 预览区域
                    previewSection()
                    
                    // 底部按钮
                    actionButtons()
                }
                .padding()
            }
            .navigationTitle("图纸设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("好啦") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = exportedImage {
                    ShareSheet(items: [image])
                }
            }
            .overlay {
                if showSaveSuccess {
                    SaveSuccessToast(message: "已保存到相册")
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
            .onAppear {
                generatePreview()
            }
        }
    }
    
    // MARK: - 设置选项区域
    private func settingsSection() -> some View {
        VStack(spacing: 16) {
            // 显示选项
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Toggle("展示网格", isOn: $settings.showGrid)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                Toggle("展示参考线", isOn: $settings.showGuidelines)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                Toggle("展示行列标签", isOn: $settings.showRowColLabels)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                Toggle("展示色号", isOn: $settings.showColorIds)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                Toggle("展示耗材", isOn: $settings.showMaterials)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                Toggle("展示图像尺寸", isOn: $settings.showImageSize)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                Toggle("展示颗粒数", isOn: $settings.showBeadCount)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
            }
            
            Divider()
            
            // 水印设置
            VStack(alignment: .leading, spacing: 8) {
                Toggle("水印设置", isOn: $settings.showWatermark)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                
                if settings.showWatermark {
                    HStack {
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                        TextField("输入水印文字", text: $settings.watermarkText)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - 预览区域
    private func previewSection() -> some View {
        VStack(spacing: 16) {
            // 耗材列表（在预览容器上方）
            if settings.showMaterials {
                materialsSection()
            }
            
            // 预览图容器（只包含拼豆图，包含行列标签）
            GeometryReader { geometry in
                let containerSize = geometry.size
                
                ZStack {
                    if let image = previewImage {
                        // 使用矢量图渲染（PDF或原生绘制）
                        PatternPreviewView(
                            canvasModel: canvasModel,
                            settings: settings,
                            size: containerSize
                        )
                        .scaleEffect(previewScale)
                        .offset(previewOffset)
                        .gesture(
                            SimultaneousGesture(
                                // 双指缩放
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastPreviewScale
                                        lastPreviewScale = value
                                        previewScale = min(max(previewScale * delta, 0.5), 10.0)
                                    }
                                    .onEnded { _ in
                                        lastPreviewScale = 1.0
                                    },
                                // 单指拖动
                                DragGesture()
                                    .onChanged { value in
                                        previewOffset = CGSize(
                                            width: lastPreviewOffset.width + value.translation.width,
                                            height: lastPreviewOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastPreviewOffset = previewOffset
                                    }
                            )
                        )
                    } else if isGenerating {
                        ProgressView("生成预览中...")
                    } else {
                        Text("无法生成预览")
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                // 双击重置
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        previewScale = 1.0
                        previewOffset = .zero
                        lastPreviewScale = 1.0
                        lastPreviewOffset = .zero
                    }
                }
            }
            .frame(minHeight: 400)
            
            // 缩放提示和尺寸信息
            HStack(spacing: 20) {
                // 缩放提示
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                    Text("双击重置")
                        .font(.caption2)
                }
                .foregroundColor(.gray.opacity(0.6))
                
                if settings.showImageSize {
                    Label("\(canvasModel.resolution.rawValue)×\(canvasModel.resolution.rawValue)", systemImage: "ruler")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                if settings.showBeadCount {
                    Label("\(canvasModel.totalBeadCount)颗", systemImage: "circle.grid.2x2")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    // MARK: - 耗材列表区域
    private func materialsSection() -> some View {
        let usedColors = canvasModel.usedColors
        guard !usedColors.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // 标题
                HStack {
                    Text("耗材对照")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
                
                // 耗材网格
                FlowLayout(spacing: 16) {
                    ForEach(usedColors.sorted(by: { $0.key < $1.key }), id: \.key) { colorIndex, count in
                        if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                            let color = canvasModel.palette[colorIndex]
                            MaterialItemView(color: color, count: count)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        )
    }
    
    // MARK: - 底部按钮
    private func actionButtons() -> some View {
        VStack(spacing: 12) {
            // 分享图片按钮
            Button {
                Task {
                    await shareImageAsync()
                }
            } label: {
                HStack {
                    Image(systemName: "photo")
                    Text("分享图片")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.pink)
                .cornerRadius(12)
            }
            .disabled(isSharing)
            
            // 分享PDF按钮（矢量图）
            Button {
                Task {
                    await sharePDFAsync()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text("分享PDF（矢量图）")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 1.0, green: 0.41, blue: 0.71)) // 莫妮卡深粉
                .cornerRadius(12)
            }
            .disabled(isSharing)
            
            // 保存按钮
            Button {
                saveToPhotos()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存到相册")
                }
                .font(.headline)
                .foregroundColor(.pink)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.pink.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(isSharing)
        }
        .overlay {
            if isSharing {
                CatPawLoadingView(message: "生成中...")
                    .transition(.opacity)
            }
        }
    }
    
    // MARK: - 分享图片（异步）
    private func shareImageAsync() async {
        await MainActor.run { isSharing = true }
        
        // 在后台线程生成图片
        let image = await Task.detached(priority: .userInitiated) {
            return self.generatePatternImage()
        }.value
        
        await MainActor.run { isSharing = false }
        
        guard let image = image else { return }
        
        // 先关闭当前sheet，再显示分享界面
        dismiss()
        
        // 稍微延迟以确保sheet完全关闭
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
        
        await MainActor.run {
            let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(activityVC, animated: true)
            }
        }
    }
    
    // MARK: - 分享PDF（矢量图，异步）
    private func sharePDFAsync() async {
        await MainActor.run { isSharing = true }
        
        // 在后台线程生成PDF
        let pdfData = await Task.detached(priority: .userInitiated) {
            return self.generatePatternPDF()
        }.value
        
        await MainActor.run { isSharing = false }
        
        guard let pdfData = pdfData else { return }
        
        // 保存到临时文件
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("拼豆图纸.pdf")
        try? pdfData.write(to: tempURL)
        
        // 先关闭当前sheet，再显示分享界面
        dismiss()
        
        // 稍微延迟以确保sheet完全关闭
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
        
        await MainActor.run {
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(activityVC, animated: true)
            }
        }
    }
    
    // MARK: - 生成预览
    private func generatePreview() {
        isGenerating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = generatePatternImage()
            
            DispatchQueue.main.async {
                previewImage = image
                isGenerating = false
            }
        }
    }
    
    // MARK: - 生成图纸图片（优化内存使用）
    private func generatePatternImage() -> UIImage? {
        let size = canvasModel.resolution.rawValue
        // 根据分辨率动态调整格子大小，确保清晰度
        let cellSize: CGFloat = size <= 32 ? 80 : (size <= 64 ? 50 : 35)
        let labelSize: CGFloat = settings.showRowColLabels ? 60 : 0
        let margin: CGFloat = 40
        let headerHeight: CGFloat = settings.showMaterials ? 240 : 80
        let footerHeight: CGFloat = 80
        
        let canvasWidth = CGFloat(size) * cellSize
        let canvasHeight = CGFloat(size) * cellSize
        let imageWidth = max(canvasWidth + labelSize + margin * 2, 400)
        let imageHeight = canvasHeight + labelSize + headerHeight + footerHeight + margin * 2
        
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        
        // 使用较低的分辨率渲染以节省内存
        let scale: CGFloat = size > 100 ? 1.0 : 2.0
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // 绘制背景
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))
        
        var currentY: CGFloat = margin
        
        // 标题区域（当不显示水印时显示默认标题）
        if !settings.showWatermark || settings.watermarkText.isEmpty {
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.gray
            ]
            let title = "拼豆图纸"
            let titleSize = (title as NSString).size(withAttributes: titleAttributes)
            let titleRect = CGRect(
                x: (imageWidth - titleSize.width) / 2,
                y: currentY,
                width: titleSize.width,
                height: titleSize.height
            )
            (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)
            currentY += titleSize.height + 10
        }
        
        // 绘制耗材列表
        if settings.showMaterials {
            currentY = drawMaterialsSection(at: currentY, width: imageWidth, margin: margin)
            currentY += 60
        }
        
        // 绘制画布区域背景
        let canvasRect = CGRect(
            x: margin + labelSize,
            y: currentY + labelSize,
            width: canvasWidth,
            height: canvasHeight
        )
        
        // 绘制行列标签
        if settings.showRowColLabels {
            drawRowColLabels(at: currentY, canvasWidth: canvasWidth, canvasHeight: canvasHeight, cellSize: cellSize, margin: margin)
        }
        
        // 绘制参考线（每10格）
        if settings.showGuidelines {
            drawGuidelines(in: canvasRect, size: size, cellSize: cellSize)
        }
        
        // 优化：批量绘制相同颜色的格子
        var colorRects: [Int: [CGRect]] = [:]
        for y in 0..<size {
            for x in 0..<size {
                let colorIndex = canvasModel.getPixel(at: x, y: y)
                let rect = CGRect(
                    x: canvasRect.origin.x + CGFloat(x) * cellSize,
                    y: canvasRect.origin.y + CGFloat(y) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                colorRects[colorIndex, default: []].append(rect)
            }
        }
        
        // 批量绘制颜色块
        for (colorIndex, rects) in colorRects {
            if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                context.setFillColor(canvasModel.palette[colorIndex].uiColor.cgColor)
                for rect in rects {
                    context.fill(rect)
                }
            } else {
                context.setFillColor(UIColor(white: 0.97, alpha: 1.0).cgColor)
                for rect in rects {
                    context.fill(rect)
                }
            }
        }
        
        // 绘制耗材型号（在有色格子上）
        if settings.showColorIds {
            for y in 0..<size {
                for x in 0..<size {
                    let colorIndex = canvasModel.getPixel(at: x, y: y)
                    if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                        let rect = CGRect(
                            x: canvasRect.origin.x + CGFloat(x) * cellSize,
                            y: canvasRect.origin.y + CGFloat(y) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )
                        
                        let colorId = canvasModel.palette[colorIndex].id
                        let fontSize = min(cellSize * 0.35, 16)
                        
                        // 根据背景色亮度决定文字颜色
                        let bgColor = canvasModel.palette[colorIndex]
                        let brightness = bgColor.brightness
                        let textColor = brightness > 0.6 
                            ? UIColor.black.withAlphaComponent(0.7) 
                            : UIColor.white.withAlphaComponent(0.9)
                        
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                            .foregroundColor: textColor
                        ]
                        let textSize = (colorId as NSString).size(withAttributes: attributes)
                        
                        // 只在格子足够大时显示文字
                        if textSize.width < rect.width - 4 && textSize.height < rect.height - 4 {
                            let textRect = CGRect(
                                x: rect.midX - textSize.width / 2,
                                y: rect.midY - textSize.height / 2,
                                width: textSize.width,
                                height: textSize.height
                            )
                            (colorId as NSString).draw(in: textRect, withAttributes: attributes)
                        }
                    }
                }
            }
        }
        
        // 绘制网格（优化：批量绘制）
        if settings.showGrid {
            context.setStrokeColor(UIColor.lightGray.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(0.5)
            for i in 0...size {
                let x = canvasRect.origin.x + CGFloat(i) * cellSize
                let y = canvasRect.origin.y + CGFloat(i) * cellSize
                // 垂直线
                context.move(to: CGPoint(x: x, y: canvasRect.origin.y))
                context.addLine(to: CGPoint(x: x, y: canvasRect.maxY))
                // 水平线
                context.move(to: CGPoint(x: canvasRect.origin.x, y: y))
                context.addLine(to: CGPoint(x: canvasRect.maxX, y: y))
            }
            context.strokePath()
        }
        
        // 绘制外边框
        context.setStrokeColor(UIColor.gray.cgColor)
        context.setLineWidth(1)
        context.stroke(canvasRect)
        
        // 绘制 App Logo 和名字（画布内部左上角）
        drawAppLogoInExport(in: canvasRect, context: context)
        
        // 绘制斜着多列水印（在画布上方）
        if settings.showWatermark && !settings.watermarkText.isEmpty {
            drawDiagonalWatermark(in: canvasRect, text: settings.watermarkText)
        }
        
        // 绘制底部信息
        currentY = canvasRect.maxY + 10
        drawFooter(at: currentY, width: imageWidth, margin: margin)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - 绘制斜着多列水印
    private func drawDiagonalWatermark(in rect: CGRect, text: String) {
        let context = UIGraphicsGetCurrentContext()!
        
        // 保存当前图形状态
        context.saveGState()
        
        // 设置水印文字属性
        let fontSize: CGFloat = 48  // 更大水印字体
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.gray.withAlphaComponent(0.12)
        ]
        
        let textSize = (text as NSString).size(withAttributes: attributes)
        let spacingX: CGFloat = textSize.width + 200  // 增大水平间距
        let spacingY: CGFloat = textSize.height + 150 // 增大垂直间距
        
        // 计算需要多少行/列才能覆盖整个画布
        let diagonalLength = sqrt(rect.width * rect.width + rect.height * rect.height)
        let cols = Int(diagonalLength / spacingX) + 3
        let rows = Int(diagonalLength / spacingY) + 3
        
        // 在画布区域内裁剪
        context.addRect(rect)
        context.clip()
        
        // 旋转坐标系 -45度
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -45 * .pi / 180)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        
        // 绘制多列水印
        for row in -rows/2..<rows/2 {
            for col in -cols/2..<cols/2 {
                let x = rect.midX + CGFloat(col) * spacingX + CGFloat(row % 2) * (spacingX / 2)
                let y = rect.midY + CGFloat(row) * spacingY
                
                let textRect = CGRect(
                    x: x - textSize.width / 2,
                    y: y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (text as NSString).draw(in: textRect, withAttributes: attributes)
            }
        }
        
        // 恢复图形状态
        context.restoreGState()
    }
    
    // MARK: - 绘制 App Logo（导出图片用）
    private func drawAppLogoInExport(in rect: CGRect, context: CGContext) {
        let iconSize: CGFloat = 48
        let iconX = rect.origin.x + 16
        let iconY = rect.origin.y + 16
        
        // 尝试加载 AppIcon
        if let appIcon = UIImage(named: "AppIcon"), let cgImage = appIcon.cgImage {
            // 绘制 AppIcon
            let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
            context.draw(cgImage, in: iconRect)
        } else {
            // 备用：绘制粉色心形
            drawHeart(in: context, at: CGPoint(x: iconX + iconSize/2, y: iconY + iconSize/2), size: iconSize)
        }
        
        // 绘制 App 名字
        let appName = "少女心愿"
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: UIColor.darkGray
        ]
        let nameSize = (appName as NSString).size(withAttributes: nameAttributes)
        (appName as NSString).draw(
            at: CGPoint(x: iconX + iconSize + 12, y: iconY + (iconSize - nameSize.height) / 2),
            withAttributes: nameAttributes
        )
    }
    
    // 绘制心形（备用）
    private func drawHeart(in context: CGContext, at center: CGPoint, size: CGFloat) {
        let radius = size / 2
        
        context.beginPath()
        context.move(to: CGPoint(x: center.x, y: center.y + radius * 0.3))
        
        // 左侧曲线
        context.addCurve(
            to: CGPoint(x: center.x - radius * 0.8, y: center.y - radius * 0.2),
            control1: CGPoint(x: center.x - radius * 0.8, y: center.y + radius * 0.6),
            control2: CGPoint(x: center.x - radius * 0.8, y: center.y - radius * 0.2)
        )
        
        // 左上圆弧
        context.addArc(
            center: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.2),
            radius: radius * 0.4,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
        )
        
        // 右上圆弧
        context.addArc(
            center: CGPoint(x: center.x + radius * 0.4, y: center.y - radius * 0.2),
            radius: radius * 0.4,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
        )
        
        // 右侧曲线
        context.addCurve(
            to: CGPoint(x: center.x, y: center.y + radius * 0.3),
            control1: CGPoint(x: center.x + radius * 0.8, y: center.y - radius * 0.2),
            control2: CGPoint(x: center.x + radius * 0.8, y: center.y + radius * 0.6)
        )
        
        context.closePath()
        // 使用莫妮卡深粉
        context.setFillColor(UIColor(red: 1.0, green: 0.41, blue: 0.71, alpha: 1.0).cgColor)
        context.fillPath()
    }
    
    // MARK: - 绘制耗材区域
    private func drawMaterialsSection(at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let usedColors = canvasModel.usedColors
        guard !usedColors.isEmpty else { return y }
        
        let context = UIGraphicsGetCurrentContext()!
        var currentX = margin
        var currentY = y
        var lastRowY = y
        let itemWidth: CGFloat = 100  // 高清：增大宽度以容纳数量
        let itemHeight: CGFloat = 80  // 高清：增大高度
        let spacing: CGFloat = 16     // 高清：增大间距
        
        // 标题
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),  // 高清：增大字体
            .foregroundColor: UIColor.gray
        ]
        ("耗材对照" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        currentY += 36  // 高清：增大间距
        lastRowY = currentY
        
        // 绘制颜色块、色号和数量
        for (colorIndex, count) in usedColors.sorted(by: { $0.key < $1.key }) {
            if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                let color = canvasModel.palette[colorIndex]
                
                // 检查是否需要换行
                if currentX + itemWidth > width - margin {
                    currentX = margin
                    currentY += itemHeight + spacing
                    lastRowY = currentY
                }
                
                let rect = CGRect(x: currentX, y: currentY, width: itemWidth, height: itemHeight)
                
                // 绘制颜色块（高清：增大到 48x48）
                context.setFillColor(color.uiColor.cgColor)
                context.fillEllipse(in: CGRect(x: rect.midX - 24, y: rect.minY, width: 48, height: 48))
                
                // 绘制色号（高清：增大字体）
                let idAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.darkGray
                ]
                let idSize = (color.id as NSString).size(withAttributes: idAttributes)
                (color.id as NSString).draw(
                    in: CGRect(x: rect.midX - idSize.width/2, y: rect.minY + 52, width: idSize.width, height: 20),
                    withAttributes: idAttributes
                )
                
                // 绘制数量（高清：新增数量显示）
                let countAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.gray
                ]
                let countText = "×\(count)"
                let countSize = (countText as NSString).size(withAttributes: countAttributes)
                (countText as NSString).draw(
                    in: CGRect(x: rect.midX - countSize.width/2, y: rect.minY + 74, width: countSize.width, height: 18),
                    withAttributes: countAttributes
                )
                
                currentX += itemWidth + spacing
            }
        }
        
        return lastRowY + itemHeight + 20
    }
    
    // MARK: - 绘制行列标签
    private func drawRowColLabels(at y: CGFloat, canvasWidth: CGFloat, canvasHeight: CGFloat, cellSize: CGFloat, margin: CGFloat) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),  // 高清：从 8 增大到 16
            .foregroundColor: UIColor.gray
        ]
        
        let size = canvasModel.resolution.rawValue
        
        // 绘制列标签（顶部）
        for x in 0..<size {
            if x % 5 == 0 || x == size - 1 {
                let label = "\(x + 1)"
                let labelSize = (label as NSString).size(withAttributes: labelAttributes)
                let labelRect = CGRect(
                    x: margin + 30 + CGFloat(x) * cellSize - labelSize.width / 2,
                    y: y + (30 - labelSize.height) / 2,
                    width: labelSize.width,
                    height: labelSize.height
                )
                (label as NSString).draw(in: labelRect, withAttributes: labelAttributes)
            }
        }
        
        // 绘制行标签（左侧）
        for row in 0..<size {
            if row % 5 == 0 || row == size - 1 {
                let label = "\(row + 1)"
                let labelSize = (label as NSString).size(withAttributes: labelAttributes)
                let labelX = margin + (30 - labelSize.width) / 2
                let labelY = y + 30 + CGFloat(row) * cellSize - labelSize.height / 2
                let labelRect = CGRect(
                    x: labelX,
                    y: labelY,
                    width: labelSize.width,
                    height: labelSize.height
                )
                (label as NSString).draw(in: labelRect, withAttributes: labelAttributes)
            }
        }
    }
    
    // MARK: - 绘制参考线
    private func drawGuidelines(in rect: CGRect, size: Int, cellSize: CGFloat) {
        let context = UIGraphicsGetCurrentContext()!
        context.setStrokeColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        
        // 每10格画一条参考线
        for i in stride(from: 10, to: size, by: 10) {
            // 垂直线
            context.move(to: CGPoint(x: rect.origin.x + CGFloat(i) * cellSize, y: rect.origin.y))
            context.addLine(to: CGPoint(x: rect.origin.x + CGFloat(i) * cellSize, y: rect.maxY))
            
            // 水平线
            context.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y + CGFloat(i) * cellSize))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.origin.y + CGFloat(i) * cellSize))
        }
        
        context.strokePath()
    }
    
    // MARK: - 绘制底部信息
    private func drawFooter(at y: CGFloat, width: CGFloat, margin: CGFloat) {
        var infoParts: [String] = []
        
        if settings.showImageSize {
            infoParts.append("图像尺寸: \(canvasModel.resolution.rawValue)×\(canvasModel.resolution.rawValue)")
        }
        
        if settings.showBeadCount {
            infoParts.append("总颗粒数: \(canvasModel.totalBeadCount)颗")
        }
        
        guard !infoParts.isEmpty else { return }
        
        let infoText = infoParts.joined(separator: "  |  ")
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20),  // 高清：从 10 增大到 20
            .foregroundColor: UIColor.gray
        ]
        let infoSize = (infoText as NSString).size(withAttributes: infoAttributes)
        let infoRect = CGRect(
            x: (width - infoSize.width) / 2,
            y: y,
            width: infoSize.width,
            height: infoSize.height
        )
        (infoText as NSString).draw(in: infoRect, withAttributes: infoAttributes)
    }
    
    // MARK: - 保存到相册
    private func saveToPhotos() {
        guard let image = exportedImage else { return }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        withAnimation {
            showSaveSuccess = true
        }
    }
    
    // MARK: - 生成PDF（矢量图，优化内存）
    private func generatePatternPDF() -> Data? {
        let size = canvasModel.resolution.rawValue
        // 根据分辨率动态调整格子大小，确保清晰度
        let cellSize: CGFloat = size <= 32 ? 80 : (size <= 64 ? 50 : 35)
        let labelSize: CGFloat = settings.showRowColLabels ? 60 : 0
        let margin: CGFloat = 40
        let headerHeight: CGFloat = settings.showMaterials ? 240 : 80
        let footerHeight: CGFloat = 80
        
        let canvasWidth = CGFloat(size) * cellSize
        let canvasHeight = CGFloat(size) * cellSize
        let pageWidth = max(canvasWidth + labelSize + margin * 2, 400)
        let pageHeight = canvasHeight + labelSize + headerHeight + footerHeight + margin * 2
        
        // 创建PDF文档
        let pdfMetaData = [
            kCGPDFContextCreator: "少女心愿",
            kCGPDFContextAuthor: "少女心愿APP"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            let cgContext = context.cgContext
            var currentY: CGFloat = margin
            
            // 标题区域
            if !settings.showWatermark || settings.watermarkText.isEmpty {
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: UIColor.gray
                ]
                let title = "拼豆图纸"
                let titleSize = (title as NSString).size(withAttributes: titleAttributes)
                let titleRect = CGRect(
                    x: (pageWidth - titleSize.width) / 2,
                    y: currentY,
                    width: titleSize.width,
                    height: titleSize.height
                )
                (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)
                currentY += titleSize.height + 10
            }
            
            // 绘制耗材列表
            if settings.showMaterials {
                currentY = drawMaterialsSectionInPDF(at: currentY, width: pageWidth, margin: margin, context: cgContext)
                currentY += 30
            }
            
            // 绘制画布区域
            let canvasRect = CGRect(
                x: margin + labelSize,
                y: currentY + labelSize,
                width: canvasWidth,
                height: canvasHeight
            )
            
            // 绘制背景
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(canvasRect)
            
            // 优化：批量绘制相同颜色的格子
            var colorRects: [Int: [CGRect]] = [:]
            for y in 0..<size {
                for x in 0..<size {
                    let colorIndex = canvasModel.getPixel(at: x, y: y)
                    let rect = CGRect(
                        x: canvasRect.origin.x + CGFloat(x) * cellSize,
                        y: canvasRect.origin.y + CGFloat(y) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    colorRects[colorIndex, default: []].append(rect)
                }
            }
            
            // 批量绘制颜色块
            for (colorIndex, rects) in colorRects {
                if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                    cgContext.setFillColor(canvasModel.palette[colorIndex].uiColor.cgColor)
                    for rect in rects {
                        cgContext.fill(rect)
                    }
                } else {
                    cgContext.setFillColor(UIColor(white: 0.97, alpha: 1.0).cgColor)
                    for rect in rects {
                        cgContext.fill(rect)
                    }
                }
            }
            
            // 绘制耗材型号（在有色格子上）
            if settings.showColorIds {
                for y in 0..<size {
                    for x in 0..<size {
                        let colorIndex = canvasModel.getPixel(at: x, y: y)
                        if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                            let rect = CGRect(
                                x: canvasRect.origin.x + CGFloat(x) * cellSize,
                                y: canvasRect.origin.y + CGFloat(y) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                            
                            let colorId = canvasModel.palette[colorIndex].id
                            let fontSize = min(cellSize * 0.35, 16)
                            
                            // 根据背景色亮度决定文字颜色
                            let bgColor = canvasModel.palette[colorIndex]
                            let brightness = bgColor.brightness
                            let textColor = brightness > 0.6 
                                ? UIColor.black.withAlphaComponent(0.7) 
                                : UIColor.white.withAlphaComponent(0.9)
                            
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                                .foregroundColor: textColor
                            ]
                            let textSize = (colorId as NSString).size(withAttributes: attributes)
                            
                            // 只在格子足够大时显示文字
                            if textSize.width < rect.width - 4 && textSize.height < rect.height - 4 {
                                let textRect = CGRect(
                                    x: rect.midX - textSize.width / 2,
                                    y: rect.midY - textSize.height / 2,
                                    width: textSize.width,
                                    height: textSize.height
                                )
                                (colorId as NSString).draw(in: textRect, withAttributes: attributes)
                            }
                        }
                    }
                }
            }
            
            // 绘制网格（优化：批量绘制）
            if settings.showGrid {
                cgContext.setStrokeColor(UIColor.lightGray.withAlphaComponent(0.5).cgColor)
                cgContext.setLineWidth(0.5)
                for i in 0...size {
                    let x = canvasRect.origin.x + CGFloat(i) * cellSize
                    let y = canvasRect.origin.y + CGFloat(i) * cellSize
                    // 垂直线
                    cgContext.move(to: CGPoint(x: x, y: canvasRect.origin.y))
                    cgContext.addLine(to: CGPoint(x: x, y: canvasRect.maxY))
                    // 水平线
                    cgContext.move(to: CGPoint(x: canvasRect.origin.x, y: y))
                    cgContext.addLine(to: CGPoint(x: canvasRect.maxX, y: y))
                }
                cgContext.strokePath()
            }
            
            // 绘制外边框
            cgContext.setStrokeColor(UIColor.gray.cgColor)
            cgContext.setLineWidth(1)
            cgContext.stroke(canvasRect)
            
            // 绘制App Logo
            drawAppLogoInPDF(in: canvasRect, context: cgContext)
            
            // 绘制行列标签
            if settings.showRowColLabels {
                drawRowColLabelsInPDF(at: currentY, canvasWidth: canvasWidth, canvasHeight: canvasHeight, cellSize: cellSize, margin: margin, context: cgContext)
            }
            
            // 绘制参考线
            if settings.showGuidelines {
                drawGuidelinesInPDF(in: canvasRect, size: size, cellSize: cellSize, context: cgContext)
            }
            
            // 绘制水印
            if settings.showWatermark && !settings.watermarkText.isEmpty {
                drawWatermarkInPDF(in: canvasRect, text: settings.watermarkText, context: cgContext)
            }
            
            // 绘制底部信息
            currentY = canvasRect.maxY + 10
            drawFooterInPDF(at: currentY, width: pageWidth, margin: margin, context: cgContext)
        }
        
        return data
    }
    
    // PDF绘制辅助方法
    private func drawMaterialsSectionInPDF(at y: CGFloat, width: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let usedColors = canvasModel.usedColors
        guard !usedColors.isEmpty else { return y }
        
        var currentX = margin
        var currentY = y
        let itemWidth: CGFloat = 100
        let itemHeight: CGFloat = 80
        let spacing: CGFloat = 16
        
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor.gray
        ]
        ("耗材对照" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        currentY += 36
        
        for (colorIndex, count) in usedColors.sorted(by: { $0.key < $1.key }) {
            if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                let color = canvasModel.palette[colorIndex]
                
                if currentX + itemWidth > width - margin {
                    currentX = margin
                    currentY += itemHeight + spacing
                }
                
                let rect = CGRect(x: currentX, y: currentY, width: itemWidth, height: itemHeight)
                
                context.setFillColor(color.uiColor.cgColor)
                context.fillEllipse(in: CGRect(x: rect.midX - 24, y: rect.minY, width: 48, height: 48))
                
                let idAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.darkGray
                ]
                let idSize = (color.id as NSString).size(withAttributes: idAttributes)
                (color.id as NSString).draw(
                    in: CGRect(x: rect.midX - idSize.width/2, y: rect.minY + 52, width: idSize.width, height: 20),
                    withAttributes: idAttributes
                )
                
                let countAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.gray
                ]
                let countText = "×\(count)"
                let countSize = (countText as NSString).size(withAttributes: countAttributes)
                (countText as NSString).draw(
                    in: CGRect(x: rect.midX - countSize.width/2, y: rect.minY + 74, width: countSize.width, height: 18),
                    withAttributes: countAttributes
                )
                
                currentX += itemWidth + spacing
            }
        }
        
        return currentY + itemHeight + 20
    }
    
    private func drawAppLogoInPDF(in rect: CGRect, context: CGContext) {
        let iconSize: CGFloat = 48
        let iconX = rect.origin.x + 16
        let iconY = rect.origin.y + 16
        
        // 绘制心形作为Logo
        drawHeartInPDF(in: context, at: CGPoint(x: iconX + iconSize/2, y: iconY + iconSize/2), size: iconSize)
        
        let appName = "少女心愿"
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: UIColor.darkGray
        ]
        let nameSize = (appName as NSString).size(withAttributes: nameAttributes)
        (appName as NSString).draw(
            at: CGPoint(x: iconX + iconSize + 12, y: iconY + (iconSize - nameSize.height) / 2),
            withAttributes: nameAttributes
        )
    }
    
    private func drawHeartInPDF(in context: CGContext, at center: CGPoint, size: CGFloat) {
        let radius = size / 2
        
        context.beginPath()
        context.move(to: CGPoint(x: center.x, y: center.y + radius * 0.3))
        context.addCurve(
            to: CGPoint(x: center.x - radius * 0.8, y: center.y - radius * 0.2),
            control1: CGPoint(x: center.x - radius * 0.8, y: center.y + radius * 0.6),
            control2: CGPoint(x: center.x - radius * 0.8, y: center.y - radius * 0.2)
        )
        context.addArc(
            center: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.2),
            radius: radius * 0.4,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
        )
        context.addArc(
            center: CGPoint(x: center.x + radius * 0.4, y: center.y - radius * 0.2),
            radius: radius * 0.4,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
        )
        context.addCurve(
            to: CGPoint(x: center.x, y: center.y + radius * 0.3),
            control1: CGPoint(x: center.x + radius * 0.8, y: center.y - radius * 0.2),
            control2: CGPoint(x: center.x + radius * 0.8, y: center.y + radius * 0.6)
        )
        context.closePath()
        context.setFillColor(UIColor(red: 1.0, green: 0.41, blue: 0.71, alpha: 1.0).cgColor)
        context.fillPath()
    }
    
    private func drawRowColLabelsInPDF(at y: CGFloat, canvasWidth: CGFloat, canvasHeight: CGFloat, cellSize: CGFloat, margin: CGFloat, context: CGContext) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.gray
        ]
        
        let size = canvasModel.resolution.rawValue
        
        for x in 0..<size {
            if x % 5 == 0 || x == size - 1 {
                let label = "\(x + 1)"
                let labelSize = (label as NSString).size(withAttributes: labelAttributes)
                let labelRect = CGRect(
                    x: margin + 30 + CGFloat(x) * cellSize - labelSize.width / 2,
                    y: y + (30 - labelSize.height) / 2,
                    width: labelSize.width,
                    height: labelSize.height
                )
                (label as NSString).draw(in: labelRect, withAttributes: labelAttributes)
            }
        }
        
        for row in 0..<size {
            if row % 5 == 0 || row == size - 1 {
                let label = "\(row + 1)"
                let labelSize = (label as NSString).size(withAttributes: labelAttributes)
                let labelX = margin + (30 - labelSize.width) / 2
                let labelY = y + 30 + CGFloat(row) * cellSize - labelSize.height / 2
                let labelRect = CGRect(
                    x: labelX,
                    y: labelY,
                    width: labelSize.width,
                    height: labelSize.height
                )
                (label as NSString).draw(in: labelRect, withAttributes: labelAttributes)
            }
        }
    }
    
    private func drawGuidelinesInPDF(in rect: CGRect, size: Int, cellSize: CGFloat, context: CGContext) {
        context.setStrokeColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        
        for i in stride(from: 10, to: size, by: 10) {
            context.move(to: CGPoint(x: rect.origin.x + CGFloat(i) * cellSize, y: rect.origin.y))
            context.addLine(to: CGPoint(x: rect.origin.x + CGFloat(i) * cellSize, y: rect.maxY))
            
            context.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y + CGFloat(i) * cellSize))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.origin.y + CGFloat(i) * cellSize))
        }
        
        context.strokePath()
    }
    
    private func drawWatermarkInPDF(in rect: CGRect, text: String, context: CGContext) {
        let fontSize: CGFloat = 48
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.gray.withAlphaComponent(0.12)
        ]
        
        let textSize = (text as NSString).size(withAttributes: attributes)
        let spacingX = textSize.width + 200
        let spacingY = textSize.height + 150
        
        let diagonalLength = sqrt(rect.width * rect.width + rect.height * rect.height)
        let cols = Int(diagonalLength / spacingX) + 3
        let rows = Int(diagonalLength / spacingY) + 3
        
        context.saveGState()
        context.addRect(rect)
        context.clip()
        
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -45 * .pi / 180)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        
        for row in -rows/2..<rows/2 {
            for col in -cols/2..<cols/2 {
                let x = rect.midX + CGFloat(col) * spacingX + CGFloat(row % 2) * (spacingX / 2)
                let y = rect.midY + CGFloat(row) * spacingY
                
                let textRect = CGRect(
                    x: x - textSize.width / 2,
                    y: y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (text as NSString).draw(in: textRect, withAttributes: attributes)
            }
        }
        
        context.restoreGState()
    }
    
    private func drawFooterInPDF(at y: CGFloat, width: CGFloat, margin: CGFloat, context: CGContext) {
        var infoParts: [String] = []
        
        if settings.showImageSize {
            infoParts.append("图像尺寸: \(canvasModel.resolution.rawValue)×\(canvasModel.resolution.rawValue)")
        }
        
        if settings.showBeadCount {
            infoParts.append("总颗粒数: \(canvasModel.totalBeadCount)颗")
        }
        
        guard !infoParts.isEmpty else { return }
        
        let infoText = infoParts.joined(separator: "  |  ")
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20),
            .foregroundColor: UIColor.gray
        ]
        let infoSize = (infoText as NSString).size(withAttributes: infoAttributes)
        let infoRect = CGRect(
            x: (width - infoSize.width) / 2,
            y: y,
            width: infoSize.width,
            height: infoSize.height
        )
        (infoText as NSString).draw(in: infoRect, withAttributes: infoAttributes)
    }
}

// MARK: - 矢量图预览视图
struct PatternPreviewView: View {
    let canvasModel: PixelCanvasModel
    let settings: PatternExportSettings
    let size: CGSize
    
    var body: some View {
        Canvas { context, canvasSize in
            drawPattern(in: &context, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
    }
    
    private func drawPattern(in context: inout GraphicsContext, size: CGSize) {
        let resolution = canvasModel.resolution.rawValue
        
        // 布局参数 - 预览容器只包含拼豆图和行列标签
        let margin: CGFloat = 16
        let labelSpace: CGFloat = settings.showRowColLabels ? 32 : 0
        
        // 计算可用空间
        let availableWidth = size.width - margin * 2
        let availableHeight = size.height - margin * 2
        
        // 计算格子大小 - 确保画布能完整显示在可用空间内
        let cellSize = min(
            (availableWidth - labelSpace) / CGFloat(resolution),
            (availableHeight - labelSpace) / CGFloat(resolution)
        )
        
        // 计算画布尺寸
        let canvasWidth = CGFloat(resolution) * cellSize
        let canvasHeight = CGFloat(resolution) * cellSize
        
        // 计算布局位置 - 居中显示，行列标签在两边
        let offsetX = margin + labelSpace + (availableWidth - labelSpace - canvasWidth) / 2
        let offsetY = margin + labelSpace + (availableHeight - labelSpace - canvasHeight) / 2
        
        // 绘制画布背景
        let backgroundRect = CGRect(x: offsetX, y: offsetY, width: canvasWidth, height: canvasHeight)
        context.fill(Path(backgroundRect), with: .color(.white))
        
        // 绘制像素格子
        let showIds = settings.showColorIds
        let showGrid = settings.showGrid
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                let colorIndex = canvasModel.getPixel(at: x, y: y)
                let rect = CGRect(
                    x: offsetX + CGFloat(x) * cellSize,
                    y: offsetY + CGFloat(y) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                
                if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                    let beadColor = canvasModel.palette[colorIndex]
                    
                    // 绘制颜色块
                    context.fill(Path(rect), with: .color(Color(beadColor.uiColor)))
                    
                    // 绘制耗材型号 - 使用相对于格子的比例，确保放大时可见
                    if showIds {
                        let colorId = beadColor.id
                        // 字体大小为格子的 40%，确保放大缩小都能看清
                        let fontSize = cellSize * 0.4
                        
                        // 根据背景亮度选择文字颜色
                        let brightness = beadColor.brightness
                        let textColor: Color = brightness > 0.5 ? .black : .white
                        
                        var text = Text(colorId)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundColor(textColor)
                        
                        // 测量文字
                        let resolved = context.resolve(text)
                        let textSize = resolved.measure(in: CGSize(width: cellSize, height: cellSize))
                        
                        // 只在能放下时绘制（留出边距）
                        if textSize.width <= cellSize * 0.85 && textSize.height <= cellSize * 0.85 {
                            let textRect = CGRect(
                                x: rect.midX - textSize.width / 2,
                                y: rect.midY - textSize.height / 2,
                                width: textSize.width,
                                height: textSize.height
                            )
                            context.draw(text, in: textRect)
                        }
                    }
                } else {
                    // 空白格子
                    context.fill(Path(rect), with: .color(Color(white: 0.95)))
                }
            }
        }
        
        // 绘制网格线
        if showGrid {
            var gridPath = Path()
            for i in 0...resolution {
                let pos = CGFloat(i) * cellSize
                // 垂直线
                gridPath.move(to: CGPoint(x: offsetX + pos, y: offsetY))
                gridPath.addLine(to: CGPoint(x: offsetX + pos, y: offsetY + canvasHeight))
                // 水平线
                gridPath.move(to: CGPoint(x: offsetX, y: offsetY + pos))
                gridPath.addLine(to: CGPoint(x: offsetX + canvasWidth, y: offsetY + pos))
            }
            context.stroke(gridPath, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
        }
        
        // 绘制外边框
        var borderPath = Path()
        borderPath.addRect(backgroundRect)
        context.stroke(borderPath, with: .color(.gray.opacity(0.5)), lineWidth: 1)
        
        // 绘制行列标签
        if settings.showRowColLabels {
            drawLabels(in: &context, offsetX: offsetX, offsetY: offsetY, cellSize: cellSize, resolution: resolution, labelSpace: labelSpace)
        }
        
        // 绘制参考线
        if settings.showGuidelines {
            drawGuidelines(in: &context, offsetX: offsetX, offsetY: offsetY, cellSize: cellSize, resolution: resolution)
        }
        
        // 绘制水印
        if settings.showWatermark && !settings.watermarkText.isEmpty {
            drawWatermark(in: &context, rect: backgroundRect, text: settings.watermarkText)
        }
    }
    
    private func drawFooterInPreview(in context: inout GraphicsContext, at position: CGPoint, width: CGFloat) {
        var infoParts: [String] = []
        
        if settings.showImageSize {
            infoParts.append("\(canvasModel.resolution.rawValue)×\(canvasModel.resolution.rawValue)")
        }
        
        if settings.showBeadCount {
            infoParts.append("\(canvasModel.totalBeadCount)颗")
        }
        
        guard !infoParts.isEmpty else { return }
        
        let infoText = infoParts.joined(separator: "  |  ")
        var text = Text(infoText)
            .font(.system(size: 10))
            .foregroundColor(.gray)
        
        let textSize = context.resolve(text).measure(in: CGSize(width: 200, height: 20))
        let textRect = CGRect(
            x: position.x + (width - textSize.width) / 2,
            y: position.y,
            width: textSize.width,
            height: textSize.height
        )
        context.draw(text, in: textRect)
    }
    
    private func drawLabels(in context: inout GraphicsContext, offsetX: CGFloat, offsetY: CGFloat, cellSize: CGFloat, resolution: Int, labelSpace: CGFloat) {
        // 标签字体大小相对于 labelSpace，确保放大时可见
        let labelFontSize = labelSpace * 0.35
        let labelFont = Font.system(size: labelFontSize)
        let labelColor = Color.gray
        
        // 列标签（顶部）- 固定在容器顶部边缘
        for x in 0..<resolution {
            if x % 5 == 0 || x == resolution - 1 {
                let label = "\(x + 1)"
                var text = Text(label)
                    .font(labelFont)
                    .foregroundColor(labelColor)
                
                let textSize = context.resolve(text).measure(in: CGSize(width: labelSpace, height: labelSpace))
                // 标签固定在容器顶部，与格子对齐
                let textRect = CGRect(
                    x: offsetX + CGFloat(x) * cellSize + cellSize / 2 - textSize.width / 2,
                    y: offsetY - labelSpace + (labelSpace - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                context.draw(text, in: textRect)
            }
        }
        
        // 行标签（左侧）- 固定在容器左侧边缘
        for y in 0..<resolution {
            if y % 5 == 0 || y == resolution - 1 {
                let label = "\(y + 1)"
                var text = Text(label)
                    .font(labelFont)
                    .foregroundColor(labelColor)
                
                let textSize = context.resolve(text).measure(in: CGSize(width: labelSpace, height: labelSpace))
                // 标签固定在容器左侧，与格子对齐
                let textRect = CGRect(
                    x: offsetX - labelSpace + (labelSpace - textSize.width) / 2,
                    y: offsetY + CGFloat(y) * cellSize + cellSize / 2 - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                context.draw(text, in: textRect)
            }
        }
    }
    
    private func drawGuidelines(in context: inout GraphicsContext, offsetX: CGFloat, offsetY: CGFloat, cellSize: CGFloat, resolution: Int) {
        // 每10格画一条参考线
        for i in stride(from: 10, to: resolution, by: 10) {
            // 垂直线
            var vPath = Path()
            let x = offsetX + CGFloat(i) * cellSize
            vPath.move(to: CGPoint(x: x, y: offsetY))
            vPath.addLine(to: CGPoint(x: x, y: offsetY + CGFloat(resolution) * cellSize))
            context.stroke(vPath, with: .color(.gray.opacity(0.3)), lineWidth: 1)
            
            // 水平线
            var hPath = Path()
            let y = offsetY + CGFloat(i) * cellSize
            hPath.move(to: CGPoint(x: offsetX, y: y))
            hPath.addLine(to: CGPoint(x: offsetX + CGFloat(resolution) * cellSize, y: y))
            context.stroke(hPath, with: .color(.gray.opacity(0.3)), lineWidth: 1)
        }
    }
    
    private func drawAppLogo(in context: inout GraphicsContext, at position: CGPoint) {
        // 使用 AppIcon 作为 Logo
        let iconSize: CGFloat = 24
        
        // 尝试加载 AppIcon
        if let appIcon = UIImage(named: "AppIcon") {
            // 绘制 AppIcon
            let iconRect = CGRect(x: position.x, y: position.y, width: iconSize, height: iconSize)
            if let cgImage = appIcon.cgImage {
                context.draw(Image(cgImage, scale: 1.0, orientation: .up, label: Text("")), in: iconRect)
            }
        } 
        
        // 绘制 App 名字
        let appName = "少女心愿"
        var appNameText = Text(appName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
        
        let nameSize = context.resolve(appNameText).measure(in: CGSize(width: 200, height: 30))
        let nameRect = CGRect(
            x: position.x + iconSize + 6,
            y: position.y + (iconSize - nameSize.height) / 2,
            width: nameSize.width,
            height: nameSize.height
        )
        context.draw(appNameText, in: nameRect)
    }
    
    private func drawWatermark(in context: inout GraphicsContext, rect: CGRect, text: String) {
        let fontSize: CGFloat = 14
        var watermarkText = Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(.gray.opacity(0.15))
        
        let textSize = context.resolve(watermarkText).measure(in: rect.size)
        let spacingX = textSize.width + 60
        let spacingY = textSize.height + 40
        
        // 计算需要多少行/列
        let diagonalLength = sqrt(rect.width * rect.width + rect.height * rect.height)
        let cols = Int(diagonalLength / spacingX) + 3
        let rows = Int(diagonalLength / spacingY) + 3
        
        // 在图纸区域内绘制水印（不旋转，直接绘制多列）
        for row in -rows/2..<rows/2 {
            for col in -cols/2..<cols/2 {
                // 计算斜向位置（45度角）
                let angle: CGFloat = -45 * .pi / 180
                let baseX = rect.midX + CGFloat(col) * spacingX
                let baseY = rect.midY + CGFloat(row) * spacingY
                
                // 应用旋转变换
                let dx = baseX - rect.midX
                let dy = baseY - rect.midY
                let rotatedX = rect.midX + dx * cos(angle) - dy * sin(angle)
                let rotatedY = rect.midY + dx * sin(angle) + dy * cos(angle)
                
                // 添加交错偏移
                let staggerOffset = CGFloat(row % 2) * (spacingX / 2)
                let finalX = rotatedX + staggerOffset
                let finalY = rotatedY
                
                let textRect = CGRect(
                    x: finalX - textSize.width / 2,
                    y: finalY - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                
                // 只在图纸区域内绘制
                if rect.contains(CGPoint(x: textRect.midX, y: textRect.midY)) {
                    context.draw(watermarkText, in: textRect)
                }
            }
        }
    }
}

// MARK: - 扩展 PixelCanvasModel
extension PixelCanvasModel {
    /// 获取使用的颜色及其数量
       var usedColors: [Int: Int] {
        var counts: [Int: Int] = [:]
        for colorIndex in pixelData where colorIndex >= 0 {
            counts[colorIndex, default: 0] += 1
        }
        return counts
    }
    
    /// 总颗粒数
    var totalBeadCount: Int {
        pixelData.filter { $0 >= 0 }.count
    }
}
