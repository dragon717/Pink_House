import AVFoundation
import Combine
import Speech
import UIKit
import SoundAnalysis

/// 萌宠互动状态
enum PetInteractionState: String {
    case idle           // 空闲
    case preparing      // 准备中 (新增)
    case listening      // 正在监听（等待人声）
    case recording      // 正在录音（人声输入中）
    case processing     // 处理中（录音结束，准备播放）
    case playing        // 播放中（变音复述）
}

/// 萌宠音色类型
enum PetVoiceType: String, CaseIterable, Identifiable {
    case funny = "funny"       // 搞怪变声
    case youngBoy = "youngBoy" // 正太音
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .funny: return "搞怪变声"
        case .youngBoy: return "正太音"
        }
    }
}

/// 总的萌宠声音管理器
/// 负责控制背景音乐、麦克风监听、语音识别和回声模式
@MainActor
final class AudioManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate, SNResultsObserving {
    static let shared = AudioManager()
    
    // MARK: - Published Properties
    
    /// BGM 音量 (0.0 - 1.0)
    @Published var bgmVolume: Double {
        didSet {
            UserDefaults.standard.set(bgmVolume, forKey: "bgmVolume")
            bgmPlayerNode.volume = Float(bgmVolume)
        }
    }
    
    // MARK: - Audio Route Detection
    
    private func isHeadphonesConnected() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.contains { desc in
            // 检查常见的耳机类型
            return desc.portType == .headphones ||
                   desc.portType == .bluetoothA2DP ||
                   desc.portType == .bluetoothHFP ||
                   desc.portType == .bluetoothLE
        }
    }

    /// 萌宠语音音量 (0.0 - 1.0)
    @Published var petVoiceVolume: Double {
        didSet {
            UserDefaults.standard.set(petVoiceVolume, forKey: "petVoiceVolume")
            updatePlayerVolume()
        }
    }
    
    /// 是否在连接耳机时强制使用 iPhone 麦克风
    @Published var useiPhoneMicWithHeadphones: Bool {
        didSet {
            UserDefaults.standard.set(useiPhoneMicWithHeadphones, forKey: "useiPhoneMicWithHeadphones")
            // 如果正在互动中，需要重新配置音频会话以应用更改
            if isInteractionEnabled {
                setupAudioSession(isRecording: true)
            }
        }
    }
    
    private func updatePlayerVolume() {
        // 根据是否连接耳机动态调整增益
        // 耳机通常更贴耳，不需要像扬声器那样激进的增益 (4.0 -> 1.5)
        // 扬声器因为距离和硬件限制，需要更高的增益 (4.0)
        let isHeadphones = isHeadphonesConnected()
        let gain: Float = isHeadphones ? 1.5 : 4.0
        
        // 确保在主线程更新
        if Thread.isMainThread {
            playerNode.volume = Float(petVoiceVolume) * gain
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.playerNode.volume = Float(self.petVoiceVolume) * gain
            }
        }
        
        // print("AudioManager: Updated volume with gain: \(gain) (Headphones: \(isHeadphones))")
    }
    
    /// 萌宠音色选择
    @Published var selectedVoiceType: PetVoiceType {
        didSet {
            UserDefaults.standard.set(selectedVoiceType.rawValue, forKey: "petVoiceType")
        }
    }
    
    /// 背景音乐开关
    @Published var isBackgroundMusicEnabled: Bool = false {
        didSet {
            if isBackgroundMusicEnabled {
                playBackgroundMusic()
            } else {
                stopBackgroundMusic()
            }
        }
    }
    
    /// 互动模式开关（原变音开关）
    /// 开启后，进入 Echo 模式：监听 -> 录音 -> 识别 -> 变音播放
    @Published var isInteractionEnabled: Bool = false {
        didSet {
            if isInteractionEnabled {
                startInteraction()
            } else {
                stopInteraction()
            }
        }
    }
    
    /// 当前互动状态
    @Published var interactionState: PetInteractionState = .idle {
        didSet {
            // 更新非隔离标志供音频线程读取，避免访问 MainActor 属性
            _isRecording = (interactionState == .recording)
            _isListening = (interactionState == .listening)
        }
    }
    
    // 供音频线程读取的标志 (简单 Bool，忽略严格并发检查以保持最简)
    private var _isRecording: Bool = false
    private var _isListening: Bool = false
    
    // Ring Buffer for Pre-recording (修复吞字问题)
    private var preRecordBuffer: [AVAudioPCMBuffer] = []
    private let maxPreRecordBuffers = 20 // 约 400-500ms
    
    /// 语音识别的文字
    @Published var recognizedText: String = ""
    
    // MARK: - Private Properties
    
    private var bgmPlayerNode = AVAudioPlayerNode()
    private var bgmBuffer: AVAudioPCMBuffer?
    
    // Audio Engine & Nodes
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitch = AVAudioUnitTimePitch()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 4) // 增加到4个频段以进行更精细的控制
    private var mixerNode = AVAudioMixerNode() // 用于将输入写入文件
    
    // VAD (Voice Activity Detection)
    private var silenceTimer: Timer?
    // 提高静音阈值以过滤远处声音 (原 -40.0) -> 现在的需求是轻声说话也能识别，调低阈值
    // -25.0 dB -> -45.0 dB (更灵敏)
    private let silenceThreshold: Float = -45.0 // dB
    private let silenceDuration: TimeInterval = 0.6 // 持续静音多久视为结束 (原 1.2 -> 0.6 提升响应速度)
    private var isSpeechDetected = false
    private var analysisThrottleCounter: Int = 0 // 用于限制 SoundAnalysis 的频率，节省 CPU
    
    // Audio Processing Queue (Serial) - Removed in simplified version
    // private let audioProcessingQueue = DispatchQueue(label: "com.pinkhouse.AudioProcessingQueue", qos: .userInteractive)
    // private let audioSessionQueue = DispatchQueue(label: "com.pinkhouse.AudioSessionQueue", qos: .userInitiated)

    // Sound Analysis (Moved below to keep properties grouped)
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var isHumanSpeech = false
    
    // Recording
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    // Speech Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) // 默认中文，可配置
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private override init() {
        self.bgmVolume = UserDefaults.standard.object(forKey: "bgmVolume") as? Double ?? 0.3
        self.petVoiceVolume = UserDefaults.standard.object(forKey: "petVoiceVolume") as? Double ?? 1.0
        self.useiPhoneMicWithHeadphones = UserDefaults.standard.bool(forKey: "useiPhoneMicWithHeadphones")
        
        // 默认使用正太音
        if let savedType = UserDefaults.standard.string(forKey: "petVoiceType"),
           let type = PetVoiceType(rawValue: savedType) {
            self.selectedVoiceType = type
        } else {
            self.selectedVoiceType = .youngBoy
        }
        
        super.init()
        speechRecognizer?.delegate = self
        setupRecordingURL()
        setupNotifications()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(bgmPlayerNode)
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eqNode)
        
        // Connect BGM directly to main mixer
        engine.connect(bgmPlayerNode, to: engine.mainMixerNode, format: nil)
        
        // Connect Voice Effects Chain
        // Player -> TimePitch -> EQ -> MainMixer
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        
        // Prepare BGM Buffer
        prepareBGMBuffer()
    }
    
    private func prepareBGMBuffer() {
        let bgmNames = ["pet_bgm", "bgm", "background_music", "music"]
        var url: URL?
        
        for name in bgmNames {
            // 1. 尝试直接查找 (Root)
            if let u = Bundle.main.url(forResource: name, withExtension: "mp3") ?? Bundle.main.url(forResource: name, withExtension: "wav") {
                url = u
                break
            }
            // 2. 尝试在 asserts 子目录查找
            if let u = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "asserts") ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "asserts") {
                url = u
                break
            }
            // 3. 尝试手动拼接路径
            if let u = Bundle.main.url(forResource: "asserts/\(name)", withExtension: "mp3") ?? Bundle.main.url(forResource: "asserts/\(name)", withExtension: "wav") {
                url = u
                break
            }
            // 4. 尝试 ItemManager/asserts (以防万一)
            if let u = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "ItemManager/asserts") ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "ItemManager/asserts") {
                url = u
                break
            }
        }
        
        guard let validUrl = url else {
            print("AudioManager: No BGM found.")
            return
        }
        
        do {
            let file = try AVAudioFile(forReading: validUrl)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
            try file.read(into: buffer!)
            self.bgmBuffer = buffer
        } catch {
            print("AudioManager: Failed to load BGM file: \(error)")
        }
    }
    
    private func setupRecordingURL() {
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("pet_echo_recording.wav")
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleAppDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleAppWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        // 监听音频路由变化
        nc.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // 忽略 CategoryChange，因为这通常是我们自己调用 setCategory 触发的，处理它会导致死循环
        if reason == .categoryChange {
            return
        }
        
        print("AudioManager: Route changed, reason: \(reason)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 路由变化时，重新应用音量设置
            self.updatePlayerVolume()
            
            // 如果开启了互动，并且需要强制使用手机麦克风，则重新应用设置
            if self.isInteractionEnabled && self.useiPhoneMicWithHeadphones {
                // 只有当原因是新设备连接或旧设备断开时，才积极重置 AudioSession
                // 避免在其他无关路由变化时频繁重置
                if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                    self.setupAudioSession(isRecording: true)
                }
            }
        }
        
        // 如果是新设备接入（例如连接了蓝牙耳机），可能需要检查是否需要重启互动以适应新的采样率或I/O
        // 这里暂时只处理音量适配
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("AudioManager: App entered background")
        // 进入后台时，暂停所有音频活动
        if isInteractionEnabled {
            // 停止引擎和录音，但不改变 isInteractionEnabled 开关状态
            stopInteraction()
        }
        stopBackgroundMusic()
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("AudioManager: App will enter foreground")
        // 回到前台时，根据开关状态恢复
        if isInteractionEnabled {
            startInteraction()
        }
        if isBackgroundMusicEnabled {
            playBackgroundMusic()
        }
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .began {
            print("AudioManager: Interruption began")
            stopInteraction()
            stopBackgroundMusic()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("AudioManager: Interruption ended, resuming")
                    if isInteractionEnabled {
                        startInteraction()
                    }
                    if isBackgroundMusicEnabled {
                        playBackgroundMusic()
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession(isRecording: Bool = false) {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 检查当前 Category 和 Mode 是否已经正确，避免重复设置
            // 注意：AVAudioSession 的属性读取也可能有开销，但通常比 set 便宜
            let currentCategory = session.category
            let currentMode = session.mode
            
            if isInteractionEnabled {
                // 目标: PlayAndRecord, VoiceChat
                if currentCategory != .playAndRecord || currentMode != .voiceChat {
                    // 互动模式下始终保持 playAndRecord，避免切换开销和 I/O 错误
                    // 使用 .voiceChat 模式以启用回声消除 (AEC)，防止 BGM 触发 VAD
                    // 添加 .allowBluetoothA2DP 以支持更广泛的蓝牙设备
                    // 关键修正：移除 overrideOutputAudioPort(.speaker)，否则会导致蓝牙耳机失效
                    // .defaultToSpeaker 选项足以保证在没有耳机时使用扬声器，有耳机时自动切换
                    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
                }
                
                // 强制使用 iPhone 麦克风逻辑
                if useiPhoneMicWithHeadphones {
                    // 检查当前是否已经是内置麦克风，如果是，跳过设置
                    let currentInput = session.currentRoute.inputs.first
                    if currentInput?.portType != .builtInMic {
                        // 查找内置麦克风
                        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                            try session.setPreferredInput(builtInMic)
                            print("AudioManager: [Setup] Forced input to Built-In Mic")
                        } else {
                            // print("AudioManager: [Setup] Built-In Mic not found in availableInputs: \(session.availableInputs?.map { $0.portType } ?? [])")
                        }
                    }
                } else {
                    // 清除首选输入（允许系统自动选择，如耳机麦克风）
                    // 只有当当前有首选输入时才清除
                    if session.preferredInput != nil {
                        try session.setPreferredInput(nil)
                    }
                }
            } else if isRecording {
                if currentCategory != .playAndRecord || currentMode != .default {
                    // 仅录音（虽然目前逻辑不会走到这里，除非有其他录音需求）
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                }
            } else {
                if currentCategory != .playback || currentMode != .default {
                    // 普通播放模式（背景音乐）
                    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                }
            }
            
            // 只有在未激活时才激活，避免中断
            // 注意：某些配置更改需要重新激活才能生效，但简单的 route 切换通常不需要
            // 这里为了稳妥，保持 setActive，但可以考虑优化
             try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 再次检查并强制设置 Input (有些情况下 Active 后会被系统重置)
            if isInteractionEnabled && useiPhoneMicWithHeadphones {
                if let currentInput = session.currentRoute.inputs.first {
                    // print("AudioManager: [Check] Current Input after activation: \(currentInput.portType)")
                    if currentInput.portType != .builtInMic {
                        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                            try session.setPreferredInput(builtInMic)
                            // print("AudioManager: [Retry] Re-forcing input to Built-In Mic after activation")
                        }
                    }
                }
            }
        } catch {
            print("AudioManager: Failed to set audio session: \(error)")
        }
    }
    
    // MARK: - Background Music
    
    private func playBackgroundMusic() {
        // 如果正在互动，session 已经由互动逻辑管理，无需切换
        if !isInteractionEnabled {
            setupAudioSession(isRecording: false)
        }
        
        // 确保引擎正在运行
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("AudioManager: Failed to start engine for BGM: \(error)")
                return
            }
        }
        
        guard let buffer = bgmBuffer else {
            print("AudioManager: No BGM buffer available")
            return
        }
        
        if !bgmPlayerNode.isPlaying {
            bgmPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            bgmPlayerNode.play()
        }
        
        // 如果处于倾听状态，静音播放
        if interactionState == .listening || interactionState == .recording {
            bgmPlayerNode.volume = 0
        } else {
            bgmPlayerNode.volume = Float(bgmVolume)
        }
    }
    
    private func stopBackgroundMusic() {
        bgmPlayerNode.stop()
    }
    
    // MARK: - Interaction Control
    
    private func startInteraction() {
        guard interactionState == .idle else { return }
        
        interactionState = .preparing
        
        // 检查权限
        checkPermissions { [weak self] authorized in
            guard let self = self else { return }
            if authorized {
                DispatchQueue.main.async {
                    self.startListening()
                }
            } else {
                DispatchQueue.main.async {
                    self.isInteractionEnabled = false
                    print("AudioManager: Permissions denied")
                }
            }
        }
    }
    
    private func stopInteraction() {
        stopListening()
        stopPlayback()
        interactionState = .idle
        
        // 互动结束，恢复 BGM
        if isBackgroundMusicEnabled {
            // 使用 fade 效果恢复音量
            // AVAudioPlayerNode 不支持内置 fade，这里简单设置
            // 如果需要 fade，可以使用 timer 或 SCNAudioPlayer (如果是 SceneKit)
            // 这里为了简单直接设置
            bgmPlayerNode.volume = Float(bgmVolume)
        }
    }
    
    private func checkPermissions(completion: @escaping (Bool) -> Void) {
        var micAuthorized = false
        var speechAuthorized = false
        
        let group = DispatchGroup()
        
        // Mic
        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            micAuthorized = granted
            group.leave()
        }
        
        // Speech
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechAuthorized = (status == .authorized)
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(micAuthorized && speechAuthorized)
        }
    }
    
    // MARK: - Listening & Recording Logic
    
    private func startListening() {
        stopPlayback() // 确保没有在播放
        
        // 倾听时，暂时将 BGM 静音
        if isBackgroundMusicEnabled {
            bgmPlayerNode.volume = 0
        }
        
        // 重置 Ring Buffer
        preRecordBuffer.removeAll()
        
        // 简易版：直接在主线程配置 AudioSession 和 Engine
        setupAudioSession(isRecording: true)
        
        // 关键：Session 配置改变后，重置 Engine 以刷新硬件格式
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        
        // 移除旧的 Tap
        engine.inputNode.removeTap(onBus: 0)
        
        let inputNode = engine.inputNode
        // 使用 outputFormat 而不是 inputFormat，因为这是 InputNode 输出给 Tap 的数据格式
        let format = inputNode.outputFormat(forBus: 0)
        
        // 打印调试信息，确认采样率
        print("AudioManager: Input format: \(format)")
        
        if format.sampleRate == 0 || format.channelCount == 0 {
            print("AudioManager: Invalid input format: \(format)")
            isInteractionEnabled = false // 关闭开关
            stopInteraction()
            return
        }
        
        prepareSpeechRecognition()
        
        // Sound Analysis
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try streamAnalyzer?.add(request, withObserver: self)
        } catch {
            print("AudioManager: Failed to create Sound Analysis request: \(error)")
        }
        
        // 准备写入文件
        do {
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
                audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            }
        } catch {
            print("AudioManager: Failed to create audio file: \(error)")
        }
        
        // 安装 Tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // 简单处理：直接写文件和分析，不进行复杂的异步拷贝
            // 注意：这可能会在低端设备上引起一点爆音，但逻辑最简单
            
            // 1. Sound Analysis (Throttled)
            self.analysisThrottleCounter += 1
            if self.analysisThrottleCounter % 6 == 0 {
                // 使用 autoreleasepool 优化内存
                autoreleasepool {
                    self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
            
            // 2. Ring Buffer Management
            // 始终维护最近的 buffer，用于回溯
            self.preRecordBuffer.append(buffer)
            if self.preRecordBuffer.count > self.maxPreRecordBuffers {
                self.preRecordBuffer.removeFirst()
            }
            
            // 3. 写入文件 & 语音识别
            if self._isRecording {
                autoreleasepool {
                    // 如果 Ring Buffer 中有积压的数据（说明刚开始录音），先全部写入
                    if !self.preRecordBuffer.isEmpty {
                        for oldBuffer in self.preRecordBuffer {
                            try? self.audioFile?.write(from: oldBuffer)
                            self.recognitionRequest?.append(oldBuffer)
                        }
                        // 写入后清空，避免重复写入
                        self.preRecordBuffer.removeAll()
                    }
                    
                    // 注意：由于上面已经把 current buffer (刚刚 append 进去的) 也写进去了，
                    // 所以这里不需要再单独写 buffer。
                    // 只要 preRecordBuffer.removeAll() 执行了，下一次回调进来时，
                    // preRecordBuffer 会是空的（然后 append 1 个），然后进入这个 block 写这 1 个。
                    // 逻辑是自洽的。
                }
            }
            
            // 4. VAD 检测 (主线程去抖动)
            self.processVAD(buffer: buffer)
        }
        
        do {
            if !engine.isRunning {
                try engine.start()
            }
            // 恢复 BGM
            if isBackgroundMusicEnabled && !bgmPlayerNode.isPlaying {
                if let buffer = bgmBuffer {
                    bgmPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                    bgmPlayerNode.play()
                }
            }
            
            interactionState = .listening
            recognizedText = ""
            print("AudioManager: Started listening...")
        } catch {
            print("AudioManager: Failed to start engine: \(error)")
            isInteractionEnabled = false // 关闭开关
            stopInteraction()
        }
    }
    
    // 简易版 VAD 处理
    private func processVAD(buffer: AVAudioPCMBuffer) {
        // 计算音量
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        let stride = buffer.stride
        
        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelDataValue[i * stride]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(rms)
        
        // 只有当状态真正改变时才去主线程
        // 使用简单的阈值判断
        let isLoud = db > silenceThreshold
        let isVoice = isLoud && (isHumanSpeech || db > -35.0)
        
        // 优化：使用本地标志判断，减少主线程调度
        if !_isListening && !_isRecording {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.interactionState == .listening {
                if isVoice {
                    self.onSpeechDetected()
                }
            } else if self.interactionState == .recording {
                if !isVoice {
                    self.onSilenceDetected() // 内部有 timer 防抖
                } else {
                    self.onSpeechDetected() // 重置 timer
                }
            }
        }
    }
    
    private func stopListening() {
        // 不要完全 stop engine，因为可能还需要播放 BGM
        // engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
        // 结束 Sound Analysis
        streamAnalyzer = nil
        isHumanSpeech = false
        
        // 结束语音识别
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // 关闭文件
        audioFile = nil
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        print("AudioManager: Stopped listening")
    }
    
    // MARK: - SNResultsObserving
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        
        // 获取置信度最高的分类
        guard let classification = result.classifications.first else { return }
        
        // 只有 Speech 且置信度较高时才认为是人声
        // 过滤掉 music, noise, laughter 等
        // 降低置信度阈值以支持轻声说话 (0.85 -> 0.5)
        let isSpeech = classification.identifier == "speech" && classification.confidence > 0.5
        
        // 在主线程更新状态（或者使用原子属性）
        DispatchQueue.main.async {
            // 这里我们更新一个属性供 VAD 使用
            // 注意：这可能有点频繁，但考虑到我们只是设置一个 Bool，应该还好
            // 也可以加个防抖
            AudioManager.shared.updateSpeechStatus(isSpeech)
        }
    }
    
    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        print("AudioManager: Sound analysis failed: \(error)")
    }
    
    private func updateSpeechStatus(_ isSpeech: Bool) {
        self.isHumanSpeech = isSpeech
    }
    
    // 状态缓存，用于减少不必要的主线程调度
    // private var lastReportedSpeechState: Bool = false
    
    // Voice Activity Detection - Removed dead logic in simplified version
    
    private func onSpeechDetected() {
        // 取消静音计时器
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if interactionState == .listening {
            // 开始录音
            interactionState = .recording
            isSpeechDetected = true
            print("AudioManager: Speech detected, started recording")
        }
    }
    
    private func onSilenceDetected() {
        if interactionState == .recording {
            if silenceTimer == nil {
                silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
                    self?.finishRecording()
                }
            }
        }
    }
    
    // Callback for AI processing
    var onRecordingFinished: ((String) -> Void)?
    
    private func finishRecording() {
        guard interactionState == .recording else { return }
        
        print("AudioManager: Silence timeout, finished recording")
        stopListening()
        
        interactionState = .processing
        
        // If external handler is set (AI Mode), delegate to it
        // BUT wait, for Echo mode, we don't want to delegate, we want to play recording.
        // The issue is PetViewModel always sets this handler now.
        // We need a way to distinguish modes OR let the handler decide whether to play recording.
        
        if let handler = onRecordingFinished {
            let text = recognizedText
            DispatchQueue.main.async {
                handler(text)
            }
            
            // If it's NOT AI mode (how do we know?), we should play recording.
            // Actually, PetViewModel controls the mode.
            // Let's change the contract: if handler is set, we ALWAYS call it.
            // But we also need to know if we should play audio.
            // Let's add a property `isEchoModeEnabled`.
            if isEchoModeEnabled {
                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                     self.playRecordedAudio()
                 }
            }
            return
        }
        
        // Default Echo Mode (Legacy fallback)
        // 延迟一点点播放，让状态流转更自然
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.playRecordedAudio()
        }
    }
    
    // Mode Control
    var isEchoModeEnabled: Bool = true // Default to true
    
    // MARK: - Speech Recognition
    
    private func prepareSpeechRecognition() {
        // 取消旧任务
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // 检查识别器是否可用
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("AudioManager: Speech recognizer not available")
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                // 识别结束或出错
            }
        }
    }
    
    // MARK: - Playback (Pitch Shift)
    
    private func playRecordedAudio() {
        if !SoundManager.shared.isSoundEnabled {
            print("AudioManager: Sound is disabled (SoundManager), skipping playback")
            restartListening()
            return
        }
        
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            print("AudioManager: No recording file found")
            restartListening()
            return
        }
        
        if isBackgroundMusicEnabled {
            bgmPlayerNode.volume = Float(bgmVolume) * 0.5
        }
        
        // 简易版：直接在主线程配置
        setupAudioSession(isRecording: false)
        
        // 关键：重置 Engine 以清除旧的连接格式缓存
        if engine.isRunning {
            engine.stop()
        }
        // engine.reset() // 注意：reset 可能会断开所有连接，需要谨慎。这里我们手动断开重连。
        
        engine.inputNode.removeTap(onBus: 0)
        
        // 断开所有相关节点，防止格式冲突
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(eqNode)
        
        // 确保节点已 Attach
        if engine.attachedNodes.contains(playerNode) == false { engine.attach(playerNode) }
        if engine.attachedNodes.contains(timePitch) == false { engine.attach(timePitch) }
        if engine.attachedNodes.contains(eqNode) == false { engine.attach(eqNode) }
        
        // BGM 重新连接 (如果需要)
        // engine.connect(bgmPlayerNode, to: engine.mainMixerNode, format: nil) 
        // BGM 通常一直连接着，不需要动
        
        playerNode.volume = Float(petVoiceVolume) * 3.0
        
        // 变音设置
        switch selectedVoiceType {
        case .funny:
            timePitch.pitch = 800
            timePitch.overlap = 8.0
            eqNode.bypass = false
            eqNode.globalGain = 5.0
            for i in 0..<eqNode.bands.count { eqNode.bands[i].bypass = true }
            
        case .youngBoy:
            timePitch.pitch = 600
            timePitch.overlap = 20.0
            eqNode.bypass = false
            eqNode.globalGain = 10.0
            
            let lowCut = eqNode.bands[0]
            lowCut.filterType = .highPass
            lowCut.frequency = 220.0
            lowCut.bypass = false
            
            let midCut = eqNode.bands[1]
            midCut.filterType = .parametric
            midCut.frequency = 600.0
            midCut.bandwidth = 1.5
            midCut.gain = -4.0
            midCut.bypass = false
            
            let highBoost = eqNode.bands[2]
            highBoost.filterType = .parametric
            highBoost.frequency = 3200.0
            highBoost.bandwidth = 1.0
            highBoost.gain = 5.0
            highBoost.bypass = false
            
            let highShelf = eqNode.bands[3]
            highShelf.filterType = .highShelf
            highShelf.frequency = 8000.0
            highShelf.gain = -3.0
            highShelf.bypass = false
        }
        
        let output = engine.mainMixerNode
        
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            
            print("AudioManager: Playing format: \(format)")
            
            // 连接链：Player -> TimePitch -> EQ -> MainMixer
            engine.connect(playerNode, to: timePitch, format: format)
            engine.connect(timePitch, to: eqNode, format: format)
            // 连接到 Mixer 时，允许格式转换 (AudioEngine 会自动处理，只要不是不支持的格式)
            engine.connect(eqNode, to: output, format: format)
            
            if !engine.isRunning {
                try engine.start()
                if isBackgroundMusicEnabled && !bgmPlayerNode.isPlaying {
                    if let buffer = bgmBuffer {
                        bgmPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                        bgmPlayerNode.play()
                    }
                }
            }
            
            interactionState = .playing
            
            // 计算音频时长
            let duration = Double(file.length) / file.processingFormat.sampleRate
            // 加上 0.3 秒缓冲时间，确保尾音完整
            let playbackDuration = duration + 0.3
            
            print("AudioManager: Scheduled playback for \(duration) seconds")
            
            playerNode.scheduleFile(file, at: nil, completionHandler: nil)
            playerNode.play()
            
            // 使用 asyncAfter 控制结束，而不是 completion handler
            // 这样更稳定，避免 completion handler 过早触发
            DispatchQueue.main.asyncAfter(deadline: .now() + playbackDuration) { [weak self] in
                print("AudioManager: Playback time ended")
                self?.stopPlayback()
                self?.restartListening()
            }
            
            print("AudioManager: Started playing recording")
            
        } catch {
            print("AudioManager: Failed to play recording: \(error)")
            restartListening()
        }
    }
    
    private func stopPlayback() {
        if playerNode.isPlaying {
            playerNode.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
    }
    
    func restartListening() {
        // 只有当总开关开启时才重新监听
        if isInteractionEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startListening()
            }
        } else {
            interactionState = .idle
        }
    }
}
