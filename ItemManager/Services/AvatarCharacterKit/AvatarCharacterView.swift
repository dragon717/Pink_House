import SwiftUI

struct AvatarCharacterView: View {
    let request: AvatarRenderRequest
    var contentMode: ContentMode = .fit
    var onActionFinished: (() -> Void)?

    var body: some View {
        Group {
            switch request.preferredBackend {
            case .staticImage:
                staticImageView
            case .transparentVideo:
                transparentVideoView
            case .live2d:
                Live2DAvatarView(request: request)
            }
        }
        .accessibilityLabel(request.characterID.displayName)
    }

    @ViewBuilder
    private var staticImageView: some View {
        if UIImage(named: request.characterID.staticImageName) != nil {
            image(request.characterID.staticImageName)
        } else {
            fallbackSilhouette
        }
    }

    @ViewBuilder
    private var transparentVideoView: some View {
        if let videoName = AvatarVideoAssetResolver.firstAvailableVideoName(
            characterID: request.characterID,
            action: request.action
        ) {
            SeamlessVideoPlayer(
                videoName: videoName,
                isLooping: request.action.loopsByDefault,
                isMuted: true,
                volume: 0,
                isPaused: request.isPaused,
                onFinished: onActionFinished
            )
        } else {
            staticImageView
        }
    }

    @ViewBuilder
    private func image(_ name: String) -> some View {
        let base = Image(name).resizable()
        switch contentMode {
        case .fill:
            base.scaledToFill()
        case .fit:
            base.scaledToFit()
        @unknown default:
            base.scaledToFit()
        }
    }

    private var fallbackSilhouette: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.pink.opacity(0.08))
            Image(systemName: "figure.stand")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.pink.opacity(0.45))
        }
    }
}
