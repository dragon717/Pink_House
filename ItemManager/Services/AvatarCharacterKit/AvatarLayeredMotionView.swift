import SwiftUI

#if canImport(UIKit)
import UIKit

struct AvatarLayeredMotionView: View {
    let request: AvatarRenderRequest
    var contentMode: ContentMode = .fit

    @State private var package: AvatarLayerPackage?

    var body: some View {
        Group {
            if let package {
                TimelineView(.animation) { timeline in
                    render(package: package, date: timeline.date)
                }
            } else {
                fallbackImage
            }
        }
        .task(id: "\(request.characterID.rawValue)|\(request.hairStyleID.rawValue)") {
            package = AvatarLayerAssetResolver.package(
                characterID: request.characterID,
                hairStyleID: request.hairStyleID
            )
        }
    }

    private func render(package: AvatarLayerPackage, date: Date) -> some View {
        GeometryReader { geometry in
            let scale = renderScale(container: geometry.size, source: package.sourceSize)
            let renderSize = CGSize(
                width: package.sourceSize.width * scale,
                height: package.sourceSize.height * scale
            )
            let phase = AvatarLayerMotionPhase(
                seconds: request.isPaused ? 0 : date.timeIntervalSinceReferenceDate,
                isActive: !request.isPaused
            )

            ZStack(alignment: .topLeading) {
                ForEach(package.layers) { layer in
                    let transform = phase.layerTransform(for: layer.bone)
                    let anchor = package.anchorUnitPoint(for: layer)

                    Image(uiImage: layer.image)
                        .resizable()
                        .frame(
                            width: layer.placement.width * scale,
                            height: layer.placement.height * scale
                        )
                        .scaleEffect(transform.scale, anchor: anchor)
                        .rotationEffect(.degrees(transform.rotationDegrees), anchor: anchor)
                        .offset(
                            x: transform.offset.width * scale,
                            y: transform.offset.height * scale
                        )
                        .position(
                            x: layer.placement.midX * scale,
                            y: layer.placement.midY * scale
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(width: renderSize.width, height: renderSize.height, alignment: .topLeading)
            .scaleEffect(phase.containerScale, anchor: .center)
            .offset(
                x: phase.containerOffset.width * scale,
                y: phase.containerOffset.height * scale
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func renderScale(container: CGSize, source: CGSize) -> CGFloat {
        guard source.width > 0, source.height > 0 else { return 1 }
        let widthRatio = container.width / source.width
        let heightRatio = container.height / source.height
        switch contentMode {
        case .fill:
            return max(widthRatio, heightRatio)
        case .fit:
            return min(widthRatio, heightRatio)
        @unknown default:
            return min(widthRatio, heightRatio)
        }
    }

    private var fallbackImage: some View {
        Image(request.characterID.staticImageName)
            .resizable()
            .aspectRatio(3.0 / 4.0, contentMode: contentMode)
    }
}

enum AvatarLayerAssetResolver {
    static func isAvailable(characterID: AvatarCharacterID, hairStyleID: AvatarHairStyleID) -> Bool {
        package(characterID: characterID, hairStyleID: hairStyleID) != nil
    }

    static func package(characterID: AvatarCharacterID, hairStyleID: AvatarHairStyleID) -> AvatarLayerPackage? {
        let baseDirectory = "asserts/avatar/\(characterID.assetDirectoryName)/live2d"
        guard let rootURL = Bundle.main.resourceURL?.appendingPathComponent(baseDirectory),
              let rig = decode(AvatarRigManifest.self, from: rootURL.appendingPathComponent("rig_manifest.json")) else {
            return nil
        }

        let bodyLayers = loadLayers(
            rig.layers,
            rootURL: rootURL,
            sourceSize: rig.sourceSize.cgSize,
            fallbackCanvasSize: rig.sourceSize.cgSize
        )

        let hairManifestURL = rootURL
            .appendingPathComponent("hairstyles")
            .appendingPathComponent(hairStyleID.rawValue)
            .appendingPathComponent("hairstyle_manifest.json")
        let hairManifest = decode(AvatarLayerGroupManifest.self, from: hairManifestURL)
        let hairLayers = loadLayers(
            hairManifest?.layers ?? [],
            rootURL: rootURL,
            sourceSize: rig.sourceSize.cgSize,
            fallbackCanvasSize: rig.sourceSize.cgSize
        )

        let layers = (bodyLayers + hairLayers)
            .sorted { lhs, rhs in
                if lhs.z == rhs.z {
                    return lhs.name < rhs.name
                }
                return lhs.z < rhs.z
            }

        guard !layers.isEmpty else { return nil }
        return AvatarLayerPackage(sourceSize: rig.sourceSize.cgSize, bones: rig.bones, layers: layers)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }

    private static func loadLayers(
        _ specs: [AvatarLayerSpec],
        rootURL: URL,
        sourceSize: CGSize,
        fallbackCanvasSize: CGSize
    ) -> [AvatarLayer] {
        specs.compactMap { spec in
            let imageURL = rootURL.appendingPathComponent(spec.file)
            guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
            let canvasSize = spec.canvasSize?.cgSize ?? fallbackCanvasSize
            let placement = spec.placementRect(sourceSize: sourceSize, canvasSize: canvasSize)
            guard placement.width > 0, placement.height > 0 else { return nil }

            return AvatarLayer(
                name: spec.name,
                image: image,
                placement: placement,
                bone: spec.bone,
                z: spec.z
            )
        }
    }
}

struct AvatarLayerPackage {
    let sourceSize: CGSize
    let bones: [String: AvatarBoneSpec]
    let layers: [AvatarLayer]

    func anchorUnitPoint(for layer: AvatarLayer) -> UnitPoint {
        let normalizedAnchor = bones[layer.bone]?.anchor ?? [
            Double(layer.placement.midX / max(sourceSize.width, 1)),
            Double(layer.placement.midY / max(sourceSize.height, 1))
        ]
        guard normalizedAnchor.count >= 2,
              layer.placement.width > 0,
              layer.placement.height > 0 else {
            return .center
        }

        let anchorX = CGFloat(normalizedAnchor[0]) * sourceSize.width
        let anchorY = CGFloat(normalizedAnchor[1]) * sourceSize.height
        let unitX = (anchorX - layer.placement.minX) / layer.placement.width
        let unitY = (anchorY - layer.placement.minY) / layer.placement.height
        return UnitPoint(x: unitX.clamped(to: 0...1), y: unitY.clamped(to: 0...1))
    }
}

struct AvatarLayer: Identifiable {
    var id: String { name }
    let name: String
    let image: UIImage
    let placement: CGRect
    let bone: String
    let z: Int
}

private struct AvatarRigManifest: Decodable {
    let sourceSize: AvatarSize
    let layers: [AvatarLayerSpec]
    let bones: [String: AvatarBoneSpec]

    enum CodingKeys: String, CodingKey {
        case sourceSize = "source_size"
        case layers
        case bones
    }
}

private struct AvatarLayerGroupManifest: Decodable {
    let layers: [AvatarLayerSpec]
}

private struct AvatarLayerSpec: Decodable {
    let name: String
    let file: String
    let sourceBBoxPixels: [Double]
    let placementBBoxPixels: [Double]?
    let canvasSize: AvatarSize?
    let bone: String
    let z: Int

    enum CodingKeys: String, CodingKey {
        case name
        case file
        case sourceBBoxPixels = "source_bbox_pixels"
        case placementBBoxPixels = "placement_bbox_pixels"
        case canvasSize = "canvas_size"
        case bone
        case z
    }

    func placementRect(sourceSize: CGSize, canvasSize: CGSize) -> CGRect {
        let raw = placementBBoxPixels ?? sourceBBoxPixels
        guard raw.count == 4 else { return .zero }
        let scaleX = sourceSize.width / max(canvasSize.width, 1)
        let scaleY = sourceSize.height / max(canvasSize.height, 1)
        let x0 = CGFloat(raw[0]) * scaleX
        let y0 = CGFloat(raw[1]) * scaleY
        let x1 = CGFloat(raw[2]) * scaleX
        let y1 = CGFloat(raw[3]) * scaleY
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

struct AvatarBoneSpec: Decodable {
    let parent: String?
    let anchor: [Double]
}

private struct AvatarSize: Decodable {
    let width: Double
    let height: Double

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        width = try container.decode(Double.self)
        height = try container.decode(Double.self)
    }
}

private struct AvatarLayerMotionPhase {
    let seconds: TimeInterval
    let isActive: Bool

    private var breath: Double {
        guard isActive else { return 0 }
        return sin(seconds * .pi * 2 / 3.4)
    }

    var containerScale: CGFloat {
        1 + CGFloat(breath * 0.0035)
    }

    var containerOffset: CGSize {
        offset(0, breath * -3)
    }

    func layerTransform(for bone: String) -> AvatarLayerTransform {
        guard isActive else { return .identity }

        let hairLag = sin(seconds * .pi * 2 / 3.1 + 0.55)

        switch bone {
        case "hairBack", "hairBackDetail":
            return AvatarLayerTransform(rotationDegrees: hairLag * 0.8, offset: offset(hairLag * 1.2, breath * 0.6))
        case "hairFront", "hairFrontDetail":
            return AvatarLayerTransform(rotationDegrees: hairLag * -0.5, offset: offset(hairLag * 0.7, breath * -0.4))
        case "hairSideLeft", "hairSideLeftDetail":
            return AvatarLayerTransform(rotationDegrees: hairLag * -1.0, offset: offset(hairLag * -1.5, breath * 0.8))
        case "hairSideRight", "hairSideRightDetail":
            return AvatarLayerTransform(rotationDegrees: hairLag * 1.0, offset: offset(hairLag * 1.5, breath * 0.8))
        default:
            return .identity
        }
    }

    private func offset(_ x: Double, _ y: Double) -> CGSize {
        CGSize(width: CGFloat(x), height: CGFloat(y))
    }
}

private struct AvatarLayerTransform {
    static let identity = AvatarLayerTransform()

    var rotationDegrees: Double = 0
    var offset: CGSize = .zero
    var scale: CGFloat = 1
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
#endif
