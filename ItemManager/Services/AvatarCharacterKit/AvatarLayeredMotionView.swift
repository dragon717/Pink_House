import SwiftUI

#if canImport(UIKit)
import UIKit

struct AvatarLayeredMotionView: View {
    let request: AvatarRenderRequest
    var contentMode: ContentMode = .fit

    @Environment(\.scenePhase) private var scenePhase
    @State private var package: AvatarLayerPackage?

    var body: some View {
        let isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        let profile = AvatarMotionQualityProfile.profile(
            for: request.action,
            isLowPowerModeEnabled: isLowPowerModeEnabled
        )
        let isMotionActive = !request.isPaused
            && scenePhase == .active
            && !(profile.pausesInLowPowerMode && isLowPowerModeEnabled)

        Group {
            if let package {
                if isMotionActive {
                    TimelineView(.periodic(
                        from: Date(timeIntervalSinceReferenceDate: 0),
                        by: profile.frameInterval
                    )) { timeline in
                        render(
                            package: package,
                            date: timeline.date,
                            isActive: true,
                            profile: profile
                        )
                    }
                } else {
                    render(
                        package: package,
                        date: Date(timeIntervalSinceReferenceDate: profile.staticPhaseSeconds),
                        isActive: false,
                        profile: profile
                    )
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

    private func render(
        package: AvatarLayerPackage,
        date: Date,
        isActive: Bool,
        profile: AvatarMotionQualityProfile
    ) -> some View {
        GeometryReader { geometry in
            let scale = renderScale(container: geometry.size, source: package.sourceSize)
            let renderSize = CGSize(
                width: package.sourceSize.width * scale,
                height: package.sourceSize.height * scale
            )
            let phase = AvatarLayerMotionPhase(
                seconds: isActive ? date.timeIntervalSinceReferenceDate : profile.staticPhaseSeconds,
                isActive: isActive,
                action: request.action,
                profile: profile
            )

            ZStack(alignment: .topLeading) {
                ForEach(package.layers) { layer in
                    let transform = phase.layerTransform(for: layer.bone, bones: package.bones)
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
                        .opacity(layer.opacity)
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
        .allowsHitTesting(false)
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
    private static let packageCache: NSCache<NSString, AvatarLayerPackageBox> = {
        let cache = NSCache<NSString, AvatarLayerPackageBox>()
        cache.countLimit = 8
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func isAvailable(characterID: AvatarCharacterID, hairStyleID: AvatarHairStyleID) -> Bool {
        package(characterID: characterID, hairStyleID: hairStyleID) != nil
    }

    static func package(characterID: AvatarCharacterID, hairStyleID: AvatarHairStyleID) -> AvatarLayerPackage? {
        let cacheKey = "\(characterID.rawValue)|\(hairStyleID.rawValue)" as NSString
        if let cached = packageCache.object(forKey: cacheKey) {
            return cached.package
        }

        guard let package = makePackage(characterID: characterID, hairStyleID: hairStyleID) else {
            return nil
        }
        packageCache.setObject(
            AvatarLayerPackageBox(package),
            forKey: cacheKey,
            cost: package.estimatedPixelCost
        )
        return package
    }

    private static func makePackage(characterID: AvatarCharacterID, hairStyleID: AvatarHairStyleID) -> AvatarLayerPackage? {
        let baseDirectory = "asserts/avatar/\(characterID.assetDirectoryName)/live2d"
        guard let rootURL = Bundle.main.resourceURL?.appendingPathComponent(baseDirectory),
              let rig = decode(AvatarRigManifest.self, from: rootURL.appendingPathComponent("rig_manifest.json")) else {
            return nil
        }

        if let hybridPackage = makeHybridPackage(
            rig: rig,
            rootURL: rootURL,
            hairStyleID: hairStyleID
        ) {
            return hybridPackage
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

        // Magic-sticker mannequins render the safe base body plus hair only.
        // The hidden default outfit package remains for harness previews and future binding.
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

    private static func makeHybridPackage(
        rig: AvatarRigManifest,
        rootURL: URL,
        hairStyleID: AvatarHairStyleID
    ) -> AvatarLayerPackage? {
        guard let surfacePlates = rig.surfacePlates, !surfacePlates.isEmpty else {
            return nil
        }

        let surfaceKey = surfacePlates[hairStyleID.rawValue] != nil ? hairStyleID.rawValue : "base_body"
        guard let surfaceSpec = surfacePlates[surfaceKey],
              let surfaceLayer = loadSurfacePlate(
                surfaceSpec,
                name: surfaceKey,
                rootURL: rootURL,
                sourceSize: rig.sourceSize.cgSize
              ) else {
            return nil
        }

        let overlayLayers = loadLayers(
            surfaceSpec.layers ?? [],
            rootURL: rootURL,
            sourceSize: rig.sourceSize.cgSize,
            fallbackCanvasSize: rig.sourceSize.cgSize,
            hairStyleID: hairStyleID
        )
        let layers = ([surfaceLayer] + overlayLayers).sorted { lhs, rhs in
            if lhs.z == rhs.z {
                return lhs.name < rhs.name
            }
            return lhs.z < rhs.z
        }

        return AvatarLayerPackage(sourceSize: rig.sourceSize.cgSize, bones: rig.bones, layers: layers)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }

    private static func resourceURL(for path: String, rootURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if path.hasPrefix("asserts/"), let resourceURL = Bundle.main.resourceURL {
            return resourceURL.appendingPathComponent(path)
        }
        return rootURL.appendingPathComponent(path)
    }

    private static func loadSurfacePlate(
        _ spec: AvatarSurfacePlateSpec,
        name: String,
        rootURL: URL,
        sourceSize: CGSize
    ) -> AvatarLayer? {
        let imageURL = resourceURL(for: spec.file, rootURL: rootURL)
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }

        let canvasSize = spec.canvasSize?.cgSize ?? sourceSize
        let placement = spec.placementRect(sourceSize: sourceSize, canvasSize: canvasSize)
        guard placement.width > 0, placement.height > 0 else { return nil }

        return AvatarLayer(
            name: "surface_plate_\(name)",
            image: image,
            placement: placement,
            bone: spec.bone ?? "root",
            z: spec.z ?? 0,
            anchorPixels: spec.anchorPixels,
            opacity: spec.opacity ?? 1,
            motionRole: spec.motionRole
        )
    }

    private static func loadLayers(
        _ specs: [AvatarLayerSpec],
        rootURL: URL,
        sourceSize: CGSize,
        fallbackCanvasSize: CGSize,
        hairStyleID: AvatarHairStyleID? = nil
    ) -> [AvatarLayer] {
        specs.compactMap { spec in
            if let hairStyleScope = spec.hairStyleScope,
               hairStyleScope != hairStyleID?.rawValue {
                return nil
            }
            let imageURL = resourceURL(for: spec.file, rootURL: rootURL)
            guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
            let canvasSize = spec.canvasSize?.cgSize ?? fallbackCanvasSize
            let placement = spec.placementRect(sourceSize: sourceSize, canvasSize: canvasSize)
            guard placement.width > 0, placement.height > 0 else { return nil }

            return AvatarLayer(
                name: spec.name,
                image: image,
                placement: placement,
                bone: spec.bone,
                z: spec.z,
                anchorPixels: spec.anchorPixels,
                opacity: spec.opacity ?? 1,
                motionRole: spec.motionRole
            )
        }
    }
}

private final class AvatarLayerPackageBox: NSObject {
    let package: AvatarLayerPackage

    init(_ package: AvatarLayerPackage) {
        self.package = package
    }
}

struct AvatarLayerPackage {
    let sourceSize: CGSize
    let bones: [String: AvatarBoneSpec]
    let layers: [AvatarLayer]

    var estimatedPixelCost: Int {
        layers.reduce(0) { total, layer in
            total + Int(layer.image.size.width * layer.image.size.height * layer.image.scale * layer.image.scale * 4)
        }
    }

    func anchorUnitPoint(for layer: AvatarLayer) -> UnitPoint {
        let normalizedAnchor = bones[layer.bone]?.anchor ?? [
            Double(layer.placement.midX / max(sourceSize.width, 1)),
            Double(layer.placement.midY / max(sourceSize.height, 1))
        ]
        guard layer.placement.width > 0,
              layer.placement.height > 0 else {
            return .center
        }

        let anchorX: CGFloat
        let anchorY: CGFloat
        if let anchorPixels = layer.anchorPixels, anchorPixels.count >= 2 {
            anchorX = CGFloat(anchorPixels[0])
            anchorY = CGFloat(anchorPixels[1])
        } else if normalizedAnchor.count >= 2 {
            anchorX = CGFloat(normalizedAnchor[0]) * sourceSize.width
            anchorY = CGFloat(normalizedAnchor[1]) * sourceSize.height
        } else {
            anchorX = layer.placement.midX
            anchorY = layer.placement.midY
        }
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
    let anchorPixels: [Double]?
    let opacity: Double
    let motionRole: String?
}

private struct AvatarRigManifest: Decodable {
    let sourceSize: AvatarSize
    let layers: [AvatarLayerSpec]
    let bones: [String: AvatarBoneSpec]
    let surfacePlates: [String: AvatarSurfacePlateSpec]?
    let embeddedOutfits: [String: AvatarEmbeddedOutfitSpec]?

    enum CodingKeys: String, CodingKey {
        case sourceSize = "source_size"
        case layers
        case bones
        case surfacePlates = "surface_plates"
        case embeddedOutfits = "embedded_outfits"
    }
}

private struct AvatarLayerGroupManifest: Decodable {
    let layers: [AvatarLayerSpec]
}

private struct AvatarEmbeddedOutfitSpec: Decodable {
    let manifest: String
    let surfacePlate: String?
    let showInStickerList: Bool?
    let hairStyleScope: String?

    enum CodingKeys: String, CodingKey {
        case manifest
        case surfacePlate = "surface_plate"
        case showInStickerList = "show_in_sticker_list"
        case hairStyleScope = "hair_style_scope"
    }

    func isCompatible(with hairStyleID: AvatarHairStyleID) -> Bool {
        hairStyleScope == nil || hairStyleScope == hairStyleID.rawValue
    }
}

private struct AvatarLayerSpec: Decodable {
    let name: String
    let file: String
    let sourceBBoxPixels: [Double]
    let placementBBoxPixels: [Double]?
    let canvasSize: AvatarSize?
    let bone: String
    let z: Int
    let hairStyleScope: String?
    let anchorPixels: [Double]?
    let motionRole: String?
    let opacity: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case file
        case sourceBBoxPixels = "source_bbox_pixels"
        case placementBBoxPixels = "placement_bbox_pixels"
        case canvasSize = "canvas_size"
        case bone
        case z
        case hairStyleScope = "hair_style_scope"
        case anchorPixels = "anchor_pixels"
        case motionRole = "motion_role"
        case opacity
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

private struct AvatarSurfacePlateSpec: Decodable {
    let file: String
    let sourceBBoxPixels: [Double]?
    let placementBBoxPixels: [Double]?
    let canvasSize: AvatarSize?
    let bone: String?
    let z: Int?
    let anchorPixels: [Double]?
    let motionRole: String?
    let opacity: Double?
    let layers: [AvatarLayerSpec]?

    enum CodingKeys: String, CodingKey {
        case file
        case sourceBBoxPixels = "source_bbox_pixels"
        case placementBBoxPixels = "placement_bbox_pixels"
        case canvasSize = "canvas_size"
        case bone
        case z
        case anchorPixels = "anchor_pixels"
        case motionRole = "motion_role"
        case opacity
        case layers
    }

    func placementRect(sourceSize: CGSize, canvasSize: CGSize) -> CGRect {
        let raw = placementBBoxPixels ?? sourceBBoxPixels ?? [0, 0, Double(canvasSize.width), Double(canvasSize.height)]
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
    let action: AvatarAction
    let profile: AvatarMotionQualityProfile

    private var breath: Double {
        guard isActive else { return 0 }
        return sin(seconds * .pi * 2 / 3.4)
    }

    private var bodySway: Double {
        guard isActive else { return 0 }
        return sin(seconds * .pi * 2 / 4.8 + 0.2)
    }

    private var softPulse: Double {
        guard isActive else { return 0 }
        return sin(seconds * .pi * 2 / 2.6 + 1.4)
    }

    var containerScale: CGFloat {
        1 + CGFloat(breath * profile.containerScaleAmplitude)
    }

    var containerOffset: CGSize {
        offset(0, breath * profile.containerLiftAmplitude)
    }

    func layerTransform(for bone: String, bones: [String: AvatarBoneSpec]) -> AvatarLayerTransform {
        guard isActive else { return .identity }
        return accumulatedTransform(for: bone, bones: bones, visited: [])
    }

    private func accumulatedTransform(
        for bone: String,
        bones: [String: AvatarBoneSpec],
        visited: Set<String>
    ) -> AvatarLayerTransform {
        guard !visited.contains(bone) else { return .identity }

        var nextVisited = visited
        nextVisited.insert(bone)

        let parentTransform: AvatarLayerTransform
        if let parent = bones[bone]?.parent {
            parentTransform = accumulatedTransform(for: parent, bones: bones, visited: nextVisited)
        } else {
            parentTransform = .identity
        }

        return parentTransform.combined(with: localTransform(for: bone))
    }

    private func localTransform(for bone: String) -> AvatarLayerTransform {
        let amplitude = profile.amplitudeScale
        let hairLag = sin(seconds * .pi * 2 / 3.1 + 0.55)
        let hairFloat = sin(seconds * .pi * 2 / 2.7 + 1.15)
        let skirtLag = sin(seconds * .pi * 2 / 3.8 + 0.85)
        let armLag = sin(seconds * .pi * 2 / 4.2 + 0.35)
        let wave = sin(seconds * .pi * 2 / 1.1)
        let happyBounce = action == .happy ? sin(seconds * .pi * 2 / 1.6) : 0
        let talkNod = action == .talkLoop ? sin(seconds * .pi * 2 / 1.25) : 0

        switch bone {
        case "root":
            return AvatarLayerTransform(offset: offset(
                (bodySway * 0.7) * amplitude,
                (breath * -0.8 + happyBounce * -1.4) * amplitude
            ))
        case "torso":
            return AvatarLayerTransform(
                rotationDegrees: bodySway * 0.28 * amplitude,
                offset: offset(bodySway * 0.6 * amplitude, breath * -0.6 * amplitude),
                scale: 1 + CGFloat(breath * 0.0012 * amplitude)
            )
        case "hip":
            return AvatarLayerTransform(
                rotationDegrees: bodySway * -0.18 * amplitude,
                offset: offset(bodySway * -0.35 * amplitude, breath * 0.35 * amplitude)
            )
        case "head":
            return AvatarLayerTransform(
                rotationDegrees: (bodySway * -0.55 + talkNod * 0.45) * amplitude,
                offset: offset(
                    bodySway * -0.9 * amplitude,
                    (breath * -1.0 + talkNod * -0.8) * amplitude
                )
            )
        case "hairBack", "hairBackDetail":
            return AvatarLayerTransform(
                rotationDegrees: hairLag * 1.25 * amplitude,
                offset: offset(
                    hairLag * 1.8 * amplitude,
                    (hairFloat * 1.1 + breath * 0.6) * amplitude
                )
            )
        case "hairFront", "hairFrontDetail":
            return AvatarLayerTransform(
                rotationDegrees: hairLag * -0.65 * amplitude,
                offset: offset(hairLag * 0.8 * amplitude, breath * -0.45 * amplitude)
            )
        case "hairSideLeft", "hairSideLeftDetail":
            return AvatarLayerTransform(
                rotationDegrees: hairLag * -1.7 * amplitude,
                offset: offset(
                    hairLag * -2.1 * amplitude,
                    (hairFloat * 1.5 + breath * 0.8) * amplitude
                )
            )
        case "hairSideRight", "hairSideRightDetail":
            return AvatarLayerTransform(
                rotationDegrees: hairLag * 1.7 * amplitude,
                offset: offset(
                    hairLag * 2.1 * amplitude,
                    (hairFloat * 1.5 + breath * 0.8) * amplitude
                )
            )
        case "upperArmLeft":
            return AvatarLayerTransform(
                rotationDegrees: armLag * -0.38 * amplitude,
                offset: offset(softPulse * -0.25 * amplitude, breath * 0.25 * amplitude)
            )
        case "upperArmRight":
            let actionLift = action == .wave ? -10 + wave * 3.8 : armLag * 0.38
            return AvatarLayerTransform(
                rotationDegrees: actionLift * amplitude,
                offset: offset(softPulse * 0.25 * amplitude, breath * 0.25 * amplitude)
            )
        case "lowerArmLeft":
            return AvatarLayerTransform(
                rotationDegrees: armLag * -0.55 * amplitude,
                offset: offset(softPulse * -0.3 * amplitude, breath * 0.35 * amplitude)
            )
        case "lowerArmRight":
            let actionBend = action == .wave ? -8 + wave * 6 : armLag * 0.55
            return AvatarLayerTransform(
                rotationDegrees: actionBend * amplitude,
                offset: offset(softPulse * 0.3 * amplitude, breath * 0.35 * amplitude)
            )
        case "handLeft":
            return AvatarLayerTransform(
                rotationDegrees: armLag * -0.75 * amplitude,
                offset: offset(softPulse * -0.25 * amplitude, breath * 0.25 * amplitude)
            )
        case "handRight":
            let handWave = action == .wave ? wave * 9 : armLag * 0.75
            return AvatarLayerTransform(
                rotationDegrees: handWave * amplitude,
                offset: offset(softPulse * 0.25 * amplitude, breath * 0.25 * amplitude)
            )
        case "skirt":
            return AvatarLayerTransform(
                rotationDegrees: skirtLag * 0.55 * amplitude,
                offset: offset(skirtLag * 1.1 * amplitude, breath * 0.65 * amplitude),
                scale: 1 + CGFloat(breath * 0.0018 * amplitude)
            )
        case "thighLeft", "legLeft":
            return AvatarLayerTransform(
                rotationDegrees: bodySway * 0.10 * amplitude,
                offset: offset(bodySway * 0.18 * amplitude, breath * 0.18 * amplitude)
            )
        case "thighRight", "legRight":
            return AvatarLayerTransform(
                rotationDegrees: bodySway * -0.10 * amplitude,
                offset: offset(bodySway * -0.18 * amplitude, breath * 0.18 * amplitude)
            )
        case "lowerLegLeft":
            return AvatarLayerTransform(
                rotationDegrees: bodySway * 0.08 * amplitude,
                offset: offset(bodySway * 0.12 * amplitude, breath * 0.14 * amplitude)
            )
        case "lowerLegRight":
            return AvatarLayerTransform(
                rotationDegrees: bodySway * -0.08 * amplitude,
                offset: offset(bodySway * -0.12 * amplitude, breath * 0.14 * amplitude)
            )
        case "footLeft":
            return AvatarLayerTransform(rotationDegrees: bodySway * 0.12 * amplitude)
        case "footRight":
            return AvatarLayerTransform(rotationDegrees: bodySway * -0.12 * amplitude)
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

    func combined(with other: AvatarLayerTransform) -> AvatarLayerTransform {
        AvatarLayerTransform(
            rotationDegrees: rotationDegrees + other.rotationDegrees,
            offset: CGSize(
                width: offset.width + other.offset.width,
                height: offset.height + other.offset.height
            ),
            scale: scale * other.scale
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
#endif
