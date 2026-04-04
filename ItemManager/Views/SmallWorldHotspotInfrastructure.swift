import SwiftUI

struct SmallWorldHotspotLabelSpec {
    let text: String
    var style: SmallWorldLabelStyle = .diagonal(angle: 45)
    var position: CGPoint? = nil
    var hitPadding: EdgeInsets? = nil
}

struct SmallWorldHotspotHitPolicy {
    var outsets: EdgeInsets = EdgeInsets()
    var minimumWidth: CGFloat = 1
    var minimumHeight: CGFloat = 1

    static let exact = SmallWorldHotspotHitPolicy()

    static func expanded(
        extraWidth: CGFloat,
        extraHeight: CGFloat,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> SmallWorldHotspotHitPolicy {
        SmallWorldHotspotHitPolicy(
            outsets: EdgeInsets(
                top: extraHeight / 2,
                leading: extraWidth / 2,
                bottom: extraHeight / 2,
                trailing: extraWidth / 2
            ),
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
    }

    static func directional(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        bottom: CGFloat = 0,
        trailing: CGFloat = 0,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> SmallWorldHotspotHitPolicy {
        SmallWorldHotspotHitPolicy(
            outsets: EdgeInsets(
                top: top,
                leading: leading,
                bottom: bottom,
                trailing: trailing
            ),
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
    }

    func interactionRect(for baseRect: CGRect) -> CGRect {
        var rect = CGRect(
            x: baseRect.minX - outsets.leading,
            y: baseRect.minY - outsets.top,
            width: baseRect.width + outsets.leading + outsets.trailing,
            height: baseRect.height + outsets.top + outsets.bottom
        )

        if rect.width < minimumWidth {
            let delta = minimumWidth - rect.width
            rect.origin.x -= delta / 2
            rect.size.width = minimumWidth
        }

        if rect.height < minimumHeight {
            let delta = minimumHeight - rect.height
            rect.origin.y -= delta / 2
            rect.size.height = minimumHeight
        }

        return rect
    }
}

struct SmallWorldHotspotSpec: Identifiable {
    let id: String
    let name: String
    let rect: CGRect
    let debugColor: Color
    var label: SmallWorldHotspotLabelSpec? = nil
    var destination: SmallWorldDestination? = nil
    var guideTargetKey: GuideTargetKey? = nil
    var hitPolicy: SmallWorldHotspotHitPolicy = .exact
    let action: () -> Void
}

struct SmallWorldHotspotOverlay: View {
    let logPrefix: String
    let hotspots: [SmallWorldHotspotSpec]
    let containerSize: CGSize
    let imageFrame: CGRect
    var showDebug: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hotspots) { hotspot in
                SmallWorldHotspotNode(
                    logPrefix: logPrefix,
                    hotspot: hotspot,
                    containerSize: containerSize,
                    imageFrame: imageFrame,
                    showDebug: showDebug
                )
            }
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
    }
}

private struct SmallWorldHotspotNode: View {
    let logPrefix: String
    let hotspot: SmallWorldHotspotSpec
    let containerSize: CGSize
    let imageFrame: CGRect
    let showDebug: Bool
    @State private var measuredLabelSize: CGSize = .zero

    private var baseSize: CGSize {
        CGSize(
            width: max(1, hotspot.rect.width * imageFrame.width),
            height: max(1, hotspot.rect.height * imageFrame.height)
        )
    }

    private var baseRect: CGRect {
        CGRect(
            x: imageFrame.minX + hotspot.rect.minX * imageFrame.width,
            y: imageFrame.minY + hotspot.rect.minY * imageFrame.height,
            width: baseSize.width,
            height: baseSize.height
        )
    }

    private var interactionRect: CGRect {
        hotspot.hitPolicy.interactionRect(for: baseRect)
    }

    private var center: CGPoint {
        CGPoint(
            x: interactionRect.midX,
            y: interactionRect.midY
        )
    }

    private var labelPosition: CGPoint? {
        guard let label = hotspot.label else { return nil }
        let normalized = label.position ?? CGPoint(x: hotspot.rect.midX, y: hotspot.rect.midY)
        return CGPoint(
            x: imageFrame.minX + normalized.x * imageFrame.width,
            y: imageFrame.minY + normalized.y * imageFrame.height
        )
    }

    private var labelHitRect: CGRect? {
        guard
            let label = hotspot.label,
            let hitPadding = label.hitPadding,
            let labelPosition,
            measuredLabelSize.width > 0,
            measuredLabelSize.height > 0
        else {
            return nil
        }

        let width = measuredLabelSize.width + hitPadding.leading + hitPadding.trailing
        let height = measuredLabelSize.height + hitPadding.top + hitPadding.bottom

        return CGRect(
            x: labelPosition.x - width / 2,
            y: labelPosition.y - height / 2,
            width: width,
            height: height
        )
    }

    var body: some View {
        ZStack {
            if let key = hotspot.guideTargetKey {
                Color.clear
                    .frame(width: interactionRect.width, height: interactionRect.height)
                    .captureGuideTarget(key)
                    .position(center)
                    .allowsHitTesting(false)
            }

            tapButton(
                rect: interactionRect,
                regionName: "主热区",
                isAccessibilityPrimary: true,
                debugTitle: debugTitle,
                debugColor: hotspot.debugColor
            )

            if let labelHitRect {
                tapButton(
                    rect: labelHitRect,
                    regionName: "标签热区",
                    isAccessibilityPrimary: false,
                    debugTitle: "\(hotspot.name)\n标签热区",
                    debugColor: hotspot.debugColor.opacity(0.72)
                )
            }

            if let label = hotspot.label, let labelPosition {
                FloatingTextLabel(text: label.text, style: label.style)
                    .readRenderedSize { measuredLabelSize = $0 }
                    .allowsHitTesting(false)
                    .position(labelPosition)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private var debugTitle: String {
        let baseWidth = Int(baseSize.width.rounded())
        let baseHeight = Int(baseSize.height.rounded())
        let targetWidth = Int(interactionRect.width.rounded())
        let targetHeight = Int(interactionRect.height.rounded())

        guard baseWidth != targetWidth || baseHeight != targetHeight else {
            return hotspot.name
        }

        return "\(hotspot.name)\n\(baseWidth)x\(baseHeight) -> \(targetWidth)x\(targetHeight)"
    }

    @ViewBuilder
    private func tapButton(
        rect: CGRect,
        regionName: String,
        isAccessibilityPrimary: Bool,
        debugTitle: String,
        debugColor: Color
    ) -> some View {
        Button(action: { logAndTrigger(regionName: regionName) }) {
            if showDebug {
                ZStack {
                    Rectangle()
                        .fill(debugColor.opacity(0.24))
                        .border(debugColor, width: 2)
                    Text(debugTitle)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .cornerRadius(4)
                }
                .contentShape(Rectangle())
            } else {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAccessibilityPrimary ? hotspot.name : "")
        .accessibilityIdentifier("smallworld.hotspot.\(hotspot.id)\(isAccessibilityPrimary ? "" : ".label")")
        .accessibilityHidden(!isAccessibilityPrimary)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func logAndTrigger(regionName: String) {
        print(
            "[\(logPrefix)] 热区点击: \(hotspot.name), 坐标: (\(hotspot.rect.minX), \(hotspot.rect.minY)), " +
            "命中区域: \(regionName), 原始尺寸: \(baseSize.width)x\(baseSize.height), 交互尺寸: \(interactionRect.width)x\(interactionRect.height)"
        )
        hotspot.action()
    }
}

private struct SmallWorldMeasuredSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func readRenderedSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: SmallWorldMeasuredSizePreferenceKey.self,
                        value: proxy.size
                    )
            }
        )
        .onPreferenceChange(SmallWorldMeasuredSizePreferenceKey.self, perform: onChange)
    }
}

enum SmallWorldImageLayout {
    static func aspectFitFrame(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height

        if containerAspectRatio > imageAspectRatio {
            let height = containerSize.height
            let width = height * imageAspectRatio
            return CGRect(
                x: (containerSize.width - width) / 2,
                y: 0,
                width: width,
                height: height
            )
        } else {
            let width = containerSize.width
            let height = width / imageAspectRatio
            return CGRect(
                x: 0,
                y: (containerSize.height - height) / 2,
                width: width,
                height: height
            )
        }
    }
}

// TODO: When House supports user-authored room composition, lift SmallWorldHotspotSpec
// and room definitions into a persisted scene schema instead of these static view configs.
