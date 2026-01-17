
import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            // Tab 1: 衣橱 (Wardrobe)
            ClothingListView()
                .tabItem {
                    Label("衣橱", systemImage: "tshirt")
                }
            
            // Tab 2: 我的 (Me)
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
