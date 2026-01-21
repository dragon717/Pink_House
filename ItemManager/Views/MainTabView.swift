
import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            // Tab 1: 衣橱 (Wardrobe)
            HomeView()
                .tabItem {
                    Label("衣橱", systemImage: "square.grid.2x2.fill")
                }
            
            // Tab 2: OOTD
            OOTDView()
                .tabItem {
                    Label("OOTD", systemImage: "tshirt.fill")
                }
            
            // Tab 3: 我的 (Me)
            MeView()
                .tabItem {
                    Label("我的", systemImage: "face.smiling")
                }
        }
    }
}

#Preview {
    MainTabView()
}
