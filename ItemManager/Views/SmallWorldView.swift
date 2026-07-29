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

    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.bookHouse.rawValue

    var body: some View {
        BookHouseSmallWorldView(
            selectedTab: $selectedTab,
            homeTab: $homeTab,
            destination: $destination,
            isPlayingOpeningAnimation: $isPlayingOpeningAnimation
        )
        .onAppear {
            if smallWorldStyle != SmallWorldStyle.bookHouse.rawValue {
                smallWorldStyle = SmallWorldStyle.bookHouse.rawValue
            }
            // ponytail: ship-hide House room; bounce to wardrobe if somehow opened
            if AppFeatureID.house.isShipHidden {
                homeTab = .wardrobe
                selectedTab = 0
            }
        }
    }
}
