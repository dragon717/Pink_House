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
    
    private init() {
        prepareHaptics()
    }
    
    /// 初始化触觉引擎
    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
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
        } catch {
            print("Haptic Engine Start Error: \(error)")
        }
    }
    
    /// 触发一次碰撞震动（模拟金豆撞击）
    /// - Parameters:
    ///   - intensity: 震动强度 (0.0 - 1.0)，通常基于碰撞速度
    ///   - sharpness: 震动锐度 (0.0 - 1.0)，模拟材质硬度
    ///   - position: 屏幕归一化坐标 (x: 0-1, y: 0-1)，用于模拟空间感
    func playCollisionHaptic(intensity: Float, sharpness: Float, position: CGPoint? = nil) {
        guard isHapticsEnabled, let engine = engine else { return }
        
        // 确保引擎正在运行
        startEngineIfNeeded()
        
        // 参数限制
        let clampedIntensity = max(0.1, min(intensity, 1.0))
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
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
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
