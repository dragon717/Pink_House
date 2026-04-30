import SwiftUI

enum ThemeSkinTabBarShapeStyle: Shape {
    case capsule
    case skyConcertStage
    case swanDream

    static func style(for descriptor: ThemeSkinDescriptor?) -> ThemeSkinTabBarShapeStyle {
        switch descriptor?.assetNamespace {
        case "sky_concert":
            return .skyConcertStage
        case "swan_dream":
            return .swanDream
        default:
            return .capsule
        }
    }

    var height: CGFloat {
        switch self {
        case .skyConcertStage:
            return 62
        case .swanDream:
            return 66
        case .capsule:
            return 56
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .capsule:
            return 16
        case .skyConcertStage, .swanDream:
            return 12
        }
    }

    func path(in rect: CGRect) -> Path {
        switch self {
        case .capsule:
            return Capsule(style: .continuous).path(in: rect)
        case .skyConcertStage:
            return skyConcertStagePath(in: rect)
        case .swanDream:
            return UnevenRoundedRectangle(
                topLeadingRadius: 34,
                bottomLeadingRadius: 30,
                bottomTrailingRadius: 34,
                topTrailingRadius: 24,
                style: .continuous
            )
            .path(in: rect)
        }
    }
    private func skyConcertStagePath(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let bottomRadius: CGFloat = 24
        let topBase = minY + 13

        path.move(to: CGPoint(x: minX + 30, y: topBase + 8))
        path.addQuadCurve(
            to: CGPoint(x: minX + width * 0.34, y: topBase - 3),
            control: CGPoint(x: minX + width * 0.16, y: minY + 4)
        )
        path.addQuadCurve(
            to: CGPoint(x: minX + width * 0.63, y: topBase + 7),
            control: CGPoint(x: minX + width * 0.48, y: topBase + 16)
        )
        path.addQuadCurve(
            to: CGPoint(x: maxX - 20, y: topBase + 3),
            control: CGPoint(x: minX + width * 0.80, y: minY + 1)
        )
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: topBase + 22),
            control: CGPoint(x: maxX - 1, y: topBase + 5)
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: maxX - bottomRadius, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + bottomRadius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - bottomRadius),
            control: CGPoint(x: minX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX, y: topBase + 30))
        path.addQuadCurve(
            to: CGPoint(x: minX + 30, y: topBase + 8),
            control: CGPoint(x: minX + 3, y: topBase + 7)
        )
        path.closeSubpath()
        return path
    }
}
