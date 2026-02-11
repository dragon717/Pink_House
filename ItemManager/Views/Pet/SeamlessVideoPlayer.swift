import SwiftUI
import UIKit
import AVFoundation
import Combine
import CoreVideo

/// 一个支持无缝切换的双缓冲视频播放器视图 (UIView)
class SeamlessVideoPlayerView: UIView {
    // 双播放器系统
    private var playerLayerA: AVPlayerLayer = AVPlayerLayer()
    private var playerLayerB: AVPlayerLayer = AVPlayerLayer()
    
    // 移除长期持有的 playerA/B，改为动态创建
    // private var playerA: AVQueuePlayer = AVQueuePlayer()
    // private var playerB: AVQueuePlayer = AVQueuePlayer()
    
    // 状态追踪
    private var activeLayer: AVPlayerLayer?
    private var activePlayer: AVQueuePlayer?
    // private var activeLooper: AVPlayerLooper? // 彻底移除 Looper
    private var currentLoadingID: UUID? // 增加 Loading ID 防止 Race Condition
    private var activeLoadingID: UUID? // 当前正在播放的 Loading ID

    
    // 当前配置
    private var currentVideoName: String?
    private var currentVideoURL: URL?
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
    private var backgroundObserver: Any?
    private var foregroundObserver: Any?
    
    private var isAppActive: Bool = true
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupWatchdog()
        setupAppLifecycleObservers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupWatchdog()
        setupAppLifecycleObservers()
    }
    
    private func setupAppLifecycleObservers() {
        let nc = NotificationCenter.default
        backgroundObserver = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppBackground()
        }
        foregroundObserver = nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppForeground()
        }
    }
    
    private func handleAppBackground() {
        print("SeamlessPlayer: App entered background, pausing playback and watchdog")
        isAppActive = false
        activePlayer?.pause()
        // Stop watchdog timer to save energy
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
    
    private func handleAppForeground() {
        print("SeamlessPlayer: App entered foreground, resuming watchdog")
        isAppActive = true
        // Restart watchdog
        setupWatchdog()
        // 立即检查一次
        checkPlaybackStatus()
    }
    
    private func setupWatchdog() {
        // 每 2 秒检查一次播放状态 (保底逻辑)
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPlaybackStatus()
        }
    }
    
    private func checkPlaybackStatus() {
        // 如果应用在后台，直接跳过检查，避免触发 err=-19431 (FigApplicationStateMonitor)
        guard isAppActive else { return }
        
        // 如果正在加载新视频 (currentLoadingID != activeLoadingID)，则跳过完成检查
        // 避免在切换过程中旧视频触发 Watchdog
        if currentLoadingID != activeLoadingID {
             // print("SeamlessPlayer Watchdog: Skipping check during transition")
             return 
        }
        
        guard let player = activePlayer else { return }
        
        // 0. 检查是否出错
        if player.status == .failed || player.currentItem?.status == .failed {
            print("SeamlessPlayer Watchdog: Player or Item failed. Error: \(String(describing: player.error ?? player.currentItem?.error)). Reloading.")
            if let name = currentVideoName {
                loadAndSwitch(to: name, url: currentVideoURL, looping: isLooping)
            }
            return
        }
        
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
                 loadAndSwitch(to: name, url: currentVideoURL, looping: isLooping)
             }
        }
    }
    
    private func setupLayers() {
        // 配置 Layer A
        // playerLayerA.player = playerA // 初始不绑定
        playerLayerA.videoGravity = .resizeAspectFill
        // 这里的 pixelFormatType 设置是不必要的，甚至是有害的。
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange (NV12) 不支持 Alpha 通道。
        // AVPlayerLayer 会自动识别 HEVC with Alpha 视频并使用正确的格式。
        playerLayerA.backgroundColor = UIColor.clear.cgColor
        playerLayerA.frame = bounds
        playerLayerA.opacity = 0 // 初始隐藏
        layer.addSublayer(playerLayerA)
        
        // 配置 Layer B
        // playerLayerB.player = playerB // 初始不绑定
        playerLayerB.videoGravity = .resizeAspectFill
        // 同上，移除显式的像素格式指定，让系统自动处理 Alpha
        playerLayerB.backgroundColor = UIColor.clear.cgColor
        playerLayerB.frame = bounds
        playerLayerB.opacity = 0 // 初始隐藏
        layer.addSublayer(playerLayerB)
        
        // 初始激活 A (虽然还没播放)
        activeLayer = playerLayerA
        // activePlayer = playerA // 初始没有 Player
        activePlayer = nil
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
        let newURL = findVideoURL(name: videoName)
        var shouldReload = false
        
        if self.currentVideoName != videoName {
            // 名字不同，检查 URL 是否也不同
            if let currentURL = self.currentVideoURL, let new = newURL, currentURL == new {
                print("SeamlessPlayer: Video name changed but URL is same. Ignoring reload. (\(videoName))")
                self.currentVideoName = videoName
                shouldReload = false
            } else {
                shouldReload = true
            }
        } else {
            shouldReload = false
        }
        
        if shouldReload {
            print("SeamlessPlayer: Switching video to \(videoName)")
            self.currentVideoName = videoName
            self.currentVideoURL = newURL
            self.isLooping = isLooping // 记录新视频的循环状态
            loadAndSwitch(to: videoName, url: newURL, looping: isLooping)
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
        // playerA.isMuted = isMuted
        // playerA.volume = volume
        // playerB.isMuted = isMuted
        // playerB.volume = volume
        activePlayer?.isMuted = isMuted
        activePlayer?.volume = volume
    }
    
    private func createPlayer() -> AVQueuePlayer {
        let player = AVQueuePlayer()
        player.isMuted = isMuted
        player.volume = volume
        return player
    }
    
    private func loadAndSwitch(to videoName: String, url: URL?, looping: Bool) {
        guard let url = url ?? findVideoURL(name: videoName) else {
            print("SeamlessPlayer: Failed to find video \(videoName)")
            return
        }
        
        // 防止旧视频在加载新视频期间触发结束回调，导致状态错乱
        removeFinishObserver()
        
        self.currentVideoURL = url
        
        // 生成新的 Loading ID
        let loadingID = UUID()
        self.currentLoadingID = loadingID
        
        // 确定下一个使用的播放器 (如果当前是 A，下一个用 B，反之亦然)
        let nextPlayer: AVQueuePlayer
        let nextLayer: AVPlayerLayer
        
        // 这里的判断逻辑需要修改，因为 activePlayer 不再是固定的 playerA/B
        if activeLayer === playerLayerA {
            nextLayer = playerLayerB
        } else {
            nextLayer = playerLayerA
        }
        
        // 关键重构：每次创建新的 Player，避免复用导致的状态污染 (err -12860)
        nextPlayer = createPlayer()
        nextLayer.player = nextPlayer
        
        // 准备 Item
        let item = AVPlayerItem(url: url)
        
        // 只有在非循环模式下才设置 actionAtItemEnd = .none (让它停在最后一帧，避免黑屏)
        // 但我们在循环模式下也希望手动 seek，所以统一设置为 .none
        nextPlayer.actionAtItemEnd = .none 
        
        nextPlayer.replaceCurrentItem(with: item)
        
        // 监听 ReadyForDisplay
        // KVO 监听 layer 的 isReadyForDisplay 是最准确的
        // 但 AVPlayerLayer.isReadyForDisplay 只有在关联了 player 且 player 有内容时才变 true
        
        // 我们使用一个临时对象来捕获本次切换的上下文
        let transitionContext = TransitionContext(
            player: nextPlayer,
            layer: nextLayer,
            item: item,
            isLooping: looping,
            loadingID: loadingID
        )
        
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
            // 只有当这是我们需要的目标播放器且 ID 匹配时才切换 (防止旧的监听回调)
            if layer.isReadyForDisplay && self.currentLoadingID == loadingID {
                if layer === nextLayer {
                    DispatchQueue.main.async {
                        // Double check ID on main thread
                        if self.currentLoadingID == loadingID {
                            self.performSwitch(context: transitionContext)
                        }
                    }
                }
            }
        }
        
        // 设置超时保护：如果 0.5 秒还没 ready，强制切换（避免永远不切）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // 如果 activeLayer 还是旧的，且 nextPlayer 正在播放，且 ID 匹配，强制切
            if self.activeLayer !== nextLayer && nextPlayer.timeControlStatus == .playing && self.currentLoadingID == loadingID {
                self.performSwitch(context: transitionContext)
            }
        }
    }
    
    private struct TransitionContext {
        let player: AVQueuePlayer
        let layer: AVPlayerLayer
        let item: AVPlayerItem
        let isLooping: Bool
        let loadingID: UUID
        // var looper: AVPlayerLooper? // 移除
    }
    
    private func performSwitch(context: TransitionContext) {
        // Double check ID
        guard currentLoadingID == context.loadingID else {
             print("SeamlessPlayer: Ignoring outdated switch context")
             return
        }
        guard activeLayer !== context.layer else { return } // 已经切过了
        
        print("SeamlessPlayer: Performing switch")
        
        // 0. 确保新 Layer 在最上层
        context.layer.zPosition = 10
        if let old = activeLayer {
            old.zPosition = 0
        }
        
        // 1. 显示新 Layer
        context.layer.opacity = 1
        
        // 记录旧 Layer 和 Player
        let oldLayer = activeLayer
        let oldPlayer = activePlayer
        // let oldLooper = activeLooper // 记录旧 Looper
        
        // 2. 立即静音旧视频 (如果存在)
        // 这样可以实现声音的立即切换，避免混音
        oldPlayer?.volume = 0
        oldPlayer?.isMuted = true
        
        // 移除旧的时间监听
        if let timeObserver = timeObserver {
            oldPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // 关键：禁用旧的 Looper
        // 虽然我们会销毁 Player，但明确 disable 是个好习惯
        // oldLooper?.disableLooping() 
        // 实际上，为了避免 err=-12860，我们应该避免调用 disableLooping，
        // 而是让 Player 销毁时自然清理。这里不做操作。
        
        // 3. 更新状态 (立即更新 active 指针，这样后续的逻辑都知道谁是新的)
        activeLayer = context.layer
        activePlayer = context.player
        activeLoadingID = context.loadingID

        
        // 处理 Race Condition: 检查当前的 isLooping 是否与 context.isLooping 一致
        // 如果在加载过程中用户改变了循环状态（例如快速松手），这里需要修正
        if self.isLooping != context.isLooping {
            print("SeamlessPlayer: Loop state mismatch in switch (Context: \(context.isLooping), Current: \(self.isLooping))")
            
            // 只需要更新状态，setupFinishObserver 会根据 self.isLooping 自动处理
            // 因为 context.item 就是当前播放的 item
            
            // 如果变成了循环 (self.isLooping = true)
            // setupFinishObserver 会添加 loop 逻辑
            
            // 如果变成了单次 (self.isLooping = false)
            // setupFinishObserver 会添加 finish 逻辑
            
            setupFinishObserver(for: context.item, isLooping: self.isLooping)
        } else {
            // 正常情况
            // activeLooper = context.looper
            setupFinishObserver(for: context.item, isLooping: context.isLooping)
        }
        
        // 4. 清理观察者
        statusObserver?.invalidate()
        statusObserver = nil
        
        // 6. 设置进度监听
        setupTimeObserver(for: context.player)
        
        // 延迟关闭旧视频 (修改为 300ms)
        if let layerToHide = oldLayer, let playerToStop = oldPlayer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                
                // 关键检查：确保要隐藏的 Layer 确实不再是 activeLayer
                // 如果在 300ms 内又切回去了，那么 activeLayer 就会等于 layerToHide，此时不应该隐藏
                if self.activeLayer !== layerToHide {
                    // 使用 CoreAnimation 事务
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layerToHide.opacity = 0
                    layerToHide.player = nil // 断开连接，加速释放
                    CATransaction.commit()
                    
                    playerToStop.pause()
                    // playerToStop.removeAllItems() // 避免操作队列
                    
                    // 恢复音量 (虽然 removeAllItems 已经清理了，但重置状态是个好习惯，
                    // 实际上下次 updateVolumeAndMute 会处理，这里可以省略，或者为了保险重置一下)
                    // playerToStop.volume = self.volume
                    // playerToStop.isMuted = self.isMuted
                }
            }
        }
    }
    
    private func updateLoopingState(isLooping: Bool) {
        guard let player = activePlayer, let currentItem = player.currentItem else { return }
        
        // 无论是开启循环还是关闭循环，我们都只需要更新 FinishObserver 的行为
        // 因为我们现在使用手动 Seek 来实现循环
        
        setupFinishObserver(for: currentItem, isLooping: isLooping)
        
        if isLooping {
            print("SeamlessPlayer: Loop enabled (Manual Seek)")
        } else {
             print("SeamlessPlayer: Loop disabled (Manual Seek)")
             
             // 检查是否已经播完
             let currentTime = currentItem.currentTime().seconds
             let duration = currentItem.duration.seconds
             
             // 如果剩余时间极短 (< 0.1s) 或者已经结束，直接触发完成
             if duration > 0 && currentTime >= duration - 0.1 {
                  print("SeamlessPlayer: Video already near end, triggering finish manually")
                  player.pause()
                  DispatchQueue.main.async { [weak self] in
                      self?.onFinished?()
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
        
        // 无论是否 Looping，我们都监听 .AVPlayerItemDidPlayToEndTime
        finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            // 每次回调时，检查当前的 isLooping 状态
            // (注意：这里的 isLooping 参数仅用于初始设置逻辑，实际判断应基于 self.isLooping)
            // 但为了逻辑清晰，我们假设外部调用者已经同步了状态。
            // 更稳妥的做法是直接读取 self.isLooping
            
            if self.isLooping {
                print("SeamlessPlayer: Loop triggered (Manual Seek)")
                // 手动循环
                self.activePlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                self.activePlayer?.play()
            } else {
                print("SeamlessPlayer: Finished playing (End)")
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
        
        // 2. Bundle 根目录查找
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            return url
        }
        
        // 3. asserts 子目录查找 (使用 subdirectory 参数)
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "asserts") {
            return url
        }
        
        // 4. asserts 子目录查找 (旧方式兼容)
        if let url = Bundle.main.url(forResource: "asserts/\(name)", withExtension: "mp4") {
            return url
        }
        
        // 5. 无后缀尝试 (Bundle 根目录)
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        
        // 6. 无后缀尝试 (asserts 子目录)
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "asserts") {
            return url
        }

        // 7. Fallback logic
        print("SeamlessPlayer: Failed to find video '\(name)'. Trying fallbacks.")
        
        // Try prefix fallback (e.g. maomao_eating -> maomao_idle)
        if let underscoreIndex = name.firstIndex(of: "_") {
            let prefix = name.prefix(upTo: underscoreIndex)
            let fallbackName = "\(prefix)_idle"
            if fallbackName != name, let url = Bundle.main.url(forResource: fallbackName, withExtension: "mp4", subdirectory: "asserts") {
                return url
            }
        }
        
        // Try naicha_idle (Default)
        if let url = Bundle.main.url(forResource: "naicha_idle", withExtension: "mp4", subdirectory: "asserts") {
             return url
        }
        
        // Fallback to legacy idle
        return Bundle.main.url(forResource: "idle", withExtension: "mp4") ?? 
               Bundle.main.url(forResource: "idle", withExtension: "mp4", subdirectory: "asserts") ??
               Bundle.main.url(forResource: "asserts/idle", withExtension: "mp4")
    }
    
    deinit {
        statusObserver?.invalidate()
        removeFinishObserver()
        if let timeObserver = timeObserver {
            activePlayer?.removeTimeObserver(timeObserver)
        }
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        watchdogTimer?.invalidate()
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
