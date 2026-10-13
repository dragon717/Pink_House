import SwiftUI

enum WardrobeStorageFurniturePart: Float { case shelf = 0, crown = 1, base = 2 }

extension View {
    /// The original texture and alpha remain intact; light mode bypasses the shader.
    func wardrobeFurnitureLight(size: CGSize, part: WardrobeStorageFurniturePart, enabled: Bool) -> some View {
        colorEffect(ShaderLibrary.wardrobeFurnitureLight(.float2(Float(size.width), Float(size.height)), .float(part.rawValue)),
                    isEnabled: enabled)
    }

    func wardrobeItemLight(size: CGSize, enabled: Bool) -> some View {
        colorEffect(ShaderLibrary.wardrobeItemLight(.float2(Float(size.width), Float(size.height))), isEnabled: enabled)
    }
}

/// Registered to the shelf texture's recessed opening, including its trapezoidal floor.
private struct WardrobeStorageInterior: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.153, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.847, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.90, y: rect.height * 0.87))
            path.addLine(to: CGPoint(x: rect.width * 0.10, y: rect.height * 0.87))
            path.closeSubpath()
        }
    }
}

struct WardrobeStorageShelfLight: View {
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            // A local wash stops at the opening, so controls and nameplates never receive it.
            Rectangle().fill(LinearGradient(colors: [Color(red: 1, green: 0.75, blue: 0.47).opacity(0.17), .clear],
                                             startPoint: .top, endPoint: .bottom))
                .frame(height: height * 0.72)
            Capsule().fill(Color(red: 1, green: 0.84, blue: 0.61))
                .frame(width: width * 0.62, height: 1.5)
                .shadow(color: Color(red: 1, green: 0.67, blue: 0.32).opacity(0.65), radius: 5, y: 3)
                .padding(.top, 2)
        }
        .frame(width: width, height: height, alignment: .top)
        .clipShape(WardrobeStorageInterior())
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
