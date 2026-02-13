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
        let selectedTone = UserDefaults.standard.string(forKey: "voiceToneId") ?? "SweetGirl"
        var voiceId = role.voiceConfig.thirdPartyVoiceId // 默认为角色配置
        
        // 映射用户选择的音色
        switch selectedTone {
        case "SweetGirl": voiceId = "zh_female_tianmei"
        case "GentleSister": voiceId = "zh_female_zhixing"
        case "LivelyGirl": voiceId = "zh_female_yuanqi"
        case "CoolLady": voiceId = "zh_female_kefu"
        default: break
        }
        
        // 如果没有有效的 voiceId，回退
        guard let finalVoiceId = voiceId,
              let appId = AIConfigManager.shared.ttsAppId,
              let token = AIConfigManager.shared.dbApiKey else {
            print("TTS Config Missing or voiceId nil")
            return false
        }
        
        let url = URL(string: "https://openspeech.bytedance.com/api/v1/tts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 火山引擎鉴权格式 Bearer; access_token (注意分号)
        request.setValue("Bearer; \(token)", forHTTPHeaderField: "Authorization")
        
        let reqId = UUID().uuidString
        let body: [String: Any] = [
            "app": [
                "appid": appId,
                "token": "access_token",
                "cluster": "volcano_icl"
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
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("TTS HTTP Error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                // 尝试打印错误信息
                if let errorMsg = String(data: data, encoding: .utf8) {
                    print("TTS Error Body: \(errorMsg)")
                }
                return false
            }
            
            // 解析 JSON
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 3000,
                  let base64Data = json["data"] as? String,
                  let audioData = Data(base64Encoded: base64Data) else {
                print("TTS Response Error or Decode Failed: \(String(data: data, encoding: .utf8) ?? "")")
                return false
            }
            
            // 播放音频
            return await MainActor.run {
                return playAudioData(audioData)
            }
            
        } catch {
            print("TTS Request Error: \(error)")
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
