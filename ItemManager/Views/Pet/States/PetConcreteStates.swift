import GameplayKit

// MARK: - Idle State
class IdleState: PetVideoState {
    override var videoName: String { "idle" }
    override var logicalState: PetState { .idle }
    override var isLooping: Bool { true }
    
    override func update(deltaTime seconds: TimeInterval) {
        // 随机洗脸逻辑
        // 仅在非离线模拟时触发
        // 注意：GKState.update 需要由外部驱动
        if Double.random(in: 0...1) < 0.005 {
            stateMachine?.enter(GroomingState.self)
        }
    }
}

// MARK: - Expecting State (期待/拖拽中)
class ExpectingState: PetVideoState {
    private var _videoName: String = PetViewModel.PetVideoPaths.attention
    override var videoName: String { _videoName }
    override var logicalState: PetState { .expecting }
    override var isLooping: Bool { true }
    
    func setVideoName(_ name: String) {
        _videoName = name
    }
}

// MARK: - Interaction State (抚摸)
class InteractionState: PetVideoState {
    private var _videoName: String = PetViewModel.PetVideoPaths.enjoy
    
    override var videoName: String { _videoName }
    override var logicalState: PetState { .interacting }
    override var isLooping: Bool { true } // 抚摸是循环的（按住时）
    
    func setExplicitVideoName(_ name: String) {
        _videoName = name
    }
    
    func setContext(isHead: Bool, mood: Double) {
        // 根据上下文决定视频
        if isHead {
            if mood < 50 {
                _videoName = (Double.random(in: 0...1) < 0.6) ? PetViewModel.PetVideoPaths.angry : PetViewModel.PetVideoPaths.enjoy
            } else {
                _videoName = (Double.random(in: 0...1) < 0.9) ? PetViewModel.PetVideoPaths.enjoy : PetViewModel.PetVideoPaths.angry
            }
        } else {
            // Belly
            if mood < 50 {
                _videoName = (Double.random(in: 0...1) < 0.6) ? PetViewModel.PetVideoPaths.angry : PetViewModel.PetVideoPaths.rolling
            } else {
                _videoName = (Double.random(in: 0...1) < 0.9) ? PetViewModel.PetVideoPaths.rolling : PetViewModel.PetVideoPaths.angry
            }
        }
    }
}

// MARK: - Grooming State (洗脸 - 自动触发)
class GroomingState: PetVideoState {
    override var videoName: String { PetViewModel.PetVideoPaths.grooming }
    override var logicalState: PetState { .interacting }
    override var isLooping: Bool { false }
    
    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        viewModel.status.hygiene = min(100, viewModel.status.hygiene + 5)
        viewModel.showFloatingText("清洁 +5", style: .hygiene)
    }
}

// MARK: - Feeding State (进食)
class FeedingState: PetVideoState {
    private var _videoName: String = PetViewModel.PetVideoPaths.eatingCatFood
    override var videoName: String { _videoName }
    override var logicalState: PetState { .eating }
    override var isLooping: Bool { false }
    
    func setFoodType(_ type: String) {
        if type == "cannedFood" {
            _videoName = PetViewModel.PetVideoPaths.eatingCanned
        } else {
            _videoName = PetViewModel.PetVideoPaths.eatingCatFood
        }
    }
}

// MARK: - Drinking State (喝水)
class DrinkingState: PetVideoState {
    override var videoName: String { PetViewModel.PetVideoPaths.drinking }
    override var logicalState: PetState { .drinking }
    override var isLooping: Bool { false }
}

// MARK: - Playing State (玩耍)
class PlayingState: PetVideoState {
    override var videoName: String { PetViewModel.PetVideoPaths.playing }
    override var logicalState: PetState { .playing }
    override var isLooping: Bool { false }
}

// MARK: - Cleaning State (洗澡 - 主动)
class CleaningState: PetVideoState {
    private var _videoName: String = PetViewModel.PetVideoPaths.bathingHappy
    override var videoName: String { _videoName }
    override var logicalState: PetState { .cleaning }
    override var isLooping: Bool { false }
    
    override func didEnter(from previousState: GKState?) {
        // 决定视频
        let mood = viewModel.status.mood
        if mood < 50 {
            _videoName = (Double.random(in: 0...1) < 0.6) ? PetViewModel.PetVideoPaths.bathingBoring : PetViewModel.PetVideoPaths.bathingHappy
        } else if mood > 90 {
            _videoName = (Double.random(in: 0...1) < 0.9) ? PetViewModel.PetVideoPaths.bathingHappy : PetViewModel.PetVideoPaths.bathingBoring
        } else {
            _videoName = (Double.random(in: 0...1) < 0.6) ? PetViewModel.PetVideoPaths.bathingHappy : PetViewModel.PetVideoPaths.bathingBoring
        }
        super.didEnter(from: previousState)
    }
}

// MARK: - Sleeping State
class SleepingState: PetVideoState {
    override var videoName: String { PetViewModel.PetVideoPaths.sleeping }
    override var logicalState: PetState { .sleeping }
    override var isLooping: Bool { true }
}

// MARK: - Working State
class WorkingState: PetVideoState {
    override var videoName: String {
        // 工作状态下默认播放 idle (视觉上看起来是普通待机，但逻辑上在打工)
        return "idle"
    }
    override var logicalState: PetState { .working }
    override var isLooping: Bool { true }
    
    // Helper to map job to video (Deprecated: 现在统一使用 idle)
    static func getJobVideoName(job: PetJob) -> String {
        return "idle"
    }
}
