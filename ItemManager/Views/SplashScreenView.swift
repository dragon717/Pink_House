import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // Background color (optional, matches the app theme or white)
            Color.white.ignoresSafeArea()
            
            // Splash Image
            Image("SplashScreen") // Using the name from Assets.xcassets
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    SplashScreenView()
}
