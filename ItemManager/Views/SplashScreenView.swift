import SwiftUI

struct SplashScreenView: View {
    var onTapEnter: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            // Background color (optional, matches the app theme or white)
            Color.white.ignoresSafeArea()
            
            // Splash Image
            Image("SplashScreen") // Using the name from Assets.xcassets
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTapEnter?()
        }
    }
}

#Preview {
    SplashScreenView()
}
