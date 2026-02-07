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
            
            // 清理旧的观察者
            context.coordinator.removeObserver()
            
            let item = AVPlayerItem(url: validUrl)
            let player = AVPlayer(playerItem: item)
            uiViewController.player = player
            
            // 添加新的观察者
            context.coordinator.setupObserver(player: player, item: item, isLooping: isLooping, onFinished: onFinished)
            
            player.play()
        } else {
            // 如果视频没变，只更新循环状态（通常状态变了视频名也会变，所以这里可能不需要做太多）
            // 确保正在播放
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
        var isLooping: Bool = false
        var onFinished: (() -> Void)?
        var observer: Any?
        
        func setupObserver(player: AVPlayer, item: AVPlayerItem, isLooping: Bool, onFinished: (() -> Void)?) {
            self.player = player
            self.item = item
            self.isLooping = isLooping
            self.onFinished = onFinished
            
            // 移除旧的（如果有）
            removeObserver()
            
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                if self.isLooping {
                    self.player?.seek(to: .zero)
                    self.player?.play()
                } else {
                    self.onFinished?()
                }
            }
        }
        
        func removeObserver() {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
        
        deinit {
            removeObserver()
        }
    }
}
