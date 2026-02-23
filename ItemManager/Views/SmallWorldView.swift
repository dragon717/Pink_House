//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI

struct SmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.rococo.rawValue
    
    var body: some View {
        Group {
            if smallWorldStyle == SmallWorldStyle.rococo.rawValue {
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
