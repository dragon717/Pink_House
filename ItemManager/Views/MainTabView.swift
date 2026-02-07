
import SwiftUI

private struct IsSimulationActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isSimulationActive: Bool {
        get { self[IsSimulationActiveKey.self] }
        set { self[IsSimulationActiveKey.self] = newValue }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 衣橱 (Wardrobe)
            HomeView()
                .tabItem {
                    Label {
                        Text("衣橱")
                    } icon: {
                        Image(systemName: selectedTab == 0 ? "cabinet.fill" : "cabinet")
                    }
                }
                .tag(0)
            
            // Tab 2: OOTD
            OOTDView()
                .tabItem {
                    Label("OOTD", systemImage: "tshirt.fill")
                }
                .tag(1)
            
            // Tab 3: 来财 (Wealth)
            WealthView()
                .tabItem {
                    Label("来财", systemImage: "yensign.circle.fill")
                }
                .tag(2)

            // Tab 4: 我的 (Me)
            MeView()
                .tabItem {
                    Label("我的", systemImage: "face.smiling")
                }
                .tag(3)
        }
        .environment(\.isSimulationActive, selectedTab == 2)
    }
}

#Preview {
    MainTabView()
}
