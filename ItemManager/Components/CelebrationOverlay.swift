
import SwiftUI

enum CelebrationEffect: CaseIterable {
    case fireworks   // 礼花
    case butterflies // 蝴蝶
}

struct CelebrationOverlay: View {
    @Binding var isPresented: Bool
    var forceEffect: CelebrationEffect? = nil
    
    // Settings
    @AppStorage("isFireworksEnabled") private var isFireworksEnabled = true
    @AppStorage("isButterfliesEnabled") private var isButterfliesEnabled = false
    
    @State private var currentEffect: CelebrationEffect = .fireworks
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isPresented {
                    if currentEffect == .butterflies {
                        ButterflyBoidsView()
                    } else {
                        CelebrationEmitterView(effect: currentEffect)
                    }
                }
            }
            .allowsHitTesting(false) // Allow clicks to pass through
            .onAppear {
                if isPresented {
                    setupEffect()
                }
            }
            .onChange(of: isPresented) { newValue in
                if newValue {
                    setupEffect()
                }
            }
            .task(id: isPresented) {
                if isPresented {
                    // Wait for effect to finish. Most effects take about 5-8 seconds to fully clear.
                    try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
                    isPresented = false
                }
            }
        }
    }
    
    private func setupEffect() {
        if let effect = forceEffect {
            currentEffect = effect
        } else {
            var enabledEffects: [CelebrationEffect] = []
            if isFireworksEnabled { enabledEffects.append(.fireworks) }
            if isButterfliesEnabled { enabledEffects.append(.butterflies) }
            
            // Default to fireworks if nothing enabled (though settings view implies fireworks is default)
            if enabledEffects.isEmpty {
                currentEffect = .fireworks
            } else {
                currentEffect = enabledEffects.randomElement() ?? .fireworks
            }
        }
        
        // 播放音效和震动
        if currentEffect == .fireworks {
            HapticEngineManager.shared.playFireworksHaptic()
        }
    }
}
