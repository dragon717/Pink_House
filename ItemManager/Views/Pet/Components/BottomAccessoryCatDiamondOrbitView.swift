import SwiftUI
import Combine

@available(iOS 26.0, *)
struct BottomAccessoryCatDiamondOrbitView: View {
    let config: BottomAccessoryCatDiamondOrbitConfig
    let petName: String
    let action: () -> Void

    @StateObject private var viewModel: BottomAccessoryCatDiamondOrbitViewModel

    init(
        config: BottomAccessoryCatDiamondOrbitConfig = BottomAccessoryCatDiamondOrbitConfig(),
        petName: String,
        action: @escaping () -> Void
    ) {
        self.config = config
        self.petName = petName
        self.action = action
        _viewModel = StateObject(
            wrappedValue: BottomAccessoryCatDiamondOrbitViewModel(
                config: config,
                petName: petName
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            Button(action: action) {
                SeamlessVideoPlayer(
                    videoName: viewModel.currentMotionVideoName,
                    isLooping: viewModel.isMotionVideoLooping,
                    isMirrored: viewModel.isMotionVideoMirrored,
                    playbackRate: viewModel.motionPlaybackRate,
                    isMuted: true,
                    volume: 0,
                    isPaused: viewModel.isPlaybackPaused,
                    onFinished: {
                        viewModel.handleMotionVideoFinished()
                    }
                )
                .frame(width: config.petSize.width, height: config.petSize.height)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .frame(
                width: config.petSize.width + config.hitSlop.width,
                height: config.petSize.height + config.hitSlop.height
            )
            .position(
                x: viewModel.currentPosition.x * geometry.size.width,
                y: viewModel.currentPosition.y * geometry.size.height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewModel.startIfNeeded()
            }
            .onChange(of: petName) { newValue in
                viewModel.updatePetName(newValue)
            }
        }
        .frame(height: config.contentHeight)
    }
}
