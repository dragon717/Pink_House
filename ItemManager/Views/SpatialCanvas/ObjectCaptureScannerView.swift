import SwiftUI
import RealityKit

#if os(iOS)

struct ObjectCaptureScannerView: View {
    
    @StateObject private var sessionManager = ObjectCaptureSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var onComplete: (URL) -> Void
    
    @State private var session: ObjectCaptureSession?
    @State private var showTips: Bool = true
    @State private var showNotSupportedAlert: Bool = false
    
    var body: some View {
        ZStack {
            if !ObjectCaptureSession.isSupported {
                notSupportedView
            } else if let session = session {
                ObjectCaptureView(session: session)
                    .onAppear {
                        session.startDetecting()
                    }
                
                VStack {
                    topControls
                    
                    Spacer()
                    
                    if showTips {
                        tipsOverlay
                    }
                    
                    bottomControls
                }
            } else {
                Color.black.ignoresSafeArea()
                ProgressView("初始化相机...")
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            if ObjectCaptureSession.isSupported {
                session = sessionManager.prepareSession()
            }
        }
        .onDisappear {
            sessionManager.reset()
        }
    }
    
    private var notSupportedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                Text("设备不支持")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("3D 扫描需要 LiDAR 设备\n（iPhone 12 Pro 及以上）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("返回")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var topControls: some View {
        HStack {
            Button {
                sessionManager.cancelSession()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
            
            Spacer()
            
            Button {
                showTips.toggle()
            } label: {
                Image(systemName: showTips ? "questionmark.circle.fill" : "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var tipsOverlay: some View {
        VStack(spacing: 16) {
            tipRow(icon: "move.3d", text: "围绕物体缓慢移动")
            tipRow(icon: "camera.circle", text: "保持相机稳定")
            tipRow(icon: "sun.max", text: "确保光线充足")
            tipRow(icon: "arrow.triangle.2.circlepath", text: "从多个角度拍摄")
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal, 32)
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 28)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
    
    private var bottomControls: some View {
        VStack(spacing: 16) {
            if sessionManager.isCapturing {
                captureProgress
            }
            
            actionButton
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var captureProgress: some View {
        VStack(spacing: 8) {
            Text("正在拍摄...")
                .font(.subheadline)
                .foregroundStyle(.white)
            
            if sessionManager.userCompletedScanPass {
                Label("扫描完成，可以结束", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch sessionManager.state {
        case .ready, .initializing:
            Button("准备中...") {}
                .disabled(true)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray)
                .foregroundStyle(.white)
                .cornerRadius(12)
            
        case .detecting:
            Button("开始拍摄") {
                sessionManager.startCapturing()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(12)
            
        case .capturing:
            if sessionManager.userCompletedScanPass {
                Button("完成拍摄") {
                    if let imageDir = sessionManager.finishCapturing() {
                        dismiss()
                        onComplete(imageDir)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .cornerRadius(12)
            } else {
                Button("继续拍摄更多角度") {
                    // 提示用户继续
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            
        case .completed:
            Button("处理中...") {}
                .disabled(true)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray)
                .foregroundStyle(.white)
                .cornerRadius(12)
            
        case .failed(let error):
            VStack(spacing: 8) {
                Text("拍摄失败: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundStyle(.red)
                
                Button("重试") {
                    sessionManager.reset()
                    session = sessionManager.prepareSession()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            
        @unknown default:
            EmptyView()
        }
    }
    
    private var statusText: String {
        switch sessionManager.state {
        case .ready: return "准备就绪"
        case .initializing: return "初始化中"
        case .detecting: return "检测物体"
        case .capturing: return "拍摄中"
        case .completed: return "拍摄完成"
        case .failed: return "拍摄失败"
        @unknown default: return "未知状态"
        }
    }
}

#else

// macOS stub
struct ObjectCaptureScannerView: View {
    var onComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                Text("功能不可用")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("3D 扫描功能仅在 iOS 设备上可用\n需要 LiDAR 设备（iPhone 12 Pro 及以上）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("返回")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#endif
