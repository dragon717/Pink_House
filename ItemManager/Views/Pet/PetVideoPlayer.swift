import SwiftUI
import AVKit
import Combine

struct PetVideoPlayer: UIViewControllerRepresentable {
    var videoName: String
    var isLooping: Bool
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

        // 1. 尝试直接作为绝对路径加载 (用户指定路径)
        var url: URL?
        if videoName.hasPrefix("/") {
            url = URL(fileURLWithPath: videoName)
        }
        
        // 2. 尝试在 Bundle 根目录查找
        if url == nil {
            url = Bundle.main.url(forResource: videoName, withExtension: "mp4")
        }
        
        // 3. 尝试在 asserts 子目录查找 (标准方式)
        if url == nil {
            url = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "asserts")
        }
        
        // 4. 尝试在 asserts 子目录查找 (兼容方式)
        if url == nil {
            url = Bundle.main.url(forResource: "asserts/\(videoName)", withExtension: "mp4")
        }
        
        // 5. 尝试查找无后缀的文件
        if url == nil {
             if let bundleUrl = Bundle.main.url(forResource: videoName, withExtension: nil) {
                 url = bundleUrl
             } else if let bundleUrl = Bundle.main.url(forResource: videoName, withExtension: nil, subdirectory: "asserts") {
                 url = bundleUrl
             } else if let bundleUrl = Bundle.main.url(forResource: "asserts/\(videoName)", withExtension: nil) {
                 url = bundleUrl
             }
        }

        // 如果找不到目标视频，回退到 idle
        if url == nil {
            print("Error: Could not find video resource: \(videoName). Trying idle fallback.")
            url = Bundle.main.url(forResource: "idle", withExtension: "mp4")
        }
        if url == nil {
            url = Bundle.main.url(forResource: "idle", withExtension: "mp4", subdirectory: "asserts")
        }
        if url == nil {
            url = Bundle.main.url(forResource: "asserts/idle", withExtension: "mp4")
        }
        
        guard let validUrl = url else {
            print("Error: Could not find video resource: \(videoName) OR fallback idle.mp4")
            return
        }
        
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
                // 设置循环
                context.coordinator.setupLooper(item: newItem, url: validUrl)
                player.actionAtItemEnd = .advance // 循环播放需要自动推进
            } else {
                // 设置单次播放监听
                player.replaceCurrentItem(with: newItem)
                player.actionAtItemEnd = .pause // 单次播放结束暂停在最后一帧，防止黑屏
                context.coordinator.setupObserver(item: newItem, onFinished: onFinished)
            }
            
            // 确保播放
            player.play()
            
        } else {
            // URL 没变，但 isLooping 可能变了
            // 这种情况通常发生在长按松手时：视频还在播放，但需要从循环切换到单次结束
            if context.coordinator.isLooping != isLooping {
                guard let player = context.coordinator.queuePlayer else { return }
                
                // 如果从循环 -> 不循环
                if !isLooping {
                    print("PetVideoPlayer: Switching from Loop to Single Play (Stop Looping)")
                    // 禁用 Looper
                    context.coordinator.looper?.disableLooping()
                    context.coordinator.looper = nil
                    
                    player.actionAtItemEnd = .pause // 切换到单次播放时，也要确保结束暂停
                    
                    // 添加结束监听，以便播放完当前遍后调用 onFinished
                    if let currentItem = player.currentItem {
                        context.coordinator.setupObserver(item: currentItem, onFinished: onFinished)
                    }
                } 
                // 如果从不循环 -> 循环 (通常是重新开始互动，这通常会伴随 URL 变化，所以可能不会走到这分支，但处理一下也无妨)
                else {
                    print("PetVideoPlayer: Switching from Single Play to Loop")
                    if let currentItem = player.currentItem {
                         context.coordinator.removeObserver()
                         context.coordinator.setupLooper(item: currentItem, url: validUrl)
                         player.actionAtItemEnd = .advance // 恢复循环播放行为
                    }
                }
            }
            
            // 如果视频没变，确保正在播放
            if uiViewController.player?.timeControlStatus != .playing {
                uiViewController.player?.play()
            }
        }
        
        // 更新记录的状态
        context.coordinator.isLooping = isLooping
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var queuePlayer: AVQueuePlayer?
        var currentUrl: URL?
        var isLooping: Bool = false // 记录当前 Coordinator 的循环状态
        var looper: AVPlayerLooper?
        var onFinished: (() -> Void)?
        var observer: Any?
        
        func setupLooper(item: AVPlayerItem, url: URL) {
            guard let player = queuePlayer else { return }
            
            // 创建 Looper，这会自动处理循环
            // 注意：AVPlayerLooper 需要传入 templateItem
            self.looper = AVPlayerLooper(player: player, templateItem: item)
            self.currentUrl = url
        }
        
        func setupObserver(item: AVPlayerItem, onFinished: (() -> Void)?) {
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
            looper?.disableLooping()
            looper = nil
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
}
