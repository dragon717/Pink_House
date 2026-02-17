//
//  SharedTypes.swift
//  ItemManager
//
//  SpatialCanvas 共享类型定义
//

import SwiftUI

// MARK: - 工具类型

public enum CanvasTool: String, CaseIterable {
    case resetCamera = "重置视角"
    case select = "选择"
    case image = "图片"
    case gallery = "图库"
    case camera = "相机"
    case usdzModel = "3D模型"
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
        case .usdzModel: return "cube.box"
        case .light: return "lightbulb"
        case .text: return "textformat"
        case .material: return "paintpalette"
        case .clothing: return "tshirt"
        case .effect: return "sparkles"
        case .template: return "doc.text"
        case .transform: return "rotate.3d"
        case .record: return "record.circle"
        case .settings: return "gearshape"
        case .resetCamera: return "arrow.counterclockwise"
        }
    }
    
    var color: Color {
        switch self {
        case .select: return .blue
        case .image: return .green
        case .gallery: return .orange
        case .camera: return .red
        case .usdzModel: return .purple
        case .light: return .yellow
        case .text: return .cyan
        case .material: return .pink
        case .clothing: return .indigo
        case .effect: return .mint
        case .template: return .teal
        case .transform: return .brown
        case .record: return .red
        case .settings: return .gray
        case .resetCamera: return .blue
        }
    }
}

// MARK: - 变换模式

public enum TransformMode {
    case move
    case rotate
    case scale
}

// MARK: - 3DGS处理阶段

enum GSProcessingStage: Equatable {
    case idle
    case preparing
    case processing
    case uploading
    case sfm
    case training
    case optimizing
    case finalizing
    case complete
    case failed(String)
    
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
        case .failed(let message): return "失败: \(message)"
        }
    }
    
    static func == (lhs: GSProcessingStage, rhs: GSProcessingStage) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.preparing, .preparing),
             (.processing, .processing),
             (.uploading, .uploading),
             (.sfm, .sfm),
             (.training, .training),
             (.optimizing, .optimizing),
             (.finalizing, .finalizing),
             (.complete, .complete):
            return true
        case (.failed(let l), .failed(let r)):
            return l == r
        default:
            return false
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
    var onDismiss: (() -> Void)? = nil
    
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                if case .failed(let message) = stage {
                    failedView(message: message)
                } else {
                    processingView
                }
            }
        }
    }
    
    private func failedView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            
            VStack(spacing: 12) {
                Text("处理失败")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Text(userFriendlyMessage(from: message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Button {
                onDismiss?()
            } label: {
                Text("确定")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0 : 1)
                
                Circle()
                    .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "cube.transparent")
                    .font(.system(size: 40))
                    .foregroundStyle(.purple)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulseAnimation.toggle()
                }
            }
            
            VStack(spacing: 20) {
                // 进度条 - 增加对比度
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 12)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(progress), height: 12)
                            .shadow(color: .purple.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                }
                .frame(width: 240, height: 12)
                
                // 阶段文字 - 增加可读性
                Text(stageText)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                
                // 百分比 - 更醒目
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 0)
            }
            
            // 底部提示 - 更醒目
            VStack(spacing: 8) {
                Text("⏱️ 处理时间约 1-3 分钟")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.yellow)
                
                Text("请保持应用在前台运行，不要锁屏")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
    }
    
    private func userFriendlyMessage(from error: String) -> String {
        if error.contains("不支持") || error.contains("not supported") {
            return "您的设备不支持 3D 建模功能\n需要 iPhone 12 Pro 及以上机型"
        } else if error.contains("图片") || error.contains("images") {
            return "请确保选择至少 20 张清晰的照片"
        } else {
            return "模型生成过程中出现错误\n请重试或检查照片质量"
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
