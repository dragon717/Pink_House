import AVFoundation
import UIKit
import Combine

/// 负责将 AI 的回复转换为语音 (TTS)
/// 支持原生 AVSpeechSynthesizer 和预留的第三方 TTS 接口
@MainActor
final class PetVoiceManager: NSObject, ObservableObject {
    static let shared = PetVoiceManager()
    
    // MARK: - Configuration
    
    /// 是否优先使用第三方 TTS 服务
    /// 如果开启但调用失败，会自动降级到原生
    @Published var preferThirdPartyTTS: Bool = true
    
    @Published var isSpeaking: Bool = false
    
    // MARK: - Native TTS
    private let synthesizer = AVSpeechSynthesizer()
    
    // MARK: - Third Party TTS Player
    private var audioPlayer: AVAudioPlayer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// 朗读文本
    /// - Parameters:
    ///   - text: 要朗读的文本
    ///   - role: 宠物角色（决定音色）
    func speak(_ text: String, for role: PetRole) {
        // 检查全局声音开关
        guard SoundManager.shared.isSoundEnabled else {
            return
        }
        
        // 1. 停止当前的朗读
        stop()
        
        // 2. 净化文本（去除表情符号、动作描述等）
        let cleanText = cleanTextForSpeech(text)
        guard !cleanText.isEmpty else { return }
        
        // 获取用户设置的语音模型优先级
        let voiceModelId = UserDefaults.standard.string(forKey: "voiceModelId") ?? "Volcengine"
        let useThirdParty = (voiceModelId == "Volcengine")
        
        Task {
            // 3. 尝试第三方 TTS
            if useThirdParty {
                let success = await speakWithThirdParty(text: cleanText, role: role)
                if success {
                    return
                }
                // 如果失败，继续执行原生逻辑
                print("PetVoiceManager: Third-party TTS failed or not implemented, falling back to native.")
            }
            
            // 4. 原生 TTS 回退
            speakWithNative(text: cleanText, role: role)
        }
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        isSpeaking = false
    }
    
    // MARK: - Private Implementation
    
    private func speakWithNative(text: String, role: PetRole) {
        let config = role.voiceConfig
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.pitchMultiplier = config.pitchMultiplier
        utterance.rate = config.rate
        utterance.volume = config.volume
        
        // 选择语音
        if let voiceId = config.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            // 默认中文
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        
        // 确保 AudioSession 设置正确
        // 使用 .duckOthers 让背景音乐自动降低音量
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("PetVoiceManager: Failed to set audio session: \(error)")
        }
        
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    /// 模拟/预留第三方 TTS 调用
    /// 返回 true 表示成功处理，false 表示需要回退
    private func speakWithThirdParty(text: String, role: PetRole) async -> Bool {
        // 获取用户设置的音色
        let selectedTone = UserDefaults.standard.string(forKey: "voiceToneId") ?? "Shota"
        var voiceId = role.voiceConfig.thirdPartyVoiceId // 默认为角色配置
        
        // 映射用户选择的音色
        print("🔍 [PetVoiceManager] Selected tone from UserDefaults: \(selectedTone)")
        
        // 强制使用用户选择的音色，忽略角色默认配置（如果有选择的话）
        // 只有当 selectedTone 为默认值且角色有特殊配置时才考虑角色配置？
        // 或者始终让用户设置覆盖角色默认？
        // 目前逻辑是：先取角色默认，然后 switch selectedTone 覆盖。
        // 但 switch case 覆盖了所有已知选项，所以实际上角色配置只在 selectedTone 为未知值时生效。
        
        switch selectedTone {
        case "Shota": voiceId = "ICL_zh_male_fengfashaonian_tob"
        // 恢复为标准精品音色 ID (需要开通“语音合成”服务的精品音色权限)
        case "SweetGirl": voiceId = "BV406_streaming" // VV
        case "GentleSister": voiceId = "ICL_zh_female_wenrouwenya_tob"
        case "LivelyGirl": voiceId = "BV407_streaming" // 小和
        case "CoolLady": voiceId = "ICL_zh_female_chengshujiejie_tob"
        case "GentleMale": voiceId = "BV002_streaming" // 云舟
        case "MagneticMale": voiceId = "BV123_streaming" // 小天
        default: 
            print("⚠️ [PetVoiceManager] Unknown tone: \(selectedTone), using role default: \(voiceId ?? "nil")")
            break
        }
        
        print("🔍 [PetVoiceManager] Resolved Voice ID: \(voiceId ?? "nil")")
        
        // 如果没有有效的 voiceId，回退
        guard let finalVoiceId = voiceId,
              let appId = AIConfigManager.shared.ttsAppId,
              let token = AIConfigManager.shared.dbApiKey else {
            print("❌ [PetVoiceManager] Config Missing. AppID: \(AIConfigManager.shared.ttsAppId ?? "nil"), Token: \(AIConfigManager.shared.dbApiKey != nil ? "Exists" : "nil"), VoiceID: \(voiceId ?? "nil")")
            return false
        }
        
        let url = URL(string: "https://openspeech.bytedance.com/api/v1/tts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 火山引擎鉴权格式 Bearer; access_token (注意分号)
        request.setValue("Bearer; \(token)", forHTTPHeaderField: "Authorization")
        
        // 确定 cluster based on voiceId prefix
        // ICL_, S_, saturn_ 开头的为克隆音色，使用 volcano_icl
        // 其他情况，默认为 volcano_icl 以避免 403 (假设用户只开通了 ICL)
        var cluster = "volcano_icl"
        if !finalVoiceId.hasPrefix("ICL_") && !finalVoiceId.hasPrefix("S_") && !finalVoiceId.hasPrefix("saturn_") {
            // 如果 ID 不是 ICL 格式，尝试使用 volcano_tts，但很可能会失败
             cluster = "volcano_tts"
        }
        
        print("🔍 [PetVoiceManager] Determining cluster for voiceId: \(finalVoiceId) -> \(cluster)")
        
        let reqId = UUID().uuidString
        let body: [String: Any] = [
            "app": [
                "appid": appId,
                "token": "access_token",
                "cluster": cluster
            ],
            "user": [
                "uid": UIDevice.current.identifierForVendor?.uuidString ?? "user_1"
            ],
            "audio": [
                "voice_type": finalVoiceId,
                "encoding": "mp3",
                "speed_ratio": 1.0, // API 参数范围可能不同，先使用默认
                "volume_ratio": 1.0,
                "pitch_ratio": 1.0
            ],
            "request": [
                "reqid": reqId,
                "text": text,
                "text_type": "plain",
                "operation": "query"
            ]
        ]
        
        print("🔍 [PetVoiceManager] TTS Request Body: appid=\(appId), cluster=\(cluster), voice_type=\(finalVoiceId)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("🚀 [PetVoiceManager] Sending TTS request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                 print("❌ [PetVoiceManager] Invalid response type")
                 return false
            }
            
            print("📥 [PetVoiceManager] Received response: Status \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ [PetVoiceManager] TTS HTTP Error: \(httpResponse.statusCode)")
                // 尝试打印错误信息
                if let errorMsg = String(data: data, encoding: .utf8) {
                    print("❌ [PetVoiceManager] Error Body: \(errorMsg)")
                    
                    // 智能提示：检测 10029 错误 (端到端服务不支持 HTTP)
                    if errorMsg.contains("volc.service_type.10029") {
                        print("""
                        ⚠️ [严重错误] 您当前使用的 AppID 属于「豆包端到端实时语音大模型」服务。
                        该服务仅支持 WebSocket 协议，不支持当前代码使用的 HTTP 协议。
                        
                        ✅ 解决方案：
                        请前往火山引擎控制台 -> 语音技术 -> 语音合成 (Standard TTS)。
                        开通「语音合成」服务，并获取对应的 AppID 和 Token 替换到项目中。
                        """)
                    }
                }
                return false
            }
            
            // 解析 JSON
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [PetVoiceManager] TTS Response Decode Failed")
                if let str = String(data: data, encoding: .utf8) {
                     print("Raw response: \(str)")
                }
                return false
            }
            
            if let code = json["code"] as? Int, code == 3000 {
               if let base64Data = json["data"] as? String,
                  let audioData = Data(base64Encoded: base64Data) {
                   print("✅ [PetVoiceManager] TTS Success. Audio data size: \(audioData.count) bytes")
                   // 播放音频
                   return await MainActor.run {
                       return playAudioData(audioData)
                   }
               } else {
                   print("❌ [PetVoiceManager] Code 3000 but data missing or invalid base64")
                   return false
               }
            } else {
                print("❌ [PetVoiceManager] TTS API Error. Code: \(json["code"] ?? "nil"), Message: \(json["message"] ?? "nil")")
                print("Full Response: \(json)")
                return false
            }
            
        } catch {
            print("❌ [PetVoiceManager] TTS Request Exception: \(error)")
            return false
        }
    }
    
    private func playAudioData(_ data: Data) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 确保数据不为空
            guard !data.isEmpty else {
                print("Audio data is empty")
                return false
            }
            
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            if audioPlayer?.play() == true {
                isSpeaking = true
                return true
            }
            return false
        } catch {
            print("AudioPlayer Init Error: \(error)")
            return false
        }
    }
    
    private func cleanTextForSpeech(_ text: String) -> String {
        // 去除 [IMAGE:...]
        var cleaned = text.replacingOccurrences(of: "\\[IMAGE:[^\\]]+\\]", with: "", options: .regularExpression)
        
        // 去除动作描述 (...) 或 （...）
        // 注意：有些动作描述可能很有趣，但 TTS 读出来很怪。
        // 比如 "(歪头) 你好呀" -> "歪头 你好呀" 还是 "你好呀"？通常不读动作。
        cleaned = cleaned.replacingOccurrences(of: "\\([^\\)]+\\)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "（[^）]+）", with: "", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVAudioPlayerDelegate
extension PetVoiceManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.audioPlayer === player {
                self.isSpeaking = false
            }
        }
    }
}
// MARK: - AVSpeechSynthesizerDelegate
extension PetVoiceManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            // 可以在这里通知 AudioManager 恢复状态，如果需要的话
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
