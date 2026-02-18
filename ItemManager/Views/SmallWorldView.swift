//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI

struct SmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.rococo.rawValue
    @State private var isShowingBigWorld = false
    
    var body: some View {
        Group {
            if destination == .bigWorld {
                // 大世界视图
                BigWorldView()
                    .onDisappear {
                        // 返回时重置目的地
                        destination = .menu
                    }
            } else if smallWorldStyle == SmallWorldStyle.rococo.rawValue {
                RococoSmallWorldView(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            } else {
                FrenchRetroSmallWorldView(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            }
        }
    }
}
