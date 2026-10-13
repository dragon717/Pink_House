import SwiftUI
import UIKit

/// Small vector illustrations stay crisp in both the rail and drawer.
struct WardrobeStorageIcon: View {
    let kind: WardrobeStorageIconKind
    var size: CGFloat = 42
    var selected = false
    var imageFile: String? = nil
    var imageData: Data? = nil
    @Environment(\.wardrobeStoragePalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [palette.iconTop.color, palette.iconBottom.color],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Circle().strokeBorder(selected ? palette.accent.color : palette.border.color, lineWidth: 1) }
                .shadow(color: palette.accent.color.opacity(selected ? 0.18 : 0.08), radius: 3, y: 2)
            if let customImage = imageData.flatMap({ UIImage(data: $0) })
                ?? imageFile.flatMap({ WardrobeStorageIconStore.shared.image(named: $0) }) {
                Image(uiImage: customImage).resizable().scaledToFill()
                    .frame(width: size * 0.84, height: size * 0.84)
                    .clipShape(Circle())
            } else {
                illustration
                    .padding(size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var illustration: some View {
            Canvas { context, canvasSize in
                var context = context
                context.scaleBy(x: canvasSize.width / 100, y: canvasSize.height / 100)
                var body = Path(), detail = Path()
                switch kind {
                case .wardrobe:
                    body.move(to: CGPoint(x: 24, y: 82)); body.addLine(to: CGPoint(x: 24, y: 31))
                    body.addQuadCurve(to: CGPoint(x: 76, y: 31), control: CGPoint(x: 50, y: 8))
                    body.addLine(to: CGPoint(x: 76, y: 82)); body.closeSubpath()
                    detail.move(to: CGPoint(x: 50, y: 26)); detail.addLine(to: CGPoint(x: 50, y: 78))
                    detail.addRoundedRect(in: CGRect(x: 30, y: 35, width: 14, height: 39), cornerSize: CGSize(width: 4, height: 4))
                    detail.addRoundedRect(in: CGRect(x: 56, y: 35, width: 14, height: 39), cornerSize: CGSize(width: 4, height: 4))
                    detail.move(to: CGPoint(x: 27, y: 82)); detail.addLine(to: CGPoint(x: 27, y: 88))
                    detail.move(to: CGPoint(x: 73, y: 82)); detail.addLine(to: CGPoint(x: 73, y: 88))
                case .shoes:
                    body.move(to: CGPoint(x: 18, y: 67))
                    body.addCurve(to: CGPoint(x: 41, y: 31), control1: CGPoint(x: 29, y: 65), control2: CGPoint(x: 33, y: 39))
                    body.addQuadCurve(to: CGPoint(x: 58, y: 59), control: CGPoint(x: 57, y: 39))
                    body.addQuadCurve(to: CGPoint(x: 83, y: 65), control: CGPoint(x: 76, y: 57))
                    body.addQuadCurve(to: CGPoint(x: 81, y: 76), control: CGPoint(x: 89, y: 74))
                    body.addLine(to: CGPoint(x: 44, y: 76)); body.addLine(to: CGPoint(x: 37, y: 70))
                    body.addLine(to: CGPoint(x: 30, y: 85)); body.addLine(to: CGPoint(x: 22, y: 85))
                    body.addLine(to: CGPoint(x: 24, y: 73)); body.closeSubpath()
                    detail.move(to: CGPoint(x: 30, y: 53)); detail.addQuadCurve(to: CGPoint(x: 53, y: 52), control: CGPoint(x: 42, y: 44))
                    detail.move(to: CGPoint(x: 45, y: 71)); detail.addLine(to: CGPoint(x: 81, y: 71))
                case .bags:
                    body.addRoundedRect(in: CGRect(x: 21, y: 43, width: 58, height: 39), cornerSize: CGSize(width: 10, height: 10))
                    detail.move(to: CGPoint(x: 34, y: 44)); detail.addLine(to: CGPoint(x: 34, y: 36))
                    detail.addCurve(to: CGPoint(x: 66, y: 36), control1: CGPoint(x: 34, y: 14), control2: CGPoint(x: 66, y: 14))
                    detail.addLine(to: CGPoint(x: 66, y: 44))
                    detail.move(to: CGPoint(x: 23, y: 52)); detail.addQuadCurve(to: CGPoint(x: 77, y: 52), control: CGPoint(x: 50, y: 68))
                    detail.addRoundedRect(in: CGRect(x: 45, y: 58, width: 10, height: 8), cornerSize: CGSize(width: 2, height: 2))
                case .accessories:
                    body.move(to: CGPoint(x: 47, y: 44))
                    body.addCurve(to: CGPoint(x: 19, y: 32), control1: CGPoint(x: 29, y: 17), control2: CGPoint(x: 18, y: 22))
                    body.addQuadCurve(to: CGPoint(x: 20, y: 66), control: CGPoint(x: 14, y: 49))
                    body.addQuadCurve(to: CGPoint(x: 47, y: 54), control: CGPoint(x: 28, y: 77)); body.closeSubpath()
                    body.move(to: CGPoint(x: 53, y: 44))
                    body.addCurve(to: CGPoint(x: 81, y: 32), control1: CGPoint(x: 71, y: 17), control2: CGPoint(x: 82, y: 22))
                    body.addQuadCurve(to: CGPoint(x: 80, y: 66), control: CGPoint(x: 86, y: 49))
                    body.addQuadCurve(to: CGPoint(x: 53, y: 54), control: CGPoint(x: 72, y: 77)); body.closeSubpath()
                    detail.move(to: CGPoint(x: 47, y: 55)); detail.addLine(to: CGPoint(x: 36, y: 82)); detail.addLine(to: CGPoint(x: 48, y: 76))
                    detail.move(to: CGPoint(x: 53, y: 55)); detail.addLine(to: CGPoint(x: 64, y: 82)); detail.addLine(to: CGPoint(x: 52, y: 76))
                    detail.move(to: CGPoint(x: 26, y: 41)); detail.addLine(to: CGPoint(x: 43, y: 49))
                    detail.move(to: CGPoint(x: 74, y: 41)); detail.addLine(to: CGPoint(x: 57, y: 49))
                case .beauty:
                    body.addRoundedRect(in: CGRect(x: 27, y: 40, width: 46, height: 44), cornerSize: CGSize(width: 9, height: 9))
                    detail.addRoundedRect(in: CGRect(x: 40, y: 18, width: 20, height: 15), cornerSize: CGSize(width: 3, height: 3))
                    detail.addRect(CGRect(x: 44, y: 33, width: 12, height: 7))
                    detail.addRoundedRect(in: CGRect(x: 35, y: 52, width: 30, height: 20), cornerSize: CGSize(width: 4, height: 4))
                case .lifestyle:
                    body.move(to: CGPoint(x: 24, y: 48)); body.addLine(to: CGPoint(x: 50, y: 24))
                    body.addLine(to: CGPoint(x: 76, y: 48)); body.addLine(to: CGPoint(x: 76, y: 82))
                    body.addLine(to: CGPoint(x: 24, y: 82)); body.closeSubpath()
                    detail.addRoundedRect(in: CGRect(x: 44, y: 58, width: 14, height: 24), cornerSize: CGSize(width: 3, height: 3))
                    detail.addEllipse(in: CGRect(x: 34, y: 45, width: 12, height: 12))
                    detail.move(to: CGPoint(x: 18, y: 49)); detail.addLine(to: CGPoint(x: 50, y: 18)); detail.addLine(to: CGPoint(x: 82, y: 49))
                case .hat:
                    body.addEllipse(in: CGRect(x: 13, y: 60, width: 74, height: 20))
                    body.move(to: CGPoint(x: 30, y: 65)); body.addLine(to: CGPoint(x: 35, y: 32))
                    body.addQuadCurve(to: CGPoint(x: 65, y: 32), control: CGPoint(x: 50, y: 23))
                    body.addLine(to: CGPoint(x: 70, y: 65)); body.closeSubpath()
                    detail.move(to: CGPoint(x: 33, y: 53)); detail.addQuadCurve(to: CGPoint(x: 68, y: 53), control: CGPoint(x: 50, y: 61))
                case .star:
                    for index in 0..<10 {
                        let angle = Double(index) * .pi / 5 - .pi / 2
                        let radius: Double = index.isMultiple(of: 2) ? 34 : 16
                        let point = CGPoint(x: 50 + cos(angle) * radius, y: 51 + sin(angle) * radius)
                        if index == 0 { body.move(to: point) } else { body.addLine(to: point) }
                    }
                    body.closeSubpath()
                }
                context.fill(body, with: .linearGradient(Gradient(colors: [palette.isDark ? palette.gold.color : .white, palette.iconFill.color]),
                    startPoint: CGPoint(x: 26, y: 23), endPoint: CGPoint(x: 75, y: 87)))
                context.stroke(body, with: .color(palette.accent.color.opacity(0.75)), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                context.stroke(detail, with: .color(palette.accent.color.opacity(0.8)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                if kind == .accessories {
                    let knot = Path(roundedRect: CGRect(x: 44, y: 40, width: 12, height: 19), cornerRadius: 4)
                    context.fill(knot, with: .color(palette.gold.color))
                    context.stroke(knot, with: .color(palette.accent.color.opacity(0.65)), lineWidth: 2)
                }
                let glint = Path(ellipseIn: CGRect(x: 76, y: 19, width: 5, height: 5))
                context.fill(glint, with: .color(palette.gold.color))
            }
    }
}
