import SwiftUI
import AVFoundation
import Combine

/// 一个支持无缝切换的双缓冲视频播放器视图 (UIView)
class SeamlessVideoPlayerView: UIView {
    // 双播放器系统
    private var playerLayerA: AVPlayerLayer = AVPlayerLayer()
    private var playerLayerB: AVPlayerLayer = AVPlayerLayer()
    
    private var playerA: AVQueuePlayer = AVQueuePlayer()
    private var playerB: AVQueuePlayer = AVQueuePlayer()
    
    // 状态追踪
    private var activeLayer: AVPlayerLayer?
    private var activePlayer: AVQueuePlayer?
    private var activeLooper: AVPlayerLooper?
    
    // 当前配置
    private var currentVideoName: String?
    private var isLooping: Bool = false
    private var isMuted: Bool = false
    private var volume: Float = 1.0
    private var onFinished: (() -> Void)?
    
    // 观察者
    private var finishObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var watchdogTimer: Timer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupWatchdog()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupWatchdog()
    }
    
    private func setupWatchdog() {
        // 每 2 秒检查一次播放状态 (保底逻辑)
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPlaybackStatus()
        }
    }
    
    private func checkPlaybackStatus() {
        guard let player = activePlayer else { return }
        
        // 1. 检查是否正在播放
        if player.timeControlStatus != .playing {
            print("SeamlessPlayer Watchdog: Player is NOT playing (Status: \(player.timeControlStatus.rawValue)). Attempting to resume.")
            player.play()
        }
        
        // 2. 检查是否卡在非循环视频的结束状态
        // 如果当前不应该循环，且视频已经播完了，但 onFinished 没触发（导致卡住）
        if !isLooping, let item = player.currentItem {
            let currentTime = item.currentTime().seconds
            let duration = item.duration.seconds
            
            // 如果已经播放到末尾 (允许 0.2s 误差)
            if duration > 0 && currentTime >= duration - 0.2 {
                print("SeamlessPlayer Watchdog: Video finished but callback missing. Forcing finish.")
                onFinished?()
            }
        }
        
        // 3. 极端保底：如果当前没有任何 Item，尝试重新加载
        if player.currentItem == nil {
             print("SeamlessPlayer Watchdog: No item in player. Reloading current video.")
             if let name = currentVideoName {
                 loadAndSwitch(to: name, looping: isLooping)
             }
        }
    }
    
    private func setupLayers() {
        // 配置 Layer A
        playerLayerA.player = playerA
        playerLayerA.videoGravity = .resizeAspectFill
        playerLayerA.backgroundColor = UIColor.clear.cgColor
        playerLayerA.frame = bounds
        playerLayerA.opacity = 0 // 初始隐藏
        layer.addSublayer(playerLayerA)
        
        // 配置 Layer B
        playerLayerB.player = playerB
        playerLayerB.videoGravity = .resizeAspectFill
        playerLayerB.backgroundColor = UIColor.clear.cgColor
        playerLayerB.frame = bounds
        playerLayerB.opacity = 0 // 初始隐藏
        layer.addSublayer(playerLayerB)
        
        // 初始激活 A (虽然还没播放)
        activeLayer = playerLayerA
        activePlayer = playerA
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayerA.frame = bounds
        playerLayerB.frame = bounds
    }
    
    // MARK: - Public Interface
    
    func update(videoName: String, isLooping: Bool, isMuted: Bool, volume: Float, onFinished: (() -> Void)?) {
        // 更新非视频属性
        self.isMuted = isMuted
        self.volume = volume
        self.onFinished = onFinished
        
        updateVolumeAndMute()
        
        // 检查视频是否变化
        if self.currentVideoName != videoName {
            print("SeamlessPlayer: Switching video to \(videoName)")
            self.currentVideoName = videoName
            self.isLooping = isLooping // 记录新视频的循环状态
            loadAndSwitch(to: videoName, looping: isLooping)
        } else {
            // 视频没变，但循环状态可能变了 (例如长按松手)
            if self.isLooping != isLooping {
                print("SeamlessPlayer: Loop state changed to \(isLooping)")
                self.isLooping = isLooping
                updateLoopingState(isLooping: isLooping)
            }
            
            // 确保正在播放
            if activePlayer?.timeControlStatus != .playing {
                activePlayer?.play()
            }
        }
    }
    
    // MARK: - Internal Logic
    
    private func updateVolumeAndMute() {
        playerA.isMuted = isMuted
        playerA.volume = volume
        playerB.isMuted = isMuted
        playerB.volume = volume
    }
    
    private func loadAndSwitch(to videoName: String, looping: Bool) {
        guard let url = findVideoURL(name: videoName) else {
            print("SeamlessPlayer: Failed to find video \(videoName)")
            return
        }
        
        // 确定下一个使用的播放器 (如果当前是 A，下一个用 B，反之亦然)
        let nextPlayer: AVQueuePlayer
        let nextLayer: AVPlayerLayer
        
        if activePlayer === playerA {
            nextPlayer = playerB
            nextLayer = playerLayerB
        } else {
            nextPlayer = playerA
            nextLayer = playerLayerA
        }
        
        // 准备 Item
        let item = AVPlayerItem(url: url)
        
        // 清理下一个播放器的旧状态
        nextPlayer.removeAllItems()
        
        // 设置循环或单次
        // 注意：我们不能在这里直接设置 Looper，因为 Looper 需要 player 已经有 item 或者由 Looper 来设置
        // 这里的策略是：先让 player 准备好，一旦 readyForDisplay 再切换显示
        
        // 我们需要一个临时引用来持有 Looper，直到切换完成赋值给 activeLooper
        // 但由于 Looper 绑定在 Player 上，我们可以直接操作
        
        // 移除旧的 Looper (如果有) - 这里是指 nextPlayer 上可能残留的 Looper？
        // 实际上 AVPlayerLooper 是一次性的，我们需要创建新的。
        
        // 加载逻辑
        if looping {
            // 对于循环，我们使用 AVPlayerLooper
            // 但 Looper 需要 player，我们得在切换后保存引用
            // 这里先暂存，等 ready 后再处理？
            // 不，AVPlayerLooper 创建时就会开始控制 Player。
            // 我们可以现在就创建，反正 Layer 是隐藏的。
            
            // 为了避免 Looper 立即播放导致声音泄漏（虽然隐藏了 Layer），我们先 Mute，或者依赖 updateVolumeAndMute
            // updateVolumeAndMute 已经设置了正确的 mute/volume。
            
            // 关键：我们需要监听 readyForDisplay
        } else {
            nextPlayer.replaceCurrentItem(with: item)
        }
        
        // 监听 ReadyForDisplay
        // KVO 监听 layer 的 isReadyForDisplay 是最准确的
        // 但 AVPlayerLayer.isReadyForDisplay 只有在关联了 player 且 player 有内容时才变 true
        
        // 我们使用一个临时对象来捕获本次切换的上下文
        var transitionContext = TransitionContext(
            player: nextPlayer,
            layer: nextLayer,
            item: item,
            isLooping: looping
        )
        
        // 开始加载
        if looping {
            transitionContext.looper = AVPlayerLooper(player: nextPlayer, templateItem: item)
        } else {
            // 单次播放
            // 已经在上面 replaceCurrentItem 了
        }
        
        // 预播放 (缓冲)
        nextPlayer.play()
        
        // 监听
        // 移除旧的 status 监听
        statusObserver?.invalidate()
        
        // 监听 nextLayer.isReadyForDisplay
        // 注意：在模拟器上 isReadyForDisplay 有时不可靠，但在真机上通常可以。
        // 另一种方法是监听 item.status == .readyToPlay
        
        statusObserver = nextLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, change in
            guard let self = self else { return }
            if layer.isReadyForDisplay {
                // 只有当这是我们需要的目标播放器时才切换 (防止旧的监听回调)
                if layer === nextLayer {
                    DispatchQueue.main.async {
                        self.performSwitch(context: transitionContext)
                    }
                }
            }
        }
        
        // 设置超时保护：如果 0.5 秒还没 ready，强制切换（避免永远不切）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // 如果 activeLayer 还是旧的，且 nextPlayer 正在播放，强制切
            if self.activeLayer !== nextLayer && nextPlayer.timeControlStatus == .playing {
                self.performSwitch(context: transitionContext)
            }
        }
    }
    
    private struct TransitionContext {
        let player: AVQueuePlayer
        let layer: AVPlayerLayer
        let item: AVPlayerItem
        let isLooping: Bool
        var looper: AVPlayerLooper?
    }
    
    private func performSwitch(context: TransitionContext) {
        guard activeLayer !== context.layer else { return } // 已经切过了
        
        print("SeamlessPlayer: Performing switch")
        
        // 1. 显示新 Layer
        context.layer.opacity = 1
        
        // 记录旧 Layer 和 Player
        let oldLayer = activeLayer
        let oldPlayer = activePlayer
        
        // 3. 更新状态 (立即更新 active 指针，这样后续的逻辑都知道谁是新的)
        activeLayer = context.layer
        activePlayer = context.player
        activeLooper = context.looper
        
        // 4. 清理观察者
        statusObserver?.invalidate()
        statusObserver = nil
        
        // 5. 设置结束监听 (如果是单次播放)
        setupFinishObserver(for: context.item, isLooping: context.isLooping)
        
        // 延迟关闭旧视频 (实现 50ms 重叠)
        if let layerToHide = oldLayer, let playerToStop = oldPlayer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                
                // 关键检查：确保要隐藏的 Layer 确实不再是 activeLayer
                // 如果在 50ms 内又切回去了，那么 activeLayer 就会等于 layerToHide，此时不应该隐藏
                if self.activeLayer !== layerToHide {
                    // 使用 CoreAnimation 事务
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layerToHide.opacity = 0
                    CATransaction.commit()
                    
                    playerToStop.pause()
                    playerToStop.removeAllItems()
                }
            }
        }
    }
    
    private func updateLoopingState(isLooping: Bool) {
        guard let player = activePlayer, let currentItem = player.currentItem else { return }
        
        if isLooping {
            // 单次 -> 循环
            if activeLooper == nil {
                removeFinishObserver()
                activeLooper = AVPlayerLooper(player: player, templateItem: currentItem)
                player.play()
            }
        } else {
            // 循环 -> 单次
            if let looper = activeLooper {
                print("SeamlessPlayer: Disabling looping")
                looper.disableLooping()
                activeLooper = nil
                
                // 关键修复：在添加监听前，先检查是否已经播完
                // 如果在 disableLooping 的瞬间刚好播完，AVPlayer 可能已经停止，且不会再触发 Notification
                let currentTime = currentItem.currentTime().seconds
                let duration = currentItem.duration.seconds
                
                // 如果剩余时间极短 (< 0.1s) 或者已经结束，直接触发完成
                if duration > 0 && currentTime >= duration - 0.1 {
                     print("SeamlessPlayer: Video already near end, triggering finish manually")
                     self.onFinished?()
                } else {
                     // 正常添加结束监听
                     setupFinishObserver(for: currentItem, isLooping: false)
                }
            }
        }
    }
    
    private func setupFinishObserver(for item: AVPlayerItem, isLooping: Bool) {
        removeFinishObserver()
        
        if !isLooping {
            finishObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                print("SeamlessPlayer: Finished playing")
                self.onFinished?()
            }
        }
    }
    
    private func removeFinishObserver() {
        if let observer = finishObserver {
            NotificationCenter.default.removeObserver(observer)
            finishObserver = nil
        }
    }
    
    private func findVideoURL(name: String) -> URL? {
        // 1. 绝对路径
        if name.hasPrefix("/") {
            return URL(fileURLWithPath: name)
        }
        // 2. Bundle 根目录
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            return url
        }
        // 3. asserts 子目录
        if let url = Bundle.main.url(forResource: "asserts/\(name)", withExtension: "mp4") {
            return url
        }
        // 4. 无后缀尝试
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        if let url = Bundle.main.url(forResource: "asserts/\(name)", withExtension: nil) {
            return url
        }
        // 5. Fallback idle
        print("SeamlessPlayer: Fallback to idle")
        return Bundle.main.url(forResource: "idle", withExtension: "mp4") ?? 
               Bundle.main.url(forResource: "asserts/idle", withExtension: "mp4")
    }
    
    deinit {
        statusObserver?.invalidate()
        removeFinishObserver()
    }
}

// MARK: - SwiftUI Wrapper

struct SeamlessVideoPlayer: UIViewRepresentable {
    var videoName: String
    var isLooping: Bool
    var isMuted: Bool
    var volume: Float
    var onFinished: (() -> Void)?
    
    func makeUIView(context: Context) -> SeamlessVideoPlayerView {
        let view = SeamlessVideoPlayerView()
        view.backgroundColor = .clear // 确保 View 本身透明
        return view
    }
    
    func updateUIView(_ uiView: SeamlessVideoPlayerView, context: Context) {
        uiView.update(
            videoName: videoName,
            isLooping: isLooping,
            isMuted: isMuted,
            volume: volume,
            onFinished: onFinished
        )
    }
}
