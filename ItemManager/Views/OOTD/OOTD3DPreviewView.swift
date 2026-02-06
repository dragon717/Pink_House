import SwiftUI
import UIKit
import MetalKit

struct OOTD3DPreviewView: View {
    let imagePath: String?
    let inputImage: UIImage?
    
    init(imagePath: String, onDismiss: (() -> Void)? = nil) {
        AppLogger.info("OOTD3DPreviewView: init(imagePath: \(imagePath))")
        self.imagePath = imagePath
        self.inputImage = nil
        self.onDismiss = onDismiss
    }
    
    init(inputImage: UIImage, onDismiss: (() -> Void)? = nil) {
        AppLogger.info("OOTD3DPreviewView: init(inputImage)")
        self.inputImage = inputImage
        self.imagePath = nil
        self.onDismiss = onDismiss
        // Initialize displayImage directly to avoid first-frame flickering
        _displayImage = State(initialValue: inputImage)
    }
    
    // Callback for manual dismissal in ZStack overlay mode
    var onDismiss: (() -> Void)?
    
    // TEMPORARILY COMMENTED OUT FOR DEBUGGING - RESTORED
    @ObservedObject private var service = SharpGenerationService.shared
    
    @State private var splats: [GaussianSplat] = []
    @State private var error: Error?
    @State private var displayImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Background is handled by parent ZStack
            
            if splats.isEmpty {
                VStack(spacing: 20) {
                    if service.isGenerating {
                        ProgressView(value: service.progress) {
                            Text("正在生成 3D 模型...")
                                .foregroundColor(.white)
                        }
                        .progressViewStyle(LinearProgressViewStyle(tint: .pink))
                        .padding(.horizontal, 40)
                    } else {
                        // Initial State
                        // Use local let binding to ensure image is available
                        if let image = displayImage ?? inputImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 300)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            
                            Button {
                                generateModel(from: image)
                            } label: {
                                HStack {
                                    if service.modelState == .loading {
                                        ProgressView()
                                            .tint(.black)
                                        Text("模型加载中(大文件)...")
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "cube.transparent")
                                        Text("生成 3D 视图")
                                    }
                                }
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding()
                                .background(service.modelState == .ready ? Color.white : Color.white.opacity(0.6))
                                .cornerRadius(12)
                            }
                            .disabled(service.modelState != .ready)
                            
                            if case .error(let msg) = service.modelState {
                                Text("模型加载失败: \(msg)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.top, 4)
                            }
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
            } else {
                // 3D View
                ZStack(alignment: .topTrailing) {
                    PointCloudView(splats: splats)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Controls overlay
                    VStack {
                        Button {
                            withAnimation {
                                splats = [] // Reset to regenerate or exit
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .padding()
                                .background(Material.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                }
            }
            
            // Close Button
            VStack {
                HStack {
                    Button {
                        if let onDismiss = onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
        .task {
            if let img = inputImage {
                self.displayImage = img
            } else if let path = imagePath {
                self.displayImage = await ImageManager.shared.loadImageAsync(fileName: path)
            }
        }
        .alert("生成失败", isPresented: Binding(get: { error != nil }, set: { _ in error = nil })) {
            Button("确定") {}
        } message: {
            Text(error?.localizedDescription ?? "未知错误")
        }
    }
    
    private func generateModel(from image: UIImage) {
        AppLogger.info("OOTD3DPreviewView: generateModel called (Real Service)")
        Task {
            do {
                let result = try await service.generate(from: image)
                withAnimation {
                    self.splats = result
                }
            } catch {
                self.error = error
            }
        }
    }
}
