import Foundation
import Vision
import UIKit
import CoreImage
import SwiftUI
import Combine

class VisionAnalysisService: ObservableObject {
    static let shared = VisionAnalysisService()
    
    @Published var isProcessing: Bool = false
    
    private init() {}
    
    struct AnalysisResult {
        let context: String // Full prompt context for AI
        let suggestedQuestion: String // User-friendly question (e.g., "Is this price good?")
    }

    // 识别图片中的文字并格式化为上下文
    func recognizeContent(from image: UIImage, completion: @escaping (AnalysisResult) -> Void) {
        self.isProcessing = true
        
        // 检查模型优先级
        let priorityString = UserDefaults.standard.string(forKey: "visualModelPriority") ?? "Qwen3-VL,Apple Vision"
        let models = priorityString.split(separator: ",").map { String($0) }
        let firstModel = models.first ?? "Qwen3-VL"
        
        if firstModel == "Qwen3-VL" && AIConfigManager.shared.qwenApiKey != nil {
            print("🔍 Using Qwen3-VL for vision analysis")
            Task {
                do {
                    // 优化提示词，要求结构化输出
                    let prompt = """
                    请详细分析这张图片。请严格按照以下格式输出：
                    
                    【视觉描述】
                    (精炼描述图片内容，如果是商品请提取名称、价格、状态；如果是生物请描述外观动作)
                    
                    【猜你想问】
                    1. (基于图片内容的本身提问)
                    2. (基于图片内容的延伸提问)
                    3. (基于图片内容的数字提问)
                    """
                    
                    let result = try await QwenService.shared.analyzeImage(image: image, prompt: prompt)
                    
                    // Parse suggested question
                    var suggestedQuestion = "这是什么？"
                    if let range = result.range(of: "【猜你想问】") {
                        let questionsPart = String(result[range.upperBound...])
                        let lines = questionsPart.split(separator: "\n")
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            // Match "1. Question" format
                            if let firstDigit = trimmed.first, firstDigit.isNumber {
                                if let dotIndex = trimmed.firstIndex(of: ".") {
                                    let q = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                                    if !q.isEmpty {
                                        suggestedQuestion = q
                                        break
                                    }
                                }
                            }
                        }
                    }
                    
                    let contextPrompt = """
                    [视觉输入 - Qwen3-VL]
                    用户向你展示了一张图片，Qwen3-VL 的分析结果如下：
                    
                    \(result)
                    
                    请基于【视觉描述】与用户互动，并可以参考【猜你想问】中的内容引导话题。
                    """
                    
                    await MainActor.run {
                        self.isProcessing = false
                        completion(AnalysisResult(context: contextPrompt, suggestedQuestion: suggestedQuestion))
                    }
                } catch {
                    print("⚠️ Qwen3-VL failed: \(error). Falling back to Apple Vision.")
                    // Fallback to Apple Vision
                    self.performAppleVisionAnalysis(from: image, completion: completion)
                }
            }
        } else {
            print("🔍 Using Apple Vision for analysis")
            performAppleVisionAnalysis(from: image, completion: completion)
        }
    }
    
    private func performAppleVisionAnalysis(from image: UIImage, completion: @escaping (AnalysisResult) -> Void) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(AnalysisResult(context: "无法识别图片内容", suggestedQuestion: "这是什么？"))
            }
            return
        }
        
        var recognizedText = ""
        var classificationTerms: [String] = []
        
        let group = DispatchGroup()
        
        // 1. 文字识别 (Text Recognition)
        group.enter()
        let textRequest = VNRecognizeTextRequest { request, error in
            defer { group.leave() }
            if let observations = request.results as? [VNRecognizedTextObservation] {
                recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        
        // 2. 图像分类 (Image Classification)
        group.enter()
        let classifyRequest = VNClassifyImageRequest { request, error in
            defer { group.leave() }
            if let observations = request.results as? [VNClassificationObservation] {
                // 取前5个置信度高的分类
                classificationTerms = observations.prefix(5).filter { $0.confidence > 0.3 }.map { $0.identifier }
            }
        }
        
        // 执行请求
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([textRequest, classifyRequest])
            } catch {
                print("Vision Error: \(error)")
            }
            
            group.notify(queue: .main) {
                self.isProcessing = false
                
                // 构建结构化输出
                var description = ""
                var questions: [String] = []
                
                if !recognizedText.isEmpty {
                    description += "图片包含文字信息：\n\(recognizedText)\n"
                    if recognizedText.contains("¥") || recognizedText.contains("价格") {
                        questions.append("这个价格划算吗？")
                        questions.append("什么时候截团？")
                    }
                }
                
                if !classificationTerms.isEmpty {
                    // 简单的分类翻译或直接使用 (这里简化处理，实际可能需要映射表)
                    // VNClassifyImageRequest 返回的是英文标签 (e.g., "tabby, tabby cat")
                    let tags = classificationTerms.joined(separator: ", ")
                    description += "图片识别到的物体标签：\(tags)"
                    
                    if tags.contains("cat") || tags.contains("dog") {
                        questions.append("它叫什么名字？")
                        questions.append("它几岁了？")
                    } else if tags.contains("food") || tags.contains("dish") {
                        questions.append("这是哪里买的？")
                        questions.append("好吃吗？")
                    } else if tags.contains("apparel") || tags.contains("clothing") {
                        questions.append("这是什么牌子的？")
                        questions.append("有其他颜色吗？")
                    }
                }
                
                if description.isEmpty {
                    description = "似乎是一张没有明显文字或可识别物体的图片。"
                    questions.append("这张图有什么特别的吗？")
                }
                
                // 补充通用问题
                if questions.isEmpty {
                    questions.append("这是什么？")
                    questions.append("你觉得怎么样？")
                }
                
                let contextPrompt = """
                [视觉输入 - Apple Vision]
                用户向你展示了一张图片，本地分析结果如下：
                
                【视觉描述】
                \(description)
                
                【猜你想问】
                \(questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
                
                请基于这些信息推断物品性质，并与用户互动。
                """
                
                // Pick the first suggested question
                let suggestedQuestion = questions.first ?? "这是什么？"
                
                completion(AnalysisResult(context: contextPrompt, suggestedQuestion: suggestedQuestion))
            }
        }
    }
}
