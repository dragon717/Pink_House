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
    private var currentLoadID: UUID? // 用于防止异步回调冲突
    
    // 当前配置
    private var currentVideoName: String?
    private var isLooping: Bool = false
    private var isMuted: Bool = false
    private var volume: Float = 1.0
    private var onFinished: (() -> Void)?
    private var onProgress: ((Double, Double) -> Void)?
    
    // 观察者
    private var finishObserver: Any?
    private var timeObserver: Any?
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
        
        // 0. 检查 item 是否丢失 (Player 变空)
        // 这种情况可能由 XPC 崩溃或逻辑错误引起
        if player.currentItem == nil {
             print("SeamlessPlayer Watchdog: No item in player. Reloading current video.")
             if let name = currentVideoName {
                 loadAndSwitch(to: name, looping: isLooping)
             }
             return // 直接返回，因为已经触发重载
        }
        
        // 1. 检查是否正在播放
        if player.timeControlStatus != .playing {
            // 如果是单次播放，且已经结束，就不应该 resume
            if !isLooping, let item = player.currentItem {
                let currentTime = item.currentTime().seconds
                let duration = item.duration.seconds
                // 允许 0.1s 误差
                if duration > 0 && currentTime >= duration - 0.1 {
                    return // 正常结束，不 resume
                }
            }
            
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
                // 这里我们不需要打印日志或强制 finish，因为正常情况下 onFinished 应该已经触发过了
                // 但如果是真的卡住了（UI没收到回调），这里再次触发也是安全的（onFinished 应该是幂等的或者 UI 会处理）
                // print("SeamlessPlayer Watchdog: Video finished check.") 
            }
        }
        
        // 3. 极端保底：如果当前没有任何 Item，尝试重新加载
        // (已上移到步骤 0)
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
    
    func update(videoName: String, isLooping: Bool, isMuted: Bool, volume: Float, onFinished: (() -> Void)?, onProgress: ((Double, Double) -> Void)?) {
        // 更新非视频属性
        self.isMuted = isMuted
        self.volume = volume
        self.onFinished = onFinished
        self.onProgress = onProgress
        
        updateVolumeAndMute()
        
        // 检查视频是否变化
        if self.currentVideoName != videoName {
            print("SeamlessPlayer: Switching video to \(videoName) (looping: \(isLooping))")
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
                // 如果是单次播放，且已经结束，就不应该 resume
                if !isLooping, let item = activePlayer?.currentItem {
                     let currentTime = item.currentTime().seconds
                     let duration = item.duration.seconds
                     if duration > 0 && currentTime >= duration - 0.1 {
                         // 已经播完了，忽略
                     } else {
                         print("SeamlessPlayer: Resuming playback for \(videoName)")
                         activePlayer?.play()
                     }
                } else {
                    print("SeamlessPlayer: Resuming playback for \(videoName)")
                    activePlayer?.play()
                }
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
        let loadID = UUID()
        self.currentLoadID = loadID
        
        print("SeamlessPlayer: loadAndSwitch to \(videoName), looping: \(looping), loadID: \(loadID)")
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
        
        // 关键设置：根据循环模式决定播放结束后的行为
        if looping {
            // 循环模式：必须允许前进，以便 Looper 能够衔接下一个副本
            nextPlayer.actionAtItemEnd = .advance
        } else {
            // 单次模式：播放结束后暂停，保留最后一帧，防止 Item 被自动移除
            nextPlayer.actionAtItemEnd = .pause
        }
        
        // 加载逻辑
        if looping {
            // ... (Looper 逻辑在后面处理)
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
            // 检查 loadID 是否匹配
            guard self.currentLoadID == loadID else {
                print("SeamlessPlayer: Ignoring obsolete ready callback for \(videoName)")
                return
            }
            
            if layer.isReadyForDisplay {
                // 只有当这是我们需要的目标播放器时才切换 (防止旧的监听回调)
                if layer === nextLayer {
                    DispatchQueue.main.async {
                        // 再次检查 ID
                        guard self.currentLoadID == loadID else { return }
                        self.performSwitch(context: transitionContext)
                    }
                }
            }
        }
        
        // 设置超时保护：如果 0.5 秒还没 ready，强制切换（避免永远不切）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // 检查 loadID 是否匹配
            guard self.currentLoadID == loadID else { return }
            
            // 如果 activeLayer 还是旧的，且 nextPlayer 正在播放，强制切
            if self.activeLayer !== nextLayer && nextPlayer.timeControlStatus == .playing {
                print("SeamlessPlayer: Force switching due to timeout for \(videoName)")
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
        
        // 增加对 isReadyForDisplay 的检查
        // 如果是超时触发的，可能此时 layer 还没 ready，如果强制显示可能会是黑屏
        // 但如果不切，用户就一直看旧视频。
        // 对于双缓冲，我们宁愿看旧视频也不要看黑屏。
        if !context.layer.isReadyForDisplay {
            print("SeamlessPlayer: WARNING - Layer is NOT ready for display during switch. Aborting switch to avoid black screen.")
            // 我们可以在这里尝试再延迟一下？
            // 或者直接放弃本次切换，等待下一次（如果 KVO 还在工作）
            // 但如果 KVO 失效了（比如模拟器），这就永远切不过去了。
            // 权衡：如果已经 play() 了 0.5s，大概率有画面了，isReadyForDisplay 可能不准。
            // 但如果真的没画面，切过去就是灾难。
            
            // 策略：如果 activeLayer 还有画面（player 还在播），那就再等等。
            if activePlayer?.timeControlStatus == .playing {
                 print("SeamlessPlayer: Active player still playing, deferring switch.")
                 return
            }
        }
        
        // 1. 显示新 Layer
        context.layer.opacity = 1
        
        // 记录旧 Layer 和 Player
        let oldLayer = activeLayer
        let oldPlayer = activePlayer
        
        // 移除旧的时间监听
        if let timeObserver = timeObserver {
            oldPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // 3. 更新状态 (立即更新 active 指针，这样后续的逻辑都知道谁是新的)
        activeLayer = context.layer
        activePlayer = context.player
        activeLooper = context.looper
        
        // 4. 清理观察者
        statusObserver?.invalidate()
        statusObserver = nil
        
        // 5. 设置结束监听 (如果是单次播放)
        setupFinishObserver(for: context.item, isLooping: context.isLooping)
        
        // 关键：状态同步
        // 如果当前 self.isLooping 已经变为 false，但 context.isLooping 为 true (说明加载过程中被改了)
        // 我们需要立即应用新的状态，否则 UI 认为不循环，但 Looper 还在跑
        if self.isLooping != context.isLooping {
            print("SeamlessPlayer: State mismatch after switch (self: \(self.isLooping), context: \(context.isLooping)). Syncing...")
            updateLoopingState(isLooping: self.isLooping)
        }
        
        // 6. 设置进度监听
        setupTimeObserver(for: context.player)
        
        // 延迟关闭旧视频 (增加重叠时间以避免黑屏)
        if let layerToHide = oldLayer, let playerToStop = oldPlayer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                
                // 关键检查：确保要隐藏的 Layer 确实不再是 activeLayer
                if self.activeLayer !== layerToHide {
                    // 使用 CoreAnimation 事务
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layerToHide.opacity = 0
                    CATransaction.commit()
                    
                    playerToStop.pause()
                    // 不要立即清空，以免闪烁，等待下一次复用时会清空
                    // playerToStop.removeAllItems()
                }
            }
        }
    }
    
    private func updateLoopingState(isLooping: Bool) {
        guard let player = activePlayer, let currentItem = player.currentItem else { 
            print("SeamlessPlayer: updateLoopingState ignored (no player/item)")
            return 
        }
        
        if isLooping {
            // 单次 -> 循环
            if activeLooper == nil {
                print("SeamlessPlayer: Enabling looping for \(currentVideoName ?? "unknown")")
                removeFinishObserver()
                // 确保 Looper 可以工作
                player.actionAtItemEnd = .advance
                activeLooper = AVPlayerLooper(player: player, templateItem: currentItem)
                player.play()
            }
        } else {
            // 循环 -> 单次
            if let looper = activeLooper {
                print("SeamlessPlayer: Disabling looping for \(currentVideoName ?? "unknown")")
                looper.disableLooping()
                activeLooper = nil
                
                // [修复] 清理队列中所有非当前的 item，防止播放 Looper 遗留的副本
                // AVQueuePlayer 只能通过 removeAllItems 清理所有，或者 advanceToNextItem 跳过
                // 既然我们要保留 currentItem，且 AVQueuePlayer 没有 remove(item) API (除了当前)
                // 我们只能依赖 actionAtItemEnd = .pause 来停止播放。
                // 如果队列里有后续 item，actionAtItemEnd = .pause 会在当前 item 播完后暂停，这符合预期。
                // 但如果 actionAtItemEnd = .advance (默认)，它就会播下一个。
                
                // 关键：切换回单次播放时，必须设置 actionAtItemEnd 为 pause
                player.actionAtItemEnd = .pause
                
                // 关键修复：在添加监听前，先检查是否已经播完
                // 如果在 disableLooping 的瞬间刚好播完，AVPlayer 可能已经停止，且不会再触发 Notification
                let currentTime = currentItem.currentTime().seconds
                let duration = currentItem.duration.seconds
                
                // 如果剩余时间极短 (< 0.1s) 或者已经结束，直接触发完成
                // [优化] 对于短视频，放宽判定标准，避免刚开始就判结束
                // 如果 currentTime 非常接近 0 (刚开始播)，不要判结束。
                if duration > 0 && currentTime >= duration - 0.1 && currentTime > 0.1 {
                     print("SeamlessPlayer: Video already near end (\(currentTime)/\(duration)), triggering finish manually")
                     self.onFinished?()
                } else {
                     // 正常添加结束监听
                     setupFinishObserver(for: currentItem, isLooping: false)
                }
            }
        }
    }
    
    private func setupTimeObserver(for player: AVQueuePlayer) {
        // 每 0.1 秒更新一次进度
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let item = player.currentItem else { return }
            let duration = item.duration.seconds
            let current = time.seconds
            
            if duration > 0 {
                self.onProgress?(current, duration)
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
        if let timeObserver = timeObserver {
            activePlayer?.removeTimeObserver(timeObserver)
        }
    }
}

// MARK: - SwiftUI Wrapper

struct SeamlessVideoPlayer: UIViewRepresentable {
    var videoName: String
    var isLooping: Bool
    var isMuted: Bool
    var volume: Float
    var onFinished: (() -> Void)?
    var onProgress: ((Double, Double) -> Void)? = nil
    
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
            onFinished: onFinished,
            onProgress: onProgress
        )
    }
}
