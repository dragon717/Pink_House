import AVFoundation
import Combine
import Speech
import UIKit

/// 萌宠互动状态
enum PetInteractionState: String {
    case idle           // 空闲
    case listening      // 正在监听（等待人声）
    case recording      // 正在录音（人声输入中）
    case processing     // 处理中（录音结束，准备播放）
    case playing        // 播放中（变音复述）
}

/// 总的萌宠声音管理器
/// 负责控制背景音乐、麦克风监听、语音识别和回声模式
@MainActor
final class AudioManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    static let shared = AudioManager()
    
    // MARK: - Published Properties
    
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
    
    private var bgmPlayer: AVAudioPlayer?
    
    // Audio Engine & Nodes
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitch = AVAudioUnitTimePitch()
    private var mixerNode = AVAudioMixerNode() // 用于将输入写入文件
    
    // VAD (Voice Activity Detection)
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = -45.0 // dB
    private let silenceDuration: TimeInterval = 1.2 // 持续静音多久视为结束
    private var isSpeechDetected = false
    
    // Recording
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    // Speech Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) // 默认中文，可配置
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private override init() {
        super.init()
        speechRecognizer?.delegate = self
        setupRecordingURL()
        setupNotifications()
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
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
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
            print("AudioManager: No BGM found. Searched for: \(bgmNames) in root and asserts/")
            return
        }
        
        do {
            if bgmPlayer == nil {
                bgmPlayer = try AVAudioPlayer(contentsOf: validUrl)
                bgmPlayer?.numberOfLoops = -1
                bgmPlayer?.volume = 0.3
                bgmPlayer?.prepareToPlay()
            }
            bgmPlayer?.play()
        } catch {
            print("AudioManager: Failed to play BGM: \(error)")
        }
    }
    
    private func stopBackgroundMusic() {
        bgmPlayer?.stop()
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
        
        setupAudioSession(isRecording: true)
        
        // 配置引擎进行录音
        // Input -> Mixer (Tap for VAD & File Write) -> Main Mixer (Muted to avoid feedback)
        
        // 清理引擎
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
            interactionState = .listening
            recognizedText = ""
            print("AudioManager: Started listening...")
        } catch {
            print("AudioManager: Failed to start engine for listening: \(error)")
            stopInteraction()
        }
    }
    
    private func stopListening() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
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
    
    // Voice Activity Detection
    private func processVAD(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let db = 20 * log10(rms)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if db > self.silenceThreshold {
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
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            print("AudioManager: No recording file found")
            restartListening()
            return
        }
        
        // 保持 playAndRecord 模式，不切换 Session
        setupAudioSession(isRecording: false)
        
        // 重建引擎连接：Player -> TimePitch -> MainMixer
        engine.stop()
        
        // 移除可能存在的 Input Tap，防止 I/O 冲突
        engine.inputNode.removeTap(onBus: 0)
        
        engine.detach(playerNode)
        engine.detach(timePitch)
        
        engine.attach(playerNode)
        engine.attach(timePitch)
        
        // 变音设置
        timePitch.pitch = 800 // 提高音调
        
        let output = engine.mainMixerNode
        
        do {
            let file = try AVAudioFile(forReading: url)
            
            engine.connect(playerNode, to: timePitch, format: file.processingFormat)
            engine.connect(timePitch, to: output, format: file.processingFormat)
            
            try engine.start()
            
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
