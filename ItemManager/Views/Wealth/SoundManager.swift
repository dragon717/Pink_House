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
    // 1306: KeyPressClickPreview (短促)
    private let impactSoundID: SystemSoundID = 1103 // 较清脆，适合撞击
    private let heavyImpactSoundID: SystemSoundID = 1104 // 较沉闷，适合堆积 (Tock)
    
    // 滚动音效播放器（循环播放）
    private var rollingPlayer: AVAudioPlayer?
    private var isRolling: Bool = false
    
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
        // 1. 加载金豆撞击音效 (轻微/普通)
        if let url = Bundle.main.url(forResource: "gold_impact_soft", withExtension: "wav") {
            createPlayers(url: url)
        } else {
            // print("SoundManager: 'gold_impact_soft.wav' not found. Using SystemSound fallback.")
            useSystemSoundFallback = true
        }
        
        // 2. 加载滚动音效 (循环)
        if let rollUrl = Bundle.main.url(forResource: "gold_roll_loop", withExtension: "wav") {
            do {
                rollingPlayer = try AVAudioPlayer(contentsOf: rollUrl)
                rollingPlayer?.numberOfLoops = -1 // 无限循环
                rollingPlayer?.volume = 0
                rollingPlayer?.prepareToPlay()
            } catch {
                print("Failed to load rolling sound: \(error)")
            }
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
    
    enum ImpactType {
        case soft  // 金豆互撞
        case hard  // 撞墙/剧烈碰撞
    }
    
    /// 播放碰撞音效
    /// - Parameters:
    ///   - volume: 音量 (0.0 - 1.0)
    ///   - type: 碰撞类型
    func playCollisionSound(volume: Float, type: ImpactType = .soft) {
        guard isSoundEnabled else { return }
        
        if useSystemSoundFallback {
            // 系统音效无法控制音量，但为了有反馈，必须播放
            // 只有当 volume 足够大时才播放，避免太频繁
            if volume > 0.2 {
                // 根据类型选择不同的系统音效，模拟层次感
                if type == .hard {
                    // 撞墙才用稍微清脆的声音，但也别太尖锐
                    AudioServicesPlaySystemSound(impactSoundID)
                } else {
                    // 互撞强制使用沉闷的声音 (Tock)，避免高频 Tink 造成的蜂鸣感
                    // 只有在大力碰撞时偶尔混入一点清脆感
                    if volume > 0.8 && Bool.random() {
                         AudioServicesPlaySystemSound(impactSoundID)
                    } else {
                         AudioServicesPlaySystemSound(heavyImpactSoundID)
                    }
                }
            }
            return
        }
        
        guard !players.isEmpty else { return }
        
        // 简单轮询播放器
        let player = players[currentPlayerIndex]
        
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        
        // 随机化音量和速率（如果支持）
        let randomVol = max(0.1, min(volume + Float.random(in: -0.1...0.1), 1.0))
        player.volume = randomVol
        
        // 简单的音调模拟：虽然 AVAudioPlayer 的 rate 改变需要 enableRate=true 且可能影响时长
        // 但对于短促音效，稍微改变 rate 可以模拟不同的音高
        // player.enableRate = true
        // player.rate = Float.random(in: 0.9...1.1) 
        
        player.play()
        
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
    }
    
    /// 更新滚动音效
    /// - Parameter intensity: 滚动强度 (0.0 - 1.0)
    func updateRollingSound(intensity: Float) {
        guard isSoundEnabled, let player = rollingPlayer else { return }
        
        if intensity > 0.05 {
            if !player.isPlaying {
                player.play()
                player.volume = 0
            }
            // 平滑过渡音量
            let targetVolume = min(intensity * 0.5, 0.5) // 滚动声不要太大
            if abs(player.volume - targetVolume) > 0.05 {
                 player.volume = targetVolume
            }
        } else {
            if player.isPlaying {
                // 快速淡出
                if player.volume > 0.01 {
                    player.volume -= 0.05
                } else {
                    player.stop()
                }
            }
        }
    }
}
