import CoreHaptics
import UIKit
import Combine
import SwiftUI // Import SwiftUI for AppStorage or other property wrappers if needed, but Combine is key for ObservableObject

/// 管理所有触觉反馈的高级管理器
/// 负责处理 Core Haptics 引擎的生命周期、震动模式生成以及空间感模拟
@MainActor
final class HapticEngineManager: ObservableObject {
    static let shared = HapticEngineManager()
    
    private var engine: CHHapticEngine?
    private var isEngineRunning = false
    
    // 用户偏好设置
    @Published var isHapticsEnabled: Bool = true
    
    // 集成声音管理器
    private let soundManager = SoundManager.shared
    
    // 持续震动播放器 (Advanced Player)
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    
    // 硬件支持标志
    private var supportsCoreHaptics: Bool = false
    
    // 系统震感开启状态 (移除自动检测，改为手动测试状态)
    // @Published var isSystemHapticsEnabled: Bool = true
    
    private init() {
        prepareHaptics()
        setupLifecycleObserver()
    }
    
    private func setupLifecycleObserver() {
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            print("App entering foreground, restarting Haptic Engine...")
            self?.isEngineRunning = false
            self?.startEngineIfNeeded()
        }
    }
    
    /// 初始化触觉引擎
    func prepareHaptics() {
        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        supportsCoreHaptics = hapticCapability.supportsHaptics
        
        guard supportsCoreHaptics else {
            print("Device does not support Core Haptics. Fallback to UIKit haptics.")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.isAutoShutdownEnabled = true
            
            // 处理引擎停止的回调 (例如应用进入后台)
            engine?.stoppedHandler = { [weak self] reason in
                print("Haptic Engine Stopped: \(reason)")
                Task { @MainActor in
                    self?.isEngineRunning = false
                }
            }
            
            // 处理引擎重置的回调
            engine?.resetHandler = { [weak self] in
                print("Haptic Engine Reset")
                Task { @MainActor in
                    self?.isEngineRunning = false
                    self?.prepareHaptics()
                }
            }
        } catch {
            print("Haptic Engine Creation Error: \(error)")
        }
    }
    
    /// 启动引擎（如果尚未运行）
    private func startEngineIfNeeded() {
        guard isHapticsEnabled, let engine = engine, !isEngineRunning else { return }
        
        do {
            try engine.start()
            isEngineRunning = true
            
            // 引擎启动后，预备持续震动模式
            prepareContinuousHaptic()
        } catch let error as NSError {
            print("Haptic Engine Start Error: Code \(error.code), Description: \(error.localizedDescription)")
        }
    }
    
    /// 播放测试震动
    func playTestHaptic() {
        guard isHapticsEnabled else { return }
        
        // 确保引擎运行
        startEngineIfNeeded()
        
        // 播放一个明显的瞬态震动
        if supportsCoreHaptics, let engine = engine {
            do {
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ], relativeTime: 0)
                
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
            } catch {
                print("Failed to play test haptic: \(error)")
            }
        } else {
            // Fallback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        
        // 同时播放一个系统音效作为参考（如果能听到声音但没震动，更容易判断）
        soundManager.playCollisionSound(volume: 1.0)
    }
    
    /// 预备持续震动模式（Continuous Haptic）
    /// 创建一个强度为 0 的持续震动，后续通过动态参数进行调制
    private func prepareContinuousHaptic() {
        guard let engine = engine else { return }
        
        // 定义一个无限时长的持续震动事件
        // 初始强度设为 0，避免一开始就有感觉
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)
        
        // duration 设为很大，例如 3600 秒，或者根据需要循环
        let continuousEvent = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: 3600)
        
        do {
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            // 使用 Advanced Player 以支持 sendParameters
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            continuousPlayer?.loopEnabled = true // 循环播放
            try continuousPlayer?.start(atTime: 0)
        } catch {
            print("Failed to prepare continuous haptic: \(error)")
        }
    }
    
    /// 实时更新空间震感参数 (Modulation)
    /// - Parameters:
    ///   - intensity: 整体震动强度 (0.0 - 1.0)
    ///   - sharpness: 震动锐度 (0.0 - 1.0)
    ///   - position: 空间位置 (x: 0-1, y: 0-1) [可选]
    func updateHapticParameters(intensity: Float, sharpness: Float, position: CGPoint? = nil) {
        guard isHapticsEnabled, let player = continuousPlayer else { return }
        
        // 确保引擎运行
        startEngineIfNeeded()
        
        // 动态参数列表
        var dynamicParams: [CHHapticDynamicParameter] = []
        
        // 1. 强度调制
        let clampedIntensity = max(0.0, min(intensity, 1.0))
        let intensityParam = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: clampedIntensity, relativeTime: 0)
        dynamicParams.append(intensityParam)
        
        // 2. 锐度调制
        let clampedSharpness = max(0.0, min(sharpness, 1.0))
        let sharpnessParam = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: clampedSharpness, relativeTime: 0)
        dynamicParams.append(sharpnessParam)
        
        // 3. 空间调制 (Audio Pan) - 仅在支持设备上有效，且对 Continuous 效果有限，但值得一试
        if let pos = position {
            // x: 0 (Left) -> 1 (Right)  => Pan: -1 -> 1
            let panValue = (pos.x * 2.0) - 1.0
            // 注意：Core Haptics 并没有直接暴露 hapticPanControl 动态参数，
            // 但我们可以通过 audioPanControl 间接影响（如果是 Haptic+Audio 模式），或者通过分别调整左右强度来实现（需要两个 Player）。
            // 简单起见，这里我们只调制主参数，空间感主要依靠“瞬态撞击”来实现定位，持续震动负责“氛围”。
        }
        
        // 发送动态参数
        do {
            try player.sendParameters(dynamicParams, atTime: 0) // 0 表示立即
        } catch {
            print("Failed to update haptic parameters: \(error)")
        }
    }
    
    /// 触发一次碰撞震动（模拟金豆撞击）
    /// - Parameters:
    ///   - intensity: 震动强度 (0.0 - 1.0)，通常基于碰撞速度
    ///   - sharpness: 震动锐度 (0.0 - 1.0)，模拟材质硬度
    ///   - position: 屏幕归一化坐标 (x: 0-1, y: 0-1)，用于模拟空间感
    func playCollisionHaptic(intensity: Float, sharpness: Float, position: CGPoint? = nil) {
        // 声音总是尝试播放（即使没有震动引擎）
        // 参数限制
        let clampedIntensity = max(0.1, min(intensity, 1.0))
        soundManager.playCollisionSound(volume: clampedIntensity)
        
        guard isHapticsEnabled else { return }
        
        // 如果不支持 Core Haptics 或引擎未就绪，使用 UIKit Fallback
        if !supportsCoreHaptics || engine == nil {
            if clampedIntensity > 0.6 {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } else if clampedIntensity > 0.3 {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            return
        }
        
        // 确保引擎正在运行
        startEngineIfNeeded()
        
        let clampedSharpness = max(0.1, min(sharpness, 1.0))
        
        // 创建触觉事件参数
        var events: [CHHapticEvent] = []
        var parameters: [CHHapticEventParameter] = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: clampedSharpness)
        ]
        
        // 增加随机微扰动，使连续震动听起来不那么机械
        // 仅在低强度时添加轻微随机性
        let randomFactor = Float.random(in: -0.05...0.05)
        if clampedIntensity < 0.5 {
             parameters.append(CHHapticEventParameter(parameterID: .attackTime, value: max(0, 0.01 + randomFactor)))
        }
        
        // 尝试添加基本的立体声参数 (虽然手机上效果有限，但有助于区分左右)
        // 0.0 是最左，1.0 是最右
        if let pos = position {
            // 将 x 坐标映射到 -1.0 到 1.0 的音频声像范围 (Audio Pan)
            // 实际上 Core Haptics 的 audioPan 默认映射到 [-1.0, 1.0]
            // 输入 pos.x 是 [0.0, 1.0]
            let panValue = (pos.x * 2.0) - 1.0
            parameters.append(CHHapticEventParameter(parameterID: .audioPan, value: Float(panValue)))
        }
        
        // 创建瞬态事件 (Transient Event) - 适合撞击
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0)
        events.append(event)
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
            
            // 音效已经在前面触发了，不需要重复
            
        } catch {
            print("Failed to play haptic: \(error)")
        }
    }
    
    /// 播放连续的滚动纹理（当大量金豆移动时）
    /// - Parameter intensity: 整体滚动的剧烈程度
    func playRollingTexture(intensity: Float) {
        // 这是一个预留接口，用于处理持续的“沙沙”声震感
        // 实现需要使用 CHHapticEvent(eventType: .hapticContinuous, ...)
    }
}
