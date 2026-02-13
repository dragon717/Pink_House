import Foundation
import UIKit

enum QwenError: Error {
    case invalidImage
    case invalidResponse
    case apiError(String)
    case missingApiKey
}

struct QwenMessage: Codable {
    let role: String
    let content: [QwenContent]
}

struct QwenContent: Codable {
    let type: String // "text" or "image_url"
    let text: String?
    let image_url: QwenImageUrl?
}

struct QwenImageUrl: Codable {
    let url: String
}

struct QwenRequest: Codable {
    let model: String
    let messages: [QwenMessage]
    let stream: Bool
}

struct QwenResponse: Codable {
    let output: QwenOutput
    let usage: QwenUsage?
    let request_id: String?
}

struct QwenOutput: Codable {
    let text: String?
    let finish_reason: String?
    let choices: [QwenChoice]? // For OpenAI compatible format
}

struct QwenChoice: Codable {
    let message: QwenMessageContent
}

struct QwenMessageContent: Codable {
    let content: String
}

struct QwenUsage: Codable {
    let output_tokens: Int
    let input_tokens: Int
}

class QwenService {
    static let shared = QwenService()
    
    private let endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    private var apiKey: String? {
        return AIConfigManager.shared.qwenApiKey
    }
    
    private init() {}
    
    func analyzeImage(image: UIImage, prompt: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw QwenError.missingApiKey
        }
        
        // Resize image if too large (Qwen-VL limits)
        let processedImage = resizeImage(image: image, targetSize: CGSize(width: 1024, height: 1024))
        
        guard let imageData = processedImage.jpegData(compressionQuality: 0.8) else {
            throw QwenError.invalidImage
        }
        
        let base64Image = imageData.base64EncodedString()
        let dataUrl = "data:image/jpeg;base64,\(base64Image)"
        
        let messages = [
            QwenMessage(role: "user", content: [
                QwenContent(type: "image_url", text: nil, image_url: QwenImageUrl(url: dataUrl)),
                QwenContent(type: "text", text: prompt, image_url: nil)
            ])
        ]
        
        let requestBody = QwenRequest(
            model: "qwen-vl-max",
            messages: messages,
            stream: false
        )
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QwenError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Qwen API Error: \(errorString)")
            }
            throw QwenError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        // Decode response for OpenAI compatible format
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let content = openAIResponse.choices.first?.message.content {
            return content
        }
        
        throw QwenError.invalidResponse
    }
    
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
}
