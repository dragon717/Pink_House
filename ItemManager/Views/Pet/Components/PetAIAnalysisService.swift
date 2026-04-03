import SwiftUI
import Combine

// MARK: - AI分析状态

enum PetAIAnalysisState: Equatable {
    case idle
    case analyzing
    case completed(result: PetAIAnalysisResult)
    case failed(error: PetAIAnalysisError)
    
    static func == (lhs: PetAIAnalysisState, rhs: PetAIAnalysisState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.analyzing, .analyzing):
            return true
        case (.completed(let lhsResult), .completed(let rhsResult)):
            return lhsResult.question == rhsResult.question && lhsResult.answer == rhsResult.answer
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - AI分析结果

struct PetAIAnalysisResult {
    let question: String
    let answer: String
    let image: UIImage?
    let context: String
    let timestamp: Date
    
    init(
        question: String,
        answer: String,
        image: UIImage?,
        context: String,
        timestamp: Date = Date()
    ) {
        self.question = question
        self.answer = answer
        self.image = image
        self.context = context
        self.timestamp = timestamp
    }
}

// MARK: - AI分析错误

enum PetAIAnalysisError: LocalizedError {
    case insufficientContent
    case visionFailed(Error)
    case aiFailed(Error)
    case imageCaptureFailed
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .insufficientContent:
            return "图片内容不足，无法识别"
        case .visionFailed(let error):
            return "图像识别失败: \(error.localizedDescription)"
        case .aiFailed(let error):
            return "AI分析失败: \(error.localizedDescription)"
        case .imageCaptureFailed:
            return "截图失败"
        case .cancelled:
            return "分析已取消"
        }
    }
}

// MARK: - AI分析服务

class PetAIAnalysisService: ObservableObject {
    static let shared = PetAIAnalysisService()
    
    // MARK: - Published Properties
    
    @Published var state: PetAIAnalysisState = .idle
    @Published var isAnalyzing: Bool = false
    
    // MARK: - Dependencies
    
    private let visionAnalysis = VisionAnalysisService.shared
    private let hapticManager = HapticEngineManager.shared
    
    // MARK: - Configuration
    
    private let screenshotScale: CGFloat = 0.5
    private let padding: CGFloat = 20
    private let minContentLength = 10
    private let insufficientContentKeywords = ["似乎是一张没有文字的图片"]
    
    // MARK: - Task Management
    
    private var currentTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 分析指定区域的图像
    /// - Parameters:
    ///   - rect: 分析区域
    ///   - screenSize: 屏幕尺寸
    ///   - captureBlock: 截图回调
    /// - Returns: 分析结果
    func analyzeArea(
        rect: CGRect,
        screenSize: CGSize,
        captureBlock: @escaping (CGRect, CGFloat) -> UIImage?
    ) async throws -> PetAIAnalysisResult {
        // 取消之前的任务
        cancel()
        
        // 保存配置值
        let padding = self.padding
        let screenshotScale = self.screenshotScale
        
        return try await withCheckedThrowingContinuation { continuation in
            currentTask = Task { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PetAIAnalysisError.cancelled)
                    return
                }
                
                do {
                    await MainActor.run {
                        self.state = .analyzing
                        self.isAnalyzing = true
                    }
                    
                    // 添加padding
                    let paddedRect = rect.insetBy(dx: -padding, dy: -padding)
                    
                    // 截图
                    guard let image = captureBlock(paddedRect, screenshotScale) else {
                        throw PetAIAnalysisError.imageCaptureFailed
                    }
                    
                    // 执行分析
                    let result = try await self.performAnalysis(image: image)
                    
                    // 检查结果是否足够
                    if self.shouldRetryWithFullScreen(result: result) {
                        // 尝试全屏分析
                        let fullScreenResult = try await self.performFullScreenAnalysis(
                            screenSize: screenSize,
                            captureBlock: captureBlock
                        )
                        continuation.resume(returning: fullScreenResult)
                    } else {
                        continuation.resume(returning: result)
                    }
                    
                } catch {
                    await MainActor.run {
                        self.state = .failed(error: error as? PetAIAnalysisError ?? .aiFailed(error))
                        self.isAnalyzing = false
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 分析指定图像
    /// - Parameter image: 要分析的图像
    /// - Returns: 分析结果
    func analyzeImage(_ image: UIImage) async throws -> PetAIAnalysisResult {
        // 取消之前的任务
        cancel()
        
        return try await withCheckedThrowingContinuation { continuation in
            currentTask = Task { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PetAIAnalysisError.cancelled)
                    return
                }
                
                do {
                    await MainActor.run {
                        self.state = .analyzing
                        self.isAnalyzing = true
                    }
                    
                    let result = try await self.performAnalysis(image: image)
                    
                    await MainActor.run {
                        self.state = .completed(result: result)
                        self.isAnalyzing = false
                    }
                    
                    continuation.resume(returning: result)
                    
                } catch {
                    await MainActor.run {
                        self.state = .failed(error: error as? PetAIAnalysisError ?? .aiFailed(error))
                        self.isAnalyzing = false
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 取消当前分析
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        
        if case .analyzing = state {
            state = .idle
            isAnalyzing = false
        }
    }
    
    /// 重置状态
    func reset() {
        cancel()
        state = .idle
        isAnalyzing = false
    }
    
    // MARK: - Private Methods
    
    private func performAnalysis(image: UIImage) async throws -> PetAIAnalysisResult {
        // 触发触觉反馈
        await MainActor.run {
            self.hapticManager.playUIFeedback(intensity: 1.0, sharpness: 0.5, fallbackStyle: .heavy)
        }
        
        // 第一步：Vision识别
        let visionResult = try await performVisionRecognition(image)

        if !VIPManager.shared.isVIP {
            return PetAIAnalysisResult(
                question: visionResult.suggestedQuestion,
                answer: localOnlyAnswer(from: visionResult),
                image: image,
                context: visionResult.context
            )
        }
        
        // 第二步：AI分析
        let aiResult = await performAIRequest(
            question: visionResult.suggestedQuestion,
            context: visionResult.context,
            image: image
        )
        
        return PetAIAnalysisResult(
            question: visionResult.suggestedQuestion,
            answer: aiResult.text,
            image: image,
            context: visionResult.context
        )
    }

    private func localOnlyAnswer(from result: VisionAnalysisService.AnalysisResult) -> String {
        let compactContext = result.context
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(48)
        return "我先用本地识别帮你看了一圈喵：\(compactContext)… 想让我继续认真分析，升级 VIP 就能解锁更完整的图片理解啦~"
    }
    
    private func performVisionRecognition(_ image: UIImage) async throws -> VisionAnalysisService.AnalysisResult {
        try await withCheckedThrowingContinuation { continuation in
            visionAnalysis.recognizeContent(from: image) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func performAIRequest(
        question: String,
        context: String,
        image: UIImage
    ) async -> ChatMessage {
        await PetAIService.shared.sendImageAnalysisRequest(
            text: question,
            imageContext: context,
            image: image
        )
    }
    
    private func shouldRetryWithFullScreen(result: PetAIAnalysisResult) -> Bool {
        // 检查内容长度
        if result.context.count < minContentLength {
            return true
        }
        
        // 检查是否包含不足内容的关键词
        for keyword in insufficientContentKeywords {
            if result.context.contains(keyword) {
                return true
            }
        }
        
        return false
    }
    
    private func performFullScreenAnalysis(
        screenSize: CGSize,
        captureBlock: @escaping (CGRect, CGFloat) -> UIImage?
    ) async throws -> PetAIAnalysisResult {
        // 等待UI更新
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        // 截取全屏
        let fullScreenRect = CGRect(origin: .zero, size: screenSize)
        guard let fullScreenImage = captureBlock(fullScreenRect, screenshotScale) else {
            throw PetAIAnalysisError.imageCaptureFailed
        }
        
        // 分析全屏图像
        return try await performAnalysis(image: fullScreenImage)
    }
}

// MARK: - AI分析结果视图

struct PetAIAnalysisResultView: View {
    let result: PetAIAnalysisResult
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Text("AI分析结果")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 图片预览
            if let image = result.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // 问题
            VStack(alignment: .leading, spacing: 4) {
                Text("问题")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.question)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 回答
            VStack(alignment: .leading, spacing: 4) {
                Text("回答")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.answer)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 关闭按钮
            Button(action: onClose) {
                Text("关闭")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .padding(.horizontal, 20)
    }
}

// MARK: - AI分析中视图

struct PetAIAnalyzingView: View {
    let petName: String
    
    var body: some View {
        VStack(spacing: 8) {
            // 思考中的猫图片
            Image("thinking_cat")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .shadow(radius: 4)
            
            HStack(spacing: 4) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
                Text("\(petName)正在思考中...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
        }
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.opacity(0.3)
        
        VStack(spacing: 20) {
            PetAIAnalyzingView(petName: "奶茶")
            
            PetAIAnalysisResultView(
                result: PetAIAnalysisResult(
                    question: "这是什么？",
                    answer: "这是一件漂亮的洛丽塔裙装，粉色系，带有蕾丝装饰。",
                    image: nil,
                    context: "图片中显示了一件粉色的洛丽塔风格裙装"
                ),
                onClose: {}
            )
        }
    }
}
