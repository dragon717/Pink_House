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
                live2DView
            }
        }
        .accessibilityLabel(request.characterID.displayName)
    }

    @ViewBuilder
    private var staticImageView: some View {
        #if canImport(UIKit)
        if AvatarLayerAssetResolver.isAvailable(
            characterID: request.characterID,
            hairStyleID: request.hairStyleID
        ) {
            AvatarLayeredMotionView(request: request.staticSnapshotRequest, contentMode: contentMode)
        } else if let image = AvatarStaticImageResolver.image(
            characterID: request.characterID,
            hairStyleID: request.hairStyleID
        ) {
            avatarImage(image)
        } else {
            fallbackSilhouette
        }
        #else
        fallbackSilhouette
        #endif
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
    private var live2DView: some View {
        #if canImport(UIKit)
        if AvatarLayerAssetResolver.isAvailable(
            characterID: request.characterID,
            hairStyleID: request.hairStyleID
        ) {
            AvatarLayeredMotionView(request: request, contentMode: contentMode)
        } else {
            Live2DAvatarView(request: request)
        }
        #else
        fallbackSilhouette
        #endif
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

    #if canImport(UIKit)
    @ViewBuilder
    private func avatarImage(_ image: UIImage) -> some View {
        let base = Image(uiImage: image).resizable()
        switch contentMode {
        case .fill:
            base.scaledToFill()
        case .fit:
            base.scaledToFit()
        @unknown default:
            base.scaledToFit()
        }
    }
    #endif

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

private extension AvatarRenderRequest {
    var staticSnapshotRequest: AvatarRenderRequest {
        var copy = self
        copy.isPaused = true
        return copy
    }
}
