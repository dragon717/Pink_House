
import SwiftUI

struct MoneyStackView: View {
    let denomination: Denomination
    let count: Int
    let currency: CurrencyType
    
    // Config
    // Visual height per note (compressed for isometric view)
    // Real note is ~0.1mm. Width ~155mm. Ratio ~0.00065.
    // Width is 160. Height per note = 160 * 0.00065 ~= 0.104
    // We use 0.1 for realistic thickness.
    let thickness: CGFloat = 0.1
    
    var body: some View {
        // Since the ViewModel now handles splitting into max 1000-count piles,
        // this view just renders a single pile of 'count' size.
        
        // We need to support "Bottom Alignment" visual effect.
        // A full pile (1000) has max height.
        // A partial pile (<1000) should sit at the "bottom" of the virtual 1000-stack space?
        // OR: Just align top-down?
        // User request: "若不满上限， 则置于底部"
        // Interpretation: In the grid cell, if the stack is short, it should be aligned to the bottom of the cell,
        // so it looks like it's sitting on the same surface as other full stacks?
        // Actually, our Grid has overlap.
        // Let's assume the "Top" of the cell is the reference point for the "Top" of the full stack.
        // If we want it "at the bottom", we mean visually lower?
        //
        // Let's look at the current implementation:
        // Top Note is at (0,0). Stack grows DOWN (+Y).
        // If a stack is short (e.g. 100), it occupies Y=0 to Y=10.
        // If a stack is full (1000), it occupies Y=0 to Y=100.
        //
        // If user wants "At Bottom", it implies the "Floor" is fixed.
        // In our perspective, the "Floor" is at Y=100 (for a full stack).
        // So a short stack should be shifted DOWN so its bottom is at Y=100?
        //
        // Yes. Let's calculate offset.
        // Max capacity = 1000.
        // Max Height = 1000 * thickness.
        // Current Height = count * thickness.
        // Offset Y = Max Height - Current Height.
        
        let maxCount = 1000
        let maxStackHeight = CGFloat(maxCount) * thickness
        let currentStackHeight = CGFloat(count) * thickness
        let yOffset = maxStackHeight - currentStackHeight
        
        IsometricBundleView(
            denomination: denomination,
            count: count,
            currency: currency,
            thickness: thickness
        )
        // Shift down to align bottom
        .offset(y: yOffset)
        // Ensure the content is centered and aligned properly for the grid
        // The grid cell expects the visual center to be consistent
        .frame(width: 170, height: 98, alignment: .center) // Reference size, will be scaled by parent
    }
}

struct IsometricBundleView: View {
    let denomination: Denomination
    let count: Int
    let currency: CurrencyType
    let thickness: CGFloat
    
    var stackHeight: CGFloat {
        CGFloat(count) * thickness
    }
    
    var body: some View {
        let width: CGFloat = 160
        let height: CGFloat = 80 // Depth of the bill
        let maxLimit = 1000
        let messyThreshold = maxLimit / 3
        let isMessy = count < messyThreshold
        
        ZStack {
            if isMessy {
                // For small counts (< 1/3), draw messy pile
                // Draw from Bottom (Highest Y) to Top (Lowest Y)
                ForEach(0..<count, id: \.self) { i in
                    let reverseIndex = count - 1 - i
                    
                    // Pseudo-random noise
                    let seed = i * 2654435761 // Knuth's multiplicative hash
                    let rotNoise = Double((seed % 21)) - 10.0 // -10 to 10 degrees
                    let xNoise = CGFloat((seed % 11)) - 5.0 // -5 to 5 points
                    
                    BanknoteLayer(
                        denomination: denomination,
                        currency: currency,
                        rotationOffset: rotNoise
                    )
                    .offset(x: xNoise, y: CGFloat(reverseIndex) * thickness)
                }
            } else {
                // For large counts, draw a solid block + top note
                // Stack grows DOWNWARDS
                
                IsometricBlockSides(
                    color: denomination.color,
                    width: width,
                    depth: height,
                    stackHeight: stackHeight
                )
                .zIndex(-1) // Put sides BEHIND the top note
                
                // 2. The Top Note
                BanknoteLayer(denomination: denomination, currency: currency, showShadow: false)
                    .offset(y: 0) // On top
            }
        }
        // Offset the whole stack so the "Top Note" is centered in the frame
        // Visual center of 170x98 diamond is roughly (0,0) of the ZStack
        // But the stack grows down.
        // If stack is tall, the bottom part goes down.
        // This is fine for "Top" alignment in Grid.
    }
}

// A single layer of banknote (Visual only)
struct BanknoteLayer: View {
    let denomination: Denomination
    let currency: CurrencyType
    var showShadow: Bool = false
    var rotationOffset: Double = 0.0
    
    var body: some View {
        BanknoteView(denomination: denomination, currency: currency, showShadow: showShadow)
            .rotationEffect(.degrees(-45 + rotationOffset)) // Rotate first (with noise)
            .scaleEffect(x: 1.0, y: 0.58) // Then squash for isometric
    }
}

// Efficient rendering of the stack sides using Paths
struct IsometricBlockSides: View {
    let color: Color
    let width: CGFloat
    let depth: CGFloat
    let stackHeight: CGFloat
    
    var body: some View {
        // Dynamic density for solid look
        // We want a solid block.
        // Instead of relying on transparency blending, we use OPAQUE layers with a darker color.
        // This simulates the side of the stack.
        
        let step: CGFloat = 0.5 // High density for smoothness (0.5pt per layer)
        // For 1000 notes (100pt), this is 200 layers.
        // For performance, let's limit the max layers and use thicker steps if needed?
        // Actually, SwiftUI can handle 200 Rects easily.
        // But let's be safe: Max 100 layers.
        
        let rawSteps = Int(stackHeight / step)
        let steps = min(max(rawSteps, 10), 100) // Clamp between 10 and 100 layers
        let adjustedStep = stackHeight / CGFloat(steps)
        
        // Side color should be darker than top
        // Create a darker version of the denomination color
        // Simple way: Overlay black with opacity
        let sideColor = color.opacity(1.0) // Base is opaque
        
        ZStack {
            // Draw layers from bottom to top (or top to bottom, doesn't matter for opaque block)
            // But we want the "Side" look.
            // Correct Z-order: Bottom layers (Higher Y) drawn first.
            
            ForEach(0..<steps, id: \.self) { i in
                let reverseIndex = steps - 1 - i
                BanknoteShape()
                    // Use a gradient or solid darker color?
                    // Solid darker color is best for "Block" look.
                    // We simulate "shading" by making it darker.
                    // But we can't easily modify Color value in SwiftUI without extensions.
                    // We can use .overlay(Color.black.opacity(0.2))
                    .fill(color)
                    .overlay(Color.black.opacity(0.15)) // 15% darker for sides
                    .frame(width: width, height: depth) // Exact size
                    .rotationEffect(.degrees(-45))
                    .scaleEffect(x: 1.0, y: 0.58)
                    .offset(y: CGFloat(reverseIndex) * adjustedStep)
            }
        }
    }
}

struct BanknoteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
        return path
    }
}

#Preview {
    MoneyStackView(
        denomination: Denomination(value: 100, color: .red, name: "100"),
        count: 1000,
        currency: .rmb
    )
}
