import AVFoundation
import Combine
import Speech
import UIKit
import SoundAnalysis

/// 萌宠互动状态
enum PetInteractionState: String {
    case idle           // 空闲
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
        
        print("AudioManager: Updated volume with gain: \(gain) (Headphones: \(isHeadphones))")
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
    @Published var interactionState: PetInteractionState = .idle
    
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
    // 提高静音阈值以过滤远处声音 (原 -40.0)
    private let silenceThreshold: Float = -25.0 // dB
    private let silenceDuration: TimeInterval = 1.2 // 持续静音多久视为结束
    private var isSpeechDetected = false
    
    // Sound Analysis
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.pinkhouse.AnalysisQueue")
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
        
        print("AudioManager: Route changed, reason: \(reason)")
        
        DispatchQueue.main.async { [weak self] in
            // 路由变化时，重新应用音量设置
            self?.updatePlayerVolume()
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
            if isInteractionEnabled {
                // 互动模式下始终保持 playAndRecord，避免切换开销和 I/O 错误
                // 使用 .voiceChat 模式以启用回声消除 (AEC)，防止 BGM 触发 VAD
                // 添加 .allowBluetoothA2DP 以支持更广泛的蓝牙设备
                // 关键修正：移除 overrideOutputAudioPort(.speaker)，否则会导致蓝牙耳机失效
                // .defaultToSpeaker 选项足以保证在没有耳机时使用扬声器，有耳机时自动切换
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            } else if isRecording {
                // 仅录音（虽然目前逻辑不会走到这里，除非有其他录音需求）
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            } else {
                // 普通播放模式（背景音乐）
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
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
        
        setupAudioSession(isRecording: true)
        
        // 配置引擎进行录音
        // Input -> Mixer (Tap for VAD & File Write) -> Main Mixer (Muted to avoid feedback)
        
        // 确保引擎停止以便重置
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        // 崩溃修复：检查格式有效性，防止后台进入或设备状态异常时崩溃
        if format.sampleRate == 0 || format.channelCount == 0 {
            print("AudioManager: Invalid input format: \(format)")
            stopInteraction()
            return
        }
        
        // 准备语音识别
        prepareSpeechRecognition()
        
        // 准备 SoundAnalysis
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try streamAnalyzer?.add(request, withObserver: self)
            print("AudioManager: Sound Analysis request added")
        } catch {
            print("AudioManager: Failed to create Sound Analysis request: \(error)")
        }
        
        // 准备写入文件
        do {
            if let url = recordingURL {
                // 删除旧文件
                try? FileManager.default.removeItem(at: url)
                // 创建新文件
                audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            }
        } catch {
            print("AudioManager: Failed to create audio file: \(error)")
        }
        
        // 安装 Tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // 0. Sound Analysis
            self.analysisQueue.async {
                self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
            
            // 1. 写入文件 (如果在录音状态)
            if self.interactionState == .recording {
                try? self.audioFile?.write(from: buffer)
                
                // 2. 发送给语音识别
                self.recognitionRequest?.append(buffer)
            }
            
            // 3. VAD 检测
            self.processVAD(buffer: buffer)
        }
        
        do {
            try engine.start()
            // 如果 BGM 启用，重新播放（因为 engine 重启了）
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
            print("AudioManager: Failed to start engine for listening: \(error)")
            stopInteraction()
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
        let isSpeech = classification.identifier == "speech" && classification.confidence > 0.85
        
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
    
    // Voice Activity Detection
    private func processVAD(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let db = 20 * log10(rms)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 结合 音量阈值 和 SoundAnalysis 结果
            // 只有当 音量足够大 且 识别为人声 时，才触发
            // 如果正在录音中，则稍微放宽条件（防止说话中间断掉）
            
            let isLoudEnough = db > self.silenceThreshold
            let isSpeechType = self.isHumanSpeech
            
            // 如果已经在录音，我们更宽容一点，只要音量够大或者持续是人声
            let isVoiceActive: Bool
            if self.interactionState == .recording {
                // 录音中：只要音量不极低，或者检测到人声，就继续
                // 这里我们稍微降低阈值以保持录音连续性
                isVoiceActive = (db > self.silenceThreshold - 5.0) || isSpeechType
            } else {
                // 监听中：必须是高音量且是人声
                isVoiceActive = isLoudEnough && isSpeechType
            }
            
            if isVoiceActive {
                // 检测到声音
                self.onSpeechDetected()
            } else {
                // 静音

                self.onSilenceDetected()
            }
        }
    }
    
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
    
    private func finishRecording() {
        guard interactionState == .recording else { return }
        
        print("AudioManager: Silence timeout, finished recording")
        stopListening()
        
        interactionState = .processing
        
        // 延迟一点点播放，让状态流转更自然
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.playRecordedAudio()
        }
    }
    
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
        // 检查全局音效开关 (复用 SoundManager 的开关状态)
        // 如果音效关闭，则不播放复述，直接重新开始监听
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
        
        // 播放回复时，恢复 BGM (但不要太大声，以免盖过语音)
        if isBackgroundMusicEnabled {
            bgmPlayerNode.volume = Float(bgmVolume) * 0.5
        }
        
        // 保持 playAndRecord 模式，不切换 Session
        setupAudioSession(isRecording: false)
        
        // 重建引擎连接：Player -> TimePitch -> EQ -> MainMixer
        engine.stop()
        
        // 移除可能存在的 Input Tap，防止 I/O 冲突
        engine.inputNode.removeTap(onBus: 0)
        
        // 重新连接所有节点
        // 1. Voice Chain
        engine.detach(playerNode)
        engine.detach(timePitch)
        engine.detach(eqNode)
        
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eqNode)
        
        // 2. BGM Chain (确保 BGM 节点也在)
        // 注意：bgmPlayerNode 一直 attach 在 engine 上，不需要 detach/attach
        // 但需要重新 connect
        engine.connect(bgmPlayerNode, to: engine.mainMixerNode, format: nil)
        
        // 设置播放节点音量
        // 应用增益系数 3.0，解决声音小的问题
        playerNode.volume = Float(petVoiceVolume) * 3.0
        
        // 变音设置
        switch selectedVoiceType {
        case .funny:
            timePitch.pitch = 800 // 搞怪变声 (高音调)
            timePitch.overlap = 8.0 // 默认重叠
            
            // 搞怪模式也开启 EQ 以获得 Gain 提升
            eqNode.bypass = false
            eqNode.globalGain = 5.0
            // 重置 EQ Bands (不需要特殊滤波)
            for i in 0..<eqNode.bands.count {
                eqNode.bands[i].bypass = true
            }
            
        case .youngBoy:
            // 优化参数 V2:
            // 1. 稍微提高 Pitch 到 +600 (半个八度)
            timePitch.pitch = 600
            // 2. 增加 Overlap 以获得更平滑的语音效果
            timePitch.overlap = 20.0
            
            // 正太音 EQ 设置：模拟 Formant Shifting
            eqNode.bypass = false
            eqNode.globalGain = 10.0 // 大幅提升增益，补偿滤波带来的衰减
            
            // Band 0: Low Cut (High Pass) - 更激进地削减低频，去除成年男性胸腔共鸣
            let lowCut = eqNode.bands[0]
            lowCut.filterType = .highPass
            lowCut.frequency = 220.0 // 提高截止频率到 220Hz
            lowCut.bypass = false
            
            // Band 1: Mid Cut (Parametric) - 挖掉中低频厚度 (500-800Hz)，这是成年男性声音特征明显的区域
            let midCut = eqNode.bands[1]
            midCut.filterType = .parametric
            midCut.frequency = 600.0
            midCut.bandwidth = 1.5
            midCut.gain = -4.0 // 衰减 4dB
            midCut.bypass = false
            
            // Band 2: High Boost (Parametric) - 提升中高频，增加清脆感和穿透力
            let highBoost = eqNode.bands[2]
            highBoost.filterType = .parametric
            highBoost.frequency = 3200.0
            highBoost.bandwidth = 1.0
            highBoost.gain = 5.0 // 增益 +5dB
            highBoost.bypass = false
            
            // Band 3: High Shelf - 稍微压一下极高频，防止变调后的齿音刺耳
            let highShelf = eqNode.bands[3]
            highShelf.filterType = .highShelf
            highShelf.frequency = 8000.0
            highShelf.gain = -3.0
            highShelf.bypass = false
        }
        
        let output = engine.mainMixerNode
        
        do {
            let file = try AVAudioFile(forReading: url)
            
            // 连接链路：Player -> TimePitch -> EQ -> Output
            engine.connect(playerNode, to: timePitch, format: file.processingFormat)
            engine.connect(timePitch, to: eqNode, format: file.processingFormat)
            engine.connect(eqNode, to: output, format: file.processingFormat)
            
            try engine.start()
            
            // 恢复 BGM 播放 (Engine 重启后需要重新 schedule)
            if isBackgroundMusicEnabled && !bgmPlayerNode.isPlaying {
                if let buffer = bgmBuffer {
                    bgmPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                    bgmPlayerNode.play()
                }
            }
            
            interactionState = .playing
            
            playerNode.scheduleFile(file, at: nil) { [weak self] in
                // 播放完成回调
                DispatchQueue.main.async {
                    print("AudioManager: Playback finished")
                    self?.stopPlayback()
                    self?.restartListening()
                }
            }
            
            playerNode.play()
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
    
    private func restartListening() {
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
