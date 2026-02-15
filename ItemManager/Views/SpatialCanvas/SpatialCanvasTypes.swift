//
//  SharedTypes.swift
//  ItemManager
//
//  SpatialCanvas 共享类型定义
//

import SwiftUI

// MARK: - 工具类型

enum CanvasTool: String, CaseIterable {
    case select = "选择"
    case image = "图片"
    case gallery = "图库"
    case camera = "相机"
    case gsModel = "3D模型"
    case light = "灯光"
    case text = "文字"
    case material = "材质"
    case clothing = "服装"
    case effect = "特效"
    case template = "模板"
    case transform = "变换"
    case record = "录制"
    case settings = "设置"
    
    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .image: return "photo"
        case .gallery: return "photo.on.rectangle"
        case .camera: return "camera.fill"
        case .gsModel: return "cube.box"
        case .light: return "lightbulb"
        case .text: return "textformat"
        case .material: return "paintpalette"
        case .clothing: return "tshirt"
        case .effect: return "sparkles"
        case .template: return "doc.text"
        case .transform: return "rotate.3d"
        case .record: return "record.circle"
        case .settings: return "gearshape"
        }
    }
    
    var color: Color {
        switch self {
        case .select: return .blue
        case .image: return .green
        case .gallery: return .orange
        case .camera: return .red
        case .gsModel: return .purple
        case .light: return .yellow
        case .text: return .cyan
        case .material: return .pink
        case .clothing: return .indigo
        case .effect: return .mint
        case .template: return .teal
        case .transform: return .brown
        case .record: return .red
        case .settings: return .gray
        }
    }
}

// MARK: - 变换模式

enum TransformMode {
    case rotate
    case scale
}

// MARK: - 3DGS处理阶段

enum GSProcessingStage: CaseIterable {
    case idle
    case preparing
    case processing
    case uploading
    case sfm
    case training
    case optimizing
    case finalizing
    case complete
    
    var description: String {
        switch self {
        case .idle: return "准备中..."
        case .preparing: return "准备数据..."
        case .processing: return "处理中..."
        case .uploading: return "上传数据..."
        case .sfm: return "SfM重建..."
        case .training: return "训练模型..."
        case .optimizing: return "优化模型..."
        case .finalizing: return "最终处理..."
        case .complete: return "完成!"
        }
    }
}

// MARK: - 素材分类

enum AssetCategory: String, CaseIterable {
    case clothing = "服饰"
    case accessories = "配饰"
    case furniture = "家具"
    case effect = "特效"
    case template = "模板"
    case material = "材质"
}

// MARK: - GS处理遮罩视图

struct GSProcessingOverlay: View {
    let stage: GSProcessingStage
    let progress: Double
    
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // 3D图标动画
                ZStack {
                    // 外圈脉冲
                    Circle()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 1)
                    
                    // 中圈
                    Circle()
                        .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    
                    // 内圈
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    // 中心图标
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        pulseAnimation.toggle()
                    }
                }
                
                // 进度信息
                VStack(spacing: 16) {
                    // 进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                        }
                    }
                    .frame(width: 200, height: 8)
                    
                    // 阶段文本
                    Text(stageText)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    // 百分比
                    Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.purple)
                }
                
                // 提示文本
                Text("请保持应用在前台运行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var stageText: String {
        stage.description
    }
}

// MARK: - 变换辅助器 (Gizmo)

struct TransformGizmoOverlay: View {
    let mode: TransformMode
    @Binding var rotationX: Double
    @Binding var rotationY: Double
    @Binding var rotationZ: Double
    @Binding var scale: Double
    var onTransformChange: () -> Void
    
    var body: some View {
        VStack {
            Text("变换控制")
                .font(.caption)
                .padding(.top, 8)
            
            if mode == .rotate {
                VStack(spacing: 8) {
                    Slider(value: $rotationX, in: -Double.pi...Double.pi) {
                        Text("X轴旋转")
                    } onEditingChanged: { _ in
                        onTransformChange()
                    }
                    Slider(value: $rotationY, in: -Double.pi...Double.pi) {
                        Text("Y轴旋转")
                    } onEditingChanged: { _ in
                        onTransformChange()
                    }
                    Slider(value: $rotationZ, in: -Double.pi...Double.pi) {
                        Text("Z轴旋转")
                    } onEditingChanged: { _ in
                        onTransformChange()
                    }
                }
                .padding()
            } else {
                Slider(value: $scale, in: 0.1...3.0) {
                    Text("缩放")
                } onEditingChanged: { _ in
                    onTransformChange()
                }
                .padding()
            }
            
            Spacer()
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.top, 100)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
