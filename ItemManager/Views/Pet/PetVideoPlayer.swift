import SwiftUI
import AVKit
import Combine

struct PetVideoPlayer: UIViewControllerRepresentable {
    var videoName: String
    var isLooping: Bool
    var onFinished: (() -> Void)?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear // 尝试透明背景
        
        // 默认不播放声音
        // 注意：AVPlayerViewController 本身没有 isMuted 属性，需要通过 player 设置
        // 这里只是初始化 controller，player 在 updateUIViewController 中设置
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 尝试在根目录或 asserts 子目录查找视频
        var url = Bundle.main.url(forResource: videoName, withExtension: "mp4")
        if url == nil {
            url = Bundle.main.url(forResource: "asserts/\(videoName)", withExtension: "mp4")
        }
        // 如果找不到目标视频，回退到 idle
        if url == nil {
            url = Bundle.main.url(forResource: "idle", withExtension: "mp4")
        }
        if url == nil {
            url = Bundle.main.url(forResource: "asserts/idle", withExtension: "mp4")
        }
        
        let currentUrl = (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url
        
        // 如果 URL 变了，或者当前没有播放器
        if uiViewController.player == nil || (url != nil && currentUrl != url) {
            guard let validUrl = url else {
                print("Error: Could not find video resource: \(videoName) or idle.mp4")
                return
            }
            
            // 清理旧的状态
            context.coordinator.cleanup()
            
            if isLooping {
                // 使用 AVQueuePlayer + AVPlayerLooper 实现无缝循环
                let item = AVPlayerItem(url: validUrl)
                let player = AVQueuePlayer(playerItem: item)
                player.isMuted = true // 默认静音
                uiViewController.player = player
                
                context.coordinator.setupLooper(player: player, item: item, url: validUrl)
                player.play()
            } else {
                // 使用普通 AVPlayer 实现一次性播放
                let item = AVPlayerItem(url: validUrl)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true // 默认静音
                uiViewController.player = player
                
                context.coordinator.setupObserver(player: player, item: item, onFinished: onFinished)
                player.play()
            }
            
        } else {
            // 如果视频没变，确保正在播放
            if uiViewController.player?.timeControlStatus != .playing {
                uiViewController.player?.play()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var item: AVPlayerItem?
        var looper: AVPlayerLooper?
        var queuePlayer: AVQueuePlayer?
        var onFinished: (() -> Void)?
        var observer: Any?
        
        func setupLooper(player: AVQueuePlayer, item: AVPlayerItem, url: URL) {
            self.player = player
            self.queuePlayer = player
            self.item = item
            // 创建 Looper，这会自动处理循环
            self.looper = AVPlayerLooper(player: player, templateItem: item)
        }
        
        func setupObserver(player: AVPlayer, item: AVPlayerItem, onFinished: (() -> Void)?) {
            self.player = player
            self.item = item
            self.onFinished = onFinished
            
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
        
        func cleanup() {
            removeObserver()
            looper?.disableLooping()
            looper = nil
            queuePlayer?.removeAllItems()
            queuePlayer = nil
            player = nil
            item = nil
        }
        
        deinit {
            cleanup()
        }
    }
}
