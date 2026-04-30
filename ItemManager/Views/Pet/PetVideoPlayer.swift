import SwiftUI
import AVKit
import Combine
import UIKit

struct PetVideoPlayer: UIViewControllerRepresentable {
    var videoName: String
    var isLooping: Bool
    var playbackRate: Float = 1.0
    var isMuted: Bool = false
    var volume: Float = 0.6 // 默认降低音量，防止与 BGM 叠加破音
    var onFinished: (() -> Void)?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear 
        
        // 预先创建 AVQueuePlayer 并赋值
        // 使用 AVQueuePlayer 兼容 AVPlayerLooper
        let player = AVQueuePlayer()
        player.isMuted = isMuted
        player.volume = volume
        controller.player = player
        
        // 保存到 coordinator 以便后续操作
        context.coordinator.queuePlayer = player
        context.coordinator.installFallbackImageView(in: controller.view)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 更新音量和静音状态
        if let player = uiViewController.player {
            if player.volume != volume {
                player.volume = volume
            }
            if player.isMuted != isMuted {
                player.isMuted = isMuted
            }
        }

        if TransparentVideoSupport.shouldSuppress(videoName: videoName) {
            if let player = uiViewController.player {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            context.coordinator.cleanupOldState()
            context.coordinator.currentUrl = nil
            context.coordinator.showFallbackImage(for: videoName)
            return
        }

        context.coordinator.hideFallbackImage()

        // 使用 VideoResourceManager 查找视频
        var url = VideoResourceManager.shared.findVideoURL(name: videoName)

        // 如果找不到目标视频，尝试回退逻辑
        if url == nil {
            print("Error: Could not find video resource: \(videoName). Trying fallbacks.")
            
            // 1. 尝试根据前缀回退到 idle (例如 maomao_eating -> maomao_idle)
            if let underscoreIndex = videoName.firstIndex(of: "_") {
                let prefix = videoName.prefix(upTo: underscoreIndex)
                let fallbackName = "\(prefix)_idle"
                if fallbackName != videoName {
                    url = VideoResourceManager.shared.findVideoURL(name: fallbackName)
                }
            }
            
            // 2. 尝试默认角色 (奶茶) 的 idle
            if url == nil {
                url = VideoResourceManager.shared.findVideoURL(name: "naicha_idle")
            }
            
            // 3. 尝试旧版 idle (兼容)
            if url == nil {
                url = Bundle.main.url(forResource: "idle", withExtension: "mp4")
            }
            if url == nil {
                url = Bundle.main.url(forResource: "idle", withExtension: "mp4", subdirectory: "asserts")
            }
        }
        
        guard let validUrl = url else {
            print("Error: Could not find video resource: \(videoName) OR fallback idle.mp4")
            return
        }

        context.coordinator.playbackRate = playbackRate
        
        // 检查是否需要更新视频
        // 通过 context.coordinator 记录当前正在播放的 URL，避免依赖 uiViewController.player 状态
        if context.coordinator.currentUrl != validUrl {
            // 准备新的 Item
            let newItem = AVPlayerItem(url: validUrl)
            
            // 获取之前保存的 queuePlayer
            guard let player = context.coordinator.queuePlayer else { return }
            
            // 清理旧的状态（如 Looper、Observer）
            context.coordinator.cleanupOldState()
            
            if isLooping {
                player.replaceCurrentItem(with: newItem)
                player.actionAtItemEnd = .none
                context.coordinator.setupObserver(item: newItem, onFinished: onFinished, isLooping: true)
            } else {
                // 设置单次播放监听
                player.replaceCurrentItem(with: newItem)
                player.actionAtItemEnd = .pause // 单次播放结束暂停在最后一帧，防止黑屏
                context.coordinator.setupObserver(item: newItem, onFinished: onFinished, isLooping: false)
            }
            
            // 确保播放
            play(player)
            
        } else {
            // URL 没变，但 isLooping 可能变了
            // 这种情况通常发生在长按松手时：视频还在播放，但需要从循环切换到单次结束
            if context.coordinator.isLooping != isLooping {
                guard let player = context.coordinator.queuePlayer else { return }
                
                // 如果从循环 -> 不循环
                if !isLooping {
                    player.actionAtItemEnd = .pause // 切换到单次播放时，也要确保结束暂停
                    
                    // 添加结束监听，以便播放完当前遍后调用 onFinished
                    if let currentItem = player.currentItem {
                        context.coordinator.setupObserver(item: currentItem, onFinished: onFinished, isLooping: false)
                    }
                } 
                // 如果从不循环 -> 循环 (通常是重新开始互动，这通常会伴随 URL 变化，所以可能不会走到这分支，但处理一下也无妨)
                else {
                    if let currentItem = player.currentItem {
                         player.actionAtItemEnd = .none
                         context.coordinator.setupObserver(item: currentItem, onFinished: onFinished, isLooping: true)
                    }
                }
            }
            
            // 如果视频没变，确保正在播放
            if uiViewController.player?.timeControlStatus != .playing {
                if let queuePlayer = context.coordinator.queuePlayer {
                    play(queuePlayer)
                }
            }
        }
        
        // 更新记录的状态
        context.coordinator.isLooping = isLooping

        // 速率可能动态变化，保持一致
        if let queuePlayer = context.coordinator.queuePlayer,
           queuePlayer.timeControlStatus == .playing {
            queuePlayer.rate = max(0.1, playbackRate)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var queuePlayer: AVQueuePlayer?
        var currentUrl: URL?
        var isLooping: Bool = false // 记录当前 Coordinator 的循环状态
        var onFinished: (() -> Void)?
        var observer: Any?
        var playbackRate: Float = 1.0
        private weak var fallbackImageView: UIImageView?

        func installFallbackImageView(in container: UIView) {
            guard fallbackImageView == nil else { return }
            let imageView = UIImageView(frame: container.bounds)
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .clear
            imageView.isHidden = true
            container.addSubview(imageView)
            fallbackImageView = imageView
        }

        func showFallbackImage(for videoName: String) {
            let image = TransparentVideoSupport
                .fallbackImageName(for: videoName)
                .flatMap { UIImage(named: $0) }
            fallbackImageView?.image = image
            fallbackImageView?.isHidden = image == nil
        }

        func hideFallbackImage() {
            fallbackImageView?.isHidden = true
            fallbackImageView?.image = nil
        }
        
        func setupObserver(item: AVPlayerItem, onFinished: (() -> Void)?, isLooping: Bool) {
            self.onFinished = onFinished
            self.currentUrl = (item.asset as? AVURLAsset)?.url
            
            // 移除旧的（如果有）
            removeObserver()
            
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                if isLooping, let player = self.queuePlayer {
                    let safeRate = max(self.playbackRate, 0.1)
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if abs(safeRate - 1.0) < 0.01 {
                            player.play()
                        } else {
                            player.playImmediately(atRate: safeRate)
                        }
                    }
                    return
                }
                self.onFinished?()
            }
        }
        
        func removeObserver() {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
        
        func cleanupOldState() {
            removeObserver()
            // 注意：不要把 queuePlayer 置空，因为它是复用的
        }
        
        // 彻底清理（deinit 用）
        func cleanupAll() {
            cleanupOldState()
            queuePlayer?.removeAllItems()
            queuePlayer = nil
        }
        
        deinit {
            cleanupAll()
        }
    }

    private func play(_ player: AVQueuePlayer) {
        let safeRate = max(0.1, playbackRate)
        if abs(safeRate - 1.0) < 0.01 {
            player.play()
        } else {
            player.playImmediately(atRate: safeRate)
        }
    }
}
