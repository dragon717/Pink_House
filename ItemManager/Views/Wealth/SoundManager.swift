import AVFoundation
import UIKit
import Combine

/// 管理所有音频反馈的管理器
/// 负责加载和播放碰撞音效
@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    // 用户偏好设置
    @Published var isSoundEnabled: Bool = true
    
    // 音频播放器池，用于支持并发播放
    private var players: [AVAudioPlayer] = []
    private let maxConcurrentPlayers = 10
    private var currentPlayerIndex = 0
    
    // Fallback: 如果没有音频文件，使用系统音效
    private var useSystemSoundFallback = false
    // 1103: Tink (短促的金属声), 1057: PINKeyPressed (机械点击声), 1104: Tock
    private let systemSoundID: SystemSoundID = 1103
    
    private init() {
        prepareAudioSession()
        loadSounds()
    }
    
    private func prepareAudioSession() {
        do {
            // 设置为 playback 模式，确保在静音模式下也能播放声音
            // 允许混音 (mixWithOthers)，以免打断后台音乐
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    
    private func loadSounds() {
        // 加载金豆撞击音效
        // 假设我们有一个名为 "gold_hit.mp3" 或 "coin_drop.wav" 的文件
        // 这里我们先检查 Bundle 中是否有类似文件，如果没有，需要后续添加
        // 为了演示，我们尝试加载一个系统声音或者预留接口
        
        // 实际上，为了效果最好，应该使用简短的 wav 文件
        // 如果项目中没有文件，我们暂时无法播放，但逻辑可以写好
        
        // 示例：加载资源
        if let url = Bundle.main.url(forResource: "gold_clink", withExtension: "wav") {
            createPlayers(url: url)
        } else {
            print("SoundManager: 'gold_clink.wav' not found in bundle. Using SystemSound fallback.")
            useSystemSoundFallback = true
        }
    }
    
    private func createPlayers(url: URL) {
        for _ in 0..<maxConcurrentPlayers {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players.append(player)
            } catch {
                print("Failed to create audio player: \(error)")
            }
        }
    }
    
    /// 播放碰撞音效
    /// - Parameters:
    ///   - volume: 音量 (0.0 - 1.0)
    ///   - pitch: 音调 (0.5 - 2.0) - 注意：AVAudioPlayer 的 enableRate 需要为 true 才能变调，但变调可能会有延迟。
    ///            简单起见，我们主要控制音量。
    func playCollisionSound(volume: Float) {
        guard isSoundEnabled else { return }
        
        if useSystemSoundFallback {
            // 系统音效无法控制音量，但为了有反馈，必须播放
            // 只有当 volume 足够大时才播放，避免太频繁
            if volume > 0.3 {
                AudioServicesPlaySystemSound(systemSoundID)
            }
            return
        }
        
        guard !players.isEmpty else { return }
        
        let player = players[currentPlayerIndex]
        
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        
        // 稍微随机化音量，更自然
        let randomVol = max(0.1, min(volume + Float.random(in: -0.1...0.1), 1.0))
        player.volume = randomVol
        
        // 播放
        player.play()
        
        // 轮换播放器
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
    }
}
