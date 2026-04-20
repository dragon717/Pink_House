import SwiftUI
import RealityKit
import Foundation

#if os(iOS)

@available(iOS 18.0, *)
struct ObjectCaptureScannerView: View {

    @StateObject private var sessionManager = ObjectCaptureSessionManager.shared
    @Environment(\.dismiss) private var dismiss

    var onComplete: (URL) -> Void

    @State private var session: ObjectCaptureSession?
    @State private var showTips: Bool = true
    @State private var showNotSupportedAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var showLowPowerAlert: Bool = false
    @State private var isLowPowerMode: Bool = false

    var body: some View {
        ZStack {
            if isLowPowerMode {
                lowPowerWarningView
            } else if !sessionManager.isSupported {
                notSupportedView
            } else if let session = session {
                ObjectCaptureView(session: session)

                VStack {
                    topControls

                    Spacer()

                    if showTips {
                        tipsOverlay
                    }

                    bottomControls
                }
            } else {
                loadingView
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .objectCaptureScannerOpened, object: nil)
            checkLowPowerMode()
            setupSession()
        }
        .onDisappear {
            // 延迟重置以避免与 RealityKit 内部资源管理器的竞争条件
            // 这是一个 workaround 来解决 Apple 框架内部的断言失败问题
            // 注意：如果 session 已经被手动清理（如点击完成按钮），这里会安全地执行 reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // 只有当 session 还存在时才重置，避免重复清理
                if sessionManager.session != nil {
                    sessionManager.reset()
                }
            }
        }
        .onChange(of: sessionManager.state) { _, newState in
            handleStateChange(newState)
        }
        .alert("扫描失败", isPresented: $showErrorAlert) {
            Button("重试") {
                retrySession()
            }
            Button("取消", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("正在启动相机...")
                    .foregroundStyle(.white)
                    .font(.headline)
                Text("请确保光线充足")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func setupSession() {
        guard sessionManager.isSupported else {
            showNotSupportedAlert = true
            return
        }

        // 确保之前的 session 已完全清理
        sessionManager.reset()

        // 延迟创建新 session，避免与之前 session 的资源竞争
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.session = sessionManager.prepareSession()
        }
    }

    private func retrySession() {
        sessionManager.reset()
        showErrorAlert = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.session = sessionManager.prepareSession()
        }
    }

    private func handleStateChange(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .failed(let error):
            errorMessage = error.localizedDescription
            showErrorAlert = true
        default:
            break
        }
    }

    // MARK: - 省电模式检测

    private func checkLowPowerMode() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if isLowPowerMode {
            print("[ObjectCapture] 检测到省电模式已开启")
        }

        // 监听省电模式变化
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            if self.isLowPowerMode {
                print("[ObjectCapture] 省电模式已开启，扫描功能不可用")
                self.sessionManager.reset()
            }
        }
    }

    private var lowPowerWarningView: some View {
        VStack(spacing: 24) {
            Image(systemName: "battery.25")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(spacing: 12) {
                Text("省电模式已开启")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("3D 扫描需要大量计算资源，\n请在关闭省电模式后重试")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    // 打开设置
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("前往设置关闭省电模式")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                Button {
                    dismiss()
                } label: {
                    Text("返回")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
            // 取消按钮
            Button {
                sessionManager.cancelSession()
                dismiss()
            } label: {
                Text("取消")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }

            Spacer()

            // 状态文本
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)

            Spacer()

            // 下一步按钮（仅在 capturing 状态显示）
            if case .capturing = sessionManager.state {
                Button {
                    // 进入下一个轨道或完成
                    if sessionManager.currentOrbit < 3 {
                        sessionManager.currentOrbit += 1
                        print("[ObjectCaptureScannerView] 进入轨道 \(sessionManager.currentOrbit)")
                    } else {
                        // 已经是最后一个轨道，完成扫描
                        print("[ObjectCaptureScannerView] 顶部按钮：完成扫描")
                        guard let imageDir = sessionManager.currentImageDirectory else {
                            print("[ObjectCaptureScannerView] 错误: currentImageDirectory 为 nil")
                            return
                        }
                        sessionManager.finishCapturing()
                        print("[ObjectCaptureScannerView] 扫描完成，目录: \(imageDir.path)")
                        
                        // 先将本地 session 设为 nil，避免 ObjectCaptureView 渲染已销毁的 session
                        self.session = nil
                        // 清理 session manager
                        sessionManager.cancelSession()
                        
                        self.onComplete(imageDir)
                        self.dismiss()
                    }
                } label: {
                    Text(sessionManager.currentOrbit < 3 ? "下一步" : "完成")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            } else {
                // 占位保持平衡
                Button {
                    showTips.toggle()
                } label: {
                    Image(systemName: showTips ? "questionmark.circle.fill" : "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var statusText: String {
        switch sessionManager.state {
        case .initializing:
            return "初始化中"
        case .ready:
            return "准备就绪"
        case .detecting:
            return "检测物体中"
        case .capturing:
            return "轨道 \(sessionManager.currentOrbit) - \(sessionManager.numberOfShotsTaken)张"
        case .completed:
            return "完成"
        case .failed:
            return "错误"
        @unknown default:
            return "未知"
        }
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
        VStack(spacing: 12) {
            if case .capturing = sessionManager.state {
                orbitProgressIndicator
                captureProgress
            }

            actionButton
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // 360度轨道进度指示器（类似图二的原生样式）
    private var orbitProgressIndicator: some View {
        HStack(spacing: 20) {
            ForEach(1...3, id: \.self) { orbit in
                orbitIndicator(orbit: orbit)
            }
        }
        .padding(.vertical, 4)
    }

    private func orbitIndicator(orbit: Int) -> some View {
        let isCompleted = orbit < sessionManager.currentOrbit
        let isCurrent = orbit == sessionManager.currentOrbit
        let isPending = orbit > sessionManager.currentOrbit

        return ZStack {
            Circle()
                .stroke(isCompleted ? Color.green : Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 32, height: 32)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
            } else if isCurrent {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)

                Text("\(orbit)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(orbit)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var captureProgress: some View {
        VStack(spacing: 4) {
            // 显示原生进度：当前拍摄数 / 最大输入图像数
            HStack {
                Text("\(sessionManager.numberOfShotsTaken)/\(sessionManager.maximumNumberOfInputImages)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                if sessionManager.userCompletedScanPass {
                    Label("完成", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
            }

            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    let progress = min(CGFloat(sessionManager.numberOfShotsTaken) / CGFloat(max(sessionManager.maximumNumberOfInputImages, 1)), 1.0)
                    Rectangle()
                        .fill(sessionManager.userCompletedScanPass ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private var actionButton: some View {
        Group {
            if case .initializing = sessionManager.state {
                Button("初始化中...") {}
                    .disabled(true)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            } else if case .ready = sessionManager.state {
                Button("开始检测") {
                    print("[ObjectCaptureScannerView] 用户点击开始检测")
                    _ = sessionManager.startDetecting()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
            } else if case .detecting = sessionManager.state {
                Button("开始拍摄") {
                    print("[ObjectCaptureScannerView] 用户点击开始拍摄")
                    sessionManager.startCapturing()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .cornerRadius(12)
            } else if case .capturing = sessionManager.state {
                // 在 capturing 状态下，显示操作按钮
                VStack(spacing: 12) {
                    // 显示当前图片数量提示
                    HStack {
                        Image(systemName: "photo.stack")
                        Text("已拍摄 \(sessionManager.numberOfShotsTaken) 张")
                            .font(.subheadline)
                        if sessionManager.numberOfShotsTaken < 10 {
                            Text("(至少需10张)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("(✓ 可完成)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .foregroundStyle(.white)
                    
                    HStack(spacing: 12) {
                        // 完成按钮（结束整个扫描）- 需要至少10张图片
                        Button {
                            Task {
                                print("[ObjectCaptureScannerView] 用户点击完成按钮")
                                print("[ObjectCaptureScannerView] 当前 session 状态: \(String(describing: sessionManager.state))")
                                print("[ObjectCaptureScannerView] 已拍摄图片数: \(sessionManager.numberOfShotsTaken)")
                                print("[ObjectCaptureScannerView] currentImageDirectory: \(String(describing: sessionManager.currentImageDirectory))")
                                
                                // 检查图片数量
                                guard sessionManager.numberOfShotsTaken >= 10 else {
                                    await MainActor.run {
                                        errorMessage = "需要至少10张图片才能生成3D模型，当前只有 \(sessionManager.numberOfShotsTaken) 张"
                                        showErrorAlert = true
                                    }
                                    return
                                }

                                // 先获取目录
                                guard let imageDir = sessionManager.currentImageDirectory else {
                                    print("[ObjectCaptureScannerView] 错误: currentImageDirectory 为 nil")
                                    await MainActor.run {
                                        errorMessage = "无法获取图像目录"
                                        showErrorAlert = true
                                    }
                                    return
                                }
                                
                                // 使用异步方法等待捕获真正完成
                                let finalDir = await sessionManager.finishCapturingAsync()
                                
                                guard let finalImageDir = finalDir else {
                                    print("[ObjectCaptureScannerView] 错误: 无法获取最终目录")
                                    await MainActor.run {
                                        errorMessage = "扫描完成失败"
                                        showErrorAlert = true
                                    }
                                    return
                                }
                                
                                print("[ObjectCaptureScannerView] 扫描完成，目录: \(finalImageDir.path)")
                                
                                // 给系统一点时间确保所有文件写入完成
                                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                                
                                // 在主线程调用 onComplete
                                await MainActor.run {
                                    // 在调用 onComplete 之前，先将本地 session 设为 nil
                                    // 这样 ObjectCaptureView 就不会尝试渲染一个即将被销毁的 session
                                    self.session = nil
                                    
                                    // 清理 session manager，但保留图像目录信息
                                    sessionManager.cancelSession()
                                    
                                    self.onComplete(finalImageDir)
                                    self.dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("完成")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sessionManager.numberOfShotsTaken >= 10 ? Color.green : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .disabled(sessionManager.numberOfShotsTaken < 10)

                        // 下一步按钮（进入下一个轨道）
                        if sessionManager.currentOrbit < 3 {
                            Button {
                                sessionManager.currentOrbit += 1
                                // 这里可以添加进入下一个轨道的逻辑
                                print("[ObjectCaptureScannerView] 进入轨道 \(sessionManager.currentOrbit)")
                            } label: {
                                HStack {
                                    Text("下一步")
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                    }
                }
            } else if case .completed = sessionManager.state {
                Button("完成") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .cornerRadius(12)
            } else if case .failed = sessionManager.state {
                Button("重试") {
                    retrySession()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .cornerRadius(12)
            } else {
                Button("状态: \(String(describing: sessionManager.state))") {}
                    .disabled(true)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
    }
}

#endif
