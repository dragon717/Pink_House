import GameplayKit
import SwiftUI

/// 宠物视频状态基类 (对应 GameplayKit 的 State)
class PetVideoState: GKState {
    unowned let viewModel: PetViewModel
    
    // 状态对应的视频名称 (子类覆盖)
    var videoName: String { return "idle" }
    
    // 对应的逻辑状态 (子类覆盖)
    var logicalState: PetState { return .idle }
    
    // 是否循环播放 (子类覆盖)
    var isLooping: Bool { return true }
    
    // 是否允许被打断 (子类覆盖)
    var canInterupt: Bool { return true }
    
    init(viewModel: PetViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    override func didEnter(from previousState: GKState?) {
        print("PetStateMachine: Entering \(type(of: self)) (Video: \(videoName), Loop: \(isLooping))")
        
        // 驱动 ViewModel 更新视频
        // 使用 DispatchQueue.main.async 确保 UI 更新在主线程
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.viewModel.updateVideoState(videoName: self.videoName, isLooping: self.isLooping)
            // 同步更新逻辑状态
            self.viewModel.currentState = self.logicalState
        }
    }
}
